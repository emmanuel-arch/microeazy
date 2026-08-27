// ─────────────────────────────────────────────────────────────────────────────
// Run the ecosystem locally.
//
//   npm run dev                      every system, in dev mode
//   npm run dev connected-suite      just one
//   npm run dev interchange pwa      a couple
//
//   npm run serve                    every system, SERVING THE BUILT OUTPUT
//   npm run serve interchange        just one
//
// Output is INTERLEAVED AND PREFIXED rather than split across terminals. That is
// the point of running them together: the interesting failures in a federated
// system are the ones where the Suite calls the Interchange and the Interchange
// says no, and you cannot see that in two windows you are not looking at.
//
// Ctrl-C stops everything. Each child is killed by process TREE on Windows —
// `next dev` spawns Turbopack workers that survive a plain SIGTERM to the parent
// and then hold the port, so the next `npm run dev` fails with EADDRINUSE on a
// server nobody can see.
//
// ── WHY THERE ARE TWO MODES ──────────────────────────────────────────────────
//
// `--built` runs each system's `start` instead of its `dev`. It is not a
// convenience: on an 8 GB machine it is the difference between running the
// ecosystem and not. Two Turbopack dev servers want ~1.9 GB each and the whole
// set does not fit beside an editor, so `npm run dev` across everything pages
// Windows until the desktop stops repainting — which reads as a crash, not as a
// shortage. Served builds cost ~0.3 GB each and the same set fits with room
// over.
//
// The trade is real and it is the only one: no hot reload, and an edit is not
// visible until you rebuild. Demo from `serve`; develop from `dev`, one system
// at a time.
// ─────────────────────────────────────────────────────────────────────────────
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { loadRegistry, select, c, colourFor, heading } from "./lib/registry.mjs";
import { budget, isBuilt, buildState, ago, reclaimable } from "./lib/memory.mjs";

const argv = process.argv.slice(2);
const has = (...names) => names.some((n) => argv.includes(n));

const built = has("--built", "--prod");
const force = has("--force");
const mode = built ? "start" : "dev";

const registry = loadRegistry();
const systems = select(registry, argv).filter((s) => s[mode]);

const missing = systems.filter((s) => !s.checkedOut);
if (missing.length) {
  console.error(c.red("\n  These submodules are not checked out:\n"));
  for (const s of missing) console.error("    " + s.id + c.dim("  →  " + s.repo));
  console.error(c.dim("\n  Run: git submodule update --init --recursive\n"));
  process.exit(1);
}

// ── Serving something that was never built is a wall of 404s ─────────────────
if (built) {
  const unbuilt = systems.filter((s) => !isBuilt(s));
  if (unbuilt.length) {
    console.error(c.red("\n  No build to serve for: " + unbuilt.map((s) => s.id).join(", ") + "\n"));
    console.error("    npm run build -- " + unbuilt.map((s) => s.id).join(" "));
    console.error(c.dim("\n  Build one at a time when memory is tight. A build that fails is"));
    console.error(c.dim("  recoverable; a machine that pages to death mid-demo is not.\n"));
    process.exit(1);
  }

  // Reported, never enforced. A stale build still runs, and ten minutes before a
  // demo that is sometimes the right call — but it has to be a call, not a thing
  // you discover from the audience's questions.
  const stale = systems.filter((s) => buildState(s).stale);
  if (stale.length) {
    console.log(c.yellow("\n  Stale build: " + stale.map((s) => s.id).join(", ")));
    for (const s of stale) {
      const b = buildState(s);
      console.log(
        c.dim("    " + s.id.padEnd(16) + " built " + ago(b.builtAt) + " ago, source changed " + ago(b.sourceAt) + " ago"),
      );
    }
    console.log(c.dim("  You are about to serve the older code."));
    console.log(c.dim("  npm run build -- " + stale.map((s) => s.id).join(" ")));
  }
}

// ── Will this fit? ───────────────────────────────────────────────────────────
//
// Checked BEFORE anything is spawned, because the failure being prevented is one
// where you cannot get back to the terminal to stop it.
const plan = budget(registry, systems, mode);

if (!plan.fits() && !force) {
  console.error(
    c.red("\n  Not enough memory for this.") +
      c.dim("  " + plan.freeGb.toFixed(1) + " GB free of " + plan.totalGb.toFixed(1) + " GB\n"),
  );

  const label = Math.max(...plan.lines.map((l) => l.system.id.length), 9);
  for (const line of plan.lines) {
    console.error("    " + line.system.id.padEnd(label) + c.dim("  " + line.gb.toFixed(2) + " GB  " + mode));
  }
  console.error("    " + "headroom".padEnd(label) + c.dim("  " + registry.memory.headroomGb.toFixed(2) + " GB"));
  console.error("    " + c.bold("needs".padEnd(label)) + c.dim("  " + plan.needGb.toFixed(2) + " GB"));

  const named = argv.filter((a) => !a.startsWith("-"));
  if (!built) {
    console.error(c.yellow("\n  Serve the built output instead — same systems, a fraction of the cost:"));
    console.error("    npm run serve" + (named.length ? " -- " + named.join(" ") : ""));
  }
  if (systems.length > 1) {
    console.error(c.yellow("\n  Or run one at a time:"));
    console.error("    npm run " + (built ? "serve" : "dev") + " -- " + systems[0].id);
  }

  const canFree = reclaimable();
  if (canFree.length) {
    console.error(c.yellow("\n  Or close some of these first:"));
    for (const p of canFree.slice(0, 8)) {
      const name = p.name + (p.count > 1 ? c.dim(" ×" + p.count) : "");
      console.error("    " + String(p.mb).padStart(5) + " MB  " + name + c.dim("  " + p.why));
    }
  }

  console.error(c.dim("\n  --force runs it anyway.\n"));
  process.exit(1);
}

