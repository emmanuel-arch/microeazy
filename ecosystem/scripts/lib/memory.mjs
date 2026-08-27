// ─────────────────────────────────────────────────────────────────────────────
// What the ecosystem costs to run, and whether this machine can pay it.
//
// This exists because the failure it prevents does not look like a memory
// failure. When Windows runs short of physical RAM it does not report "out of
// memory" — it pages, the desktop stops repainting, and the machine reads as
// crashed. When it runs short of COMMIT it fails a directory rename with
// ACCESS_DENIED, fails a fork inside git-bash, and fails a Turbopack write with
// ERROR_NO_SYSTEM_RESOURCES (os error 1450): three symptoms that each look like
// a permissions or corruption bug and are all the same shortage.
//
// The per-stack numbers live in registry.json, so `doctor` and `dev` cannot
// disagree about what a system costs.
// ─────────────────────────────────────────────────────────────────────────────
import { totalmem, freemem } from "node:os";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

export const GB = 1024 ** 3;

/**
 * The cost of running `systems` in `mode` ("dev" or "start"), in GB.
 *
 * preDev is counted in BOTH modes: the Interchange's PGlite daemon is detached
 * and outlives the server, so serving the built output does not avoid it.
 */
export function budget(registry, systems, mode = "dev") {
  const m = registry.memory;
  const lines = systems.map((s) => {
    const perStack = m.cost[s.stack] ?? {};
    const run = perStack[mode] ?? perStack.dev ?? 0;
    const pre = s.preDev?.length ? m.preDevGb : 0;
    return { system: s, gb: run + pre };
  });

  return {
    mode,
    lines,
    needGb: m.headroomGb + lines.reduce((total, l) => total + l.gb, 0),
    freeGb: freemem() / GB,
    totalGb: totalmem() / GB,
    fits() {
      return this.freeGb >= this.needGb;
    },
  };
}

/** Has this system actually been built? A `start` against no build is a 404 wall. */
export function isBuilt(system) {
  if (!system.buildOutput) return true;
  const out = join(system.dir, system.buildOutput);
  if (!existsSync(out)) return false;
  // Next writes .next for `dev` too. BUILD_ID is only written by `next build`,
  // so it is the one marker that tells a served build from a dev scratch dir.
  if (system.stack === "next") return existsSync(join(out, "BUILD_ID"));
  return true;
}

// ── Is the build worth serving? ──────────────────────────────────────────────
//
// A build that exists is not a build that is current, and `npm run serve` will
// happily serve a stale one without a word. That is a worse failure than an
// absent build: an absent build is a wall of 404s you notice immediately, and a
// stale build is yesterday's code answering confidently in front of an audience.
//
// The case this was written for: the OPRF national-id normalisation landed in
// source, the built output still held the version that tokenised differently,
// and a served exposure query answered "no other lender is reporting a loan to
// you" about a borrower three lenders deep — the exact bug the fix removed.

/** Source extensions worth rebuilding for. Assets are deliberately included. */
const SOURCE = new Set([".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".css", ".prisma", ".json"]);

/** Directories that are output or input, never source. */
const SKIP = new Set(["node_modules", ".next", "dist", ".git", ".turbo", "obj", "bin", "out", "build"]);

/** Newest source mtime under a system, in epoch ms. 0 when there is none. */
export function newestSource(dir, depth = 0) {
  if (depth > 12) return 0;
  let newest = 0;
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return 0;
  }
  for (const entry of entries) {
    if (entry.name.startsWith(".") && entry.name !== ".env") {
      if (SKIP.has(entry.name)) continue;
    }
    if (SKIP.has(entry.name)) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      newest = Math.max(newest, newestSource(full, depth + 1));
    } else {
      const dot = entry.name.lastIndexOf(".");
      if (dot < 0 || !SOURCE.has(entry.name.slice(dot))) continue;
      try {
        newest = Math.max(newest, statSync(full).mtimeMs);
      } catch { /* raced with a write; the next check will see it */ }
    }
  }
  return newest;
}

/**
 * What state this system's build is in.
 *   { needsBuild, built, stale, builtAt, sourceAt }
 * `stale` is advisory — a stale build still runs, and mid-meeting that may be
 * the right call. It is reported, never enforced.
 */
export function buildState(system) {
  if (!system.buildOutput) return { needsBuild: false, built: true, stale: false };
  const built = isBuilt(system);
  if (!built) return { needsBuild: true, built: false, stale: false };

  const out = join(system.dir, system.buildOutput);
  const marker = system.stack === "next" ? join(out, "BUILD_ID") : out;
  let builtAt = 0;
  try {
    builtAt = statSync(marker).mtimeMs;
  } catch { /* checked by isBuilt already */ }

  // Deliberately NOT counting the env file. Server env vars are read at RUNTIME
  // by `next start`, so editing .env and restarting is enough — measured, not
  // assumed: a build made with INTERCHANGE_ALLOW_CODE_LOGIN="1" still refused
  // sign-in once .env said "0", with no rebuild in between. Treating an env edit
  // as staleness would send people off to rebuild for nothing.
  const sourceAt = newestSource(system.root);
  return { needsBuild: true, built: true, stale: sourceAt > builtAt, builtAt, sourceAt };
}

