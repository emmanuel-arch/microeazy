// ─────────────────────────────────────────────────────────────────────────────
// Run the ecosystem locally.
//
//   npm run dev                      every system
//   npm run dev connected-suite      just one
//   npm run dev interchange pwa      a couple
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
// ─────────────────────────────────────────────────────────────────────────────
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { loadRegistry, select, c, colourFor, heading } from "./lib/registry.mjs";

const registry = loadRegistry();
const systems = select(registry, process.argv.slice(2)).filter((s) => s.dev);

const missing = systems.filter((s) => !s.checkedOut);
if (missing.length) {
  console.error(c.red("\n  These submodules are not checked out:\n"));
  for (const s of missing) console.error("    " + s.id + c.dim("  →  " + s.repo));
  console.error(c.dim("\n  Run: git submodule update --init --recursive\n"));
  process.exit(1);
}

const width = Math.max(...systems.map((s) => s.id.length));
const children = [];
let shuttingDown = false;

function run(system, index) {
  const paint = colourFor(index);
  const tag = paint(system.id.padEnd(width)) + c.dim(" │ ");

  const child = spawn(system.dev, {
    cwd: system.dir,
    shell: true,
    // Ports are assigned in registry.json, and passed down so a system's own
    // dev script does not need to hard-code one. PORT is honoured by Next and
    // by Vite, which is every web system here.
    env: { ...process.env, PORT: system.port ? String(system.port) : undefined, FORCE_COLOR: "1" },
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
for (const system of systems) {
  for (const step of system.preDev ?? []) {
    console.log(c.dim("  " + system.id + ": " + step.why));
    const result = spawn(step.cmd, { cwd: system.dir, shell: true, stdio: "ignore" });
    await new Promise((done) => result.on("exit", done));
  }
}

heading("  Micro Eazy — running " + systems.length + " system" + (systems.length === 1 ? "" : "s"));
for (const [i, s] of systems.entries()) {
  const paint = colourFor(i);
  const where = s.url ? c.bold(s.url) : c.dim("no HTTP surface");
  console.log("  " + paint("●") + " " + s.name.padEnd(22) + " " + where);
  for (const door of s.signIn ?? []) {
    if (!s.url) continue;
    console.log(c.dim("      " + door.label.padEnd(26) + " " + s.url + door.path));
  }
}

// A system whose env file is absent will boot and then fail on its first query,
// which reads as a code bug rather than a setup step that was skipped.
const unconfigured = systems.filter((s) => s.env?.file && !existsSync(s.root + "/" + s.env.file));
if (unconfigured.length) {
  console.log(c.yellow("\n  No env file for: " + unconfigured.map((s) => s.id).join(", ")));
  console.log(c.dim("  Run `npm run doctor` for what each one needs."));
}

console.log(c.dim("\n  Ctrl-C stops everything.\n"));
systems.forEach(run);