const width = Math.max(...systems.map((s) => s.id.length));
const children = [];
let shuttingDown = false;

function run(system, index) {
  const paint = colourFor(index);
  const tag = paint(system.id.padEnd(width)) + c.dim(" │ ");

  // `{{port}}` is substituted from the registry for the systems whose CLI will
  // not read PORT out of the environment. Vite is the one that matters here:
  // `vite` defaults to 5173 and `vite preview` defaults to 4173, and neither
  // reads PORT — so the PWA silently moved ports the moment it was served
  // rather than dev'd, while every banner and link still said 5173.
  const command = system[mode].replaceAll("{{port}}", String(system.port ?? ""));

  const child = spawn(command, {
    cwd: system.dir,
    shell: true,
    // Ports are assigned in registry.json, and passed down so a system's own
    // dev script does not need to hard-code one. PORT is honoured by Next and
    // by Vite, which is every web system here.
    //
    // The heap cap is a seatbelt, not a diet: it does not make a server want
    // less than it needs, it stops one runaway compile from taking the machine
    // with it. A server that hits the cap dies with a heap trace you can read,
    // minutes before Windows would have started paging.
    env: {
      ...process.env,
      PORT: system.port ? String(system.port) : undefined,
      NODE_OPTIONS: [process.env.NODE_OPTIONS, "--max-old-space-size=" + registry.memory.heapCapMb]
        .filter(Boolean)
        .join(" "),
      FORCE_COLOR: "1",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  const pipe = (stream) => {
    let buffer = "";
    stream.on("data", (chunk) => {
      buffer += chunk.toString();
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) console.log(tag + line);
    });
  };
  pipe(child.stdout);
  pipe(child.stderr);

  child.on("exit", (code) => {
    if (shuttingDown) return;
    console.log(tag + c.red("exited with code " + code));
  });

  children.push(child);
}

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(c.dim("\n  stopping…"));
  for (const child of children) {
    if (child.pid == null) continue;
    if (process.platform === "win32") {
      // /T kills the tree. Without it the Turbopack workers outlive the parent
      // and keep the port, which looks exactly like "the server is still running"
      // right up until you try to reach it.
      spawn("taskkill", ["/pid", String(child.pid), "/T", "/F"], { stdio: "ignore" });
    } else {
      try { process.kill(-child.pid, "SIGTERM"); } catch { child.kill("SIGTERM"); }
    }
  }
  setTimeout(() => process.exit(0), 700);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

// ── Pre-flight: anything a system needs standing up before it starts ─────────
//
// Runs in both modes. The Interchange's PGlite daemon is what the console talks
// to, and serving a built console against no database fails at the first query
// rather than at boot.
for (const system of systems) {
  for (const step of system.preDev ?? []) {
    console.log(c.dim("  " + system.id + ": " + step.why));
    const result = spawn(step.cmd, { cwd: system.dir, shell: true, stdio: "ignore" });
    await new Promise((done) => result.on("exit", done));
  }
}

heading(
  "  Micro Eazy — " +
    (built ? "serving " : "running ") +
    systems.length +
    " system" +
    (systems.length === 1 ? "" : "s") +
    (built ? " from built output" : ""),
);
for (const [i, s] of systems.entries()) {
  const paint = colourFor(i);
  const where = s.url ? c.bold(s.url) : c.dim("no HTTP surface");
  console.log("  " + paint("●") + " " + s.name.padEnd(22) + " " + where);
  for (const door of s.signIn ?? []) {
    if (!s.url) continue;
    console.log(c.dim("      " + door.label.padEnd(26) + " " + s.url + door.path));
  }
}

console.log(
  c.dim(
    "\n  " +
      plan.needGb.toFixed(1) +
      " GB expected · " +
      plan.freeGb.toFixed(1) +
      " GB free" +
      (built ? "  ·  no hot reload — rebuild to see an edit" : ""),
  ),
);

// A system whose env file is absent will boot and then fail on its first query,
// which reads as a code bug rather than a setup step that was skipped.
const unconfigured = systems.filter((s) => s.env?.file && !existsSync(s.root + "/" + s.env.file));
if (unconfigured.length) {
  console.log(c.yellow("\n  No env file for: " + unconfigured.map((s) => s.id).join(", ")));
  console.log(c.dim("  Run `npm run doctor` for what each one needs."));
}

console.log(c.dim("\n  Ctrl-C stops everything.\n"));
systems.forEach(run);