/** "2 days" / "4 hours" / "20 minutes" — for telling a fresh build from a fossil. */
export function ago(ms) {
  const mins = Math.max(0, Math.round((Date.now() - ms) / 60000));
  if (mins < 60) return mins + " minute" + (mins === 1 ? "" : "s");
  const hours = Math.round(mins / 60);
  if (hours < 48) return hours + " hour" + (hours === 1 ? "" : "s");
  return Math.round(hours / 24) + " days";
}

// ── Reclaim ──────────────────────────────────────────────────────────────────
//
// Deliberately REPORTS and never kills. Half of these are someone's meeting —
// 3CX is the softphone ConnectDesk demos against — so the decision is the
// operator's. Matched on process name, case-insensitively.
//
// ⚠ msedgewebview2 IS NOT ON THIS LIST, AND MUST NOT BE.
//
// It is the largest single block of memory on this machine and it is a trap.
// Those processes are not Edge — they are other apps' embedded browsers, and
// each one is supervised by the app that opened it. Measured here: 2.5 GB of
// WebView2 belonged to WhatsApp (879 MB), Teams (664 MB), M365 Copilot (608 MB)
// and the Start menu (350 MB).
//
// Killing them does not free the memory. The parents notice within seconds and
// respawn a fresh webview, which then reloads its content — so the total comes
// back HIGHER than before. Closing 642 MB of WebView2 returned 50 MB, and the
// rebound settled at 2.1 GB.
//
// So webview memory is attributed to the embedder instead, and the embedder is
// what gets offered. Closing the parent is the only thing that actually works.
const RECLAIMABLE = {
  "whatsapp": "WhatsApp",
  "msedge": "Edge windows",
  "brave": "Brave windows",
  "chrome": "Chrome windows",
  "m365copilot": "M365 Copilot",
  "snippingtool": "Snipping Tool",
  "taskmgr": "Task Manager (itself)",
  "3cxsoftphone": "3CX softphone — ConnectDesk demos against this",
  "onedrive": "OneDrive sync",
  "teams": "Teams",
  "spotify": "Spotify",
  "steam": "Steam",
  "slack": "Slack",
  "discord": "Discord",
};

// One app, two process names. WhatsApp runs a `.Root` supervisor beside its
// workers and new Teams is `ms-teams`; reported apart they read as two small
// apps instead of one large one, and the largest thing on the list is exactly
// what the operator needs to see first.
const ALIAS = {
  "whatsapp.root": "whatsapp",
  "ms-teams": "teams",
};

/** Embedder exe name (from --webview-exe-name) → the app it rolls up into. */
const EMBEDDER = {
  "whatsapp.exe": "whatsapp",
  "whatsapp.root.exe": "whatsapp",
  "ms-teams.exe": "teams",
  "teams.exe": "teams",
  "m365copilot.exe": "m365copilot",
};

// One query, because two would see two different machines. Reports each process
// with the embedder it is hosting a webview for, where there is one.
const PROBE = [
  "Get-CimInstance Win32_Process | ForEach-Object {",
  "  $e = ''",
  "  if ($_.Name -eq 'msedgewebview2.exe' -and $_.CommandLine -match '--webview-exe-name=([^\\s\"]+)') { $e = $matches[1] }",
  "  [pscustomobject]@{ n=$_.Name; e=$e; mb=[math]::Round($_.WorkingSetSize/1MB,0) }",
  "} | ConvertTo-Json -Compress",
].join("\n");

/**
 * Apps that could be closed and the memory that would actually come back,
 * biggest first. A webview's memory is billed to the app that opened it, so the
 * number shown is what closing that app really returns — see the note above.
 *
 * Windows-only and best-effort: a machine that will not answer gets an empty
 * list rather than a stack trace, because this is advice, not a gate.
 */
export function reclaimable() {
  if (process.platform !== "win32") return [];
  let rows;
  try {
    const out = execFileSync("powershell", ["-NoProfile", "-NonInteractive", "-Command", PROBE], {
      encoding: "utf8",
      timeout: 20_000,
      maxBuffer: 16 * 1024 * 1024,
      stdio: ["ignore", "pipe", "ignore"],
    });
    rows = JSON.parse(out);
  } catch {
    return [];
  }
  if (!Array.isArray(rows)) rows = [rows];

  const totals = new Map();
  const add = (key, mb) => {
    const at = totals.get(key) ?? { name: key, why: RECLAIMABLE[key], count: 0, mb: 0 };
    at.count += 1;
    at.mb += mb;
    totals.set(key, at);
  };

  for (const row of rows) {
    const exe = String(row.n ?? "").toLowerCase();
    const embedder = String(row.e ?? "").toLowerCase();
    const mb = Number(row.mb) || 0;

    // A webview bills to its embedder. Unattributed webviews (the Start menu's,
    // mostly) are dropped rather than offered: nothing useful can be closed.
    if (embedder) {
      const key = EMBEDDER[embedder];
      if (key && RECLAIMABLE[key]) add(key, mb);
      continue;
    }
    if (exe === "msedgewebview2.exe") continue;

    const raw = exe.replace(/\.exe$/, "");
    const key = ALIAS[raw] ?? raw;
    if (RECLAIMABLE[key]) add(key, mb);
  }

  return [...totals.values()].sort((a, b) => b.mb - a.mb);
}
