// ─────────────────────────────────────────────────────────────────────────────
// Run one registry command across systems, in sequence, and report honestly.
//
//   node ecosystem/scripts/run.mjs install [ids…]
//   node ecosystem/scripts/run.mjs build   [ids…]
//
// SEQUENTIAL, not parallel. Four npm installs at once on Windows contend on the
// same cache and turn a slow operation into a flaky one. Builds are sequential
// for a plainer reason: when one fails you want to be reading its output, not
// hunting for it between three others.
//
// The exit code is the point. A bootstrap that prints an error and exits 0 is
// how CI goes green on a broken tree.
// ─────────────────────────────────────────────────────────────────────────────
import { spawnSync } from "node:child_process";
import { loadRegistry, select, c, heading } from "./lib/registry.mjs";

const [, , key, ...rest] = process.argv;
if (!key) {
  console.error("usage: run.mjs <install|build> [system…]");
  process.exit(1);
}

// `start` used to be routed here, and could never have worked. This runner is
// sequential and blocking by design — correct for install and build, wrong for
// anything long-lived: it would launch the first server, block on it forever and
// never reach the second. Servers go through the supervisor in dev.mjs, which
// spawns them in parallel and kills the tree on Ctrl-C.
if (key === "start") {
  console.error(
    "\n  `start` does not run here — this runner blocks on each system in turn,\n" +
      "  so it would launch the first server and never reach the second.\n\n" +
      "    npm run serve                 every system, from its built output\n" +
      "    npm run serve -- interchange  just one\n",
  );
  process.exit(1);
}

const registry = loadRegistry();
const systems = select(registry, rest);

const results = [];
for (const s of systems) {
  const command = s[key];
  if (!command) {
    results.push({ s, status: "skipped", why: "no " + key + " command" });
    continue;
  }
  if (!s.checkedOut) {
    results.push({ s, status: "skipped", why: "not checked out" });
    continue;
  }

  heading("  " + s.name + c.dim("  ·  " + command));
  const started = Date.now();
  const proc = spawnSync(command, { cwd: s.dir, shell: true, stdio: "inherit", env: { ...process.env, FORCE_COLOR: "1" } });
  const seconds = ((Date.now() - started) / 1000).toFixed(1);

  results.push({
    s,
    status: proc.status === 0 ? "ok" : "failed",
    why: proc.status === 0 ? seconds + "s" : "exit " + proc.status,
  });
}

heading("  " + key);
for (const r of results) {
  const mark = r.status === "ok" ? c.green("✓") : r.status === "failed" ? c.red("✗") : c.dim("–");
  console.log("  " + mark + " " + r.s.id.padEnd(18) + c.dim(r.why));
}

const failed = results.filter((r) => r.status === "failed");
console.log(
  "\n  " + (failed.length === 0 ? c.green("all " + key + " succeeded") : c.red(failed.length + " failed")) + "\n",
);
process.exit(failed.length ? 1 : 0);
