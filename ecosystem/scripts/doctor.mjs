// ─────────────────────────────────────────────────────────────────────────────
// Is this machine ready to run the ecosystem?
//
//   npm run doctor
//
// Every check answers a question someone would otherwise answer by reading a
// stack trace: is the submodule checked out, are dependencies installed, does
// the env file exist, is the port free, is the required variable actually set.
//
// It NEVER prints a secret. Env checks report presence and nothing else — a
// doctor script that echoes DATABASE_URL is one screen-share away from being an
// incident.
// ─────────────────────────────────────────────────────────────────────────────
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { createServer } from "node:net";
import { execSync } from "node:child_process";
import { loadRegistry, select, c, heading, ROOT } from "./lib/registry.mjs";

let problems = 0;
const ok = (label, detail) => console.log("  " + c.green("✓") + " " + label + (detail ? c.dim("  " + detail) : ""));
const bad = (label, fix) => { problems++; console.log("  " + c.red("✗") + " " + label + (fix ? "\n      " + c.dim(fix) : "")); };
const warn = (label, detail) => console.log("  " + c.yellow("!") + " " + label + (detail ? "\n      " + c.dim(detail) : ""));

function portFree(port) {
  return new Promise((resolve) => {
    const server = createServer();
    server.once("error", () => resolve(false));
    server.once("listening", () => server.close(() => resolve(true)));
    server.listen(port, "127.0.0.1");
  });
}

/** Which keys a .env actually defines, without reading a single value. */
function envKeys(file) {
  try {
    return new Set(
      readFileSync(file, "utf8")
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l && !l.startsWith("#"))
        .map((l) => l.split("=")[0].trim())
        .filter(Boolean),
    );
  } catch {
    return new Set();
  }
}

const registry = loadRegistry();
const systems = select(registry, process.argv.slice(2));

// ── Toolchain ────────────────────────────────────────────────────────────────
heading("  Toolchain");
const node = process.versions.node;
Number(node.split(".")[0]) >= 20
  ? ok("Node " + node)
  : bad("Node " + node + " is too old", "The Suite and the Interchange are both Next 16 — Node 20+.");

for (const [tool, cmd, needed] of [
  ["git", "git --version", true],
  ["npm", "npm --version", true],
  ["dotnet", "dotnet --version", systems.some((s) => s.stack === "dotnet-worker")],
]) {
  if (!needed) continue;
  try {
    ok(tool, execSync(cmd, { stdio: ["ignore", "pipe", "ignore"] }).toString().trim());
  } catch {
    bad(tool + " is not on PATH");
  }
}

// ── Systems ──────────────────────────────────────────────────────────────────
for (const s of systems) {
  heading("  " + s.name + c.dim("  (" + s.id + ")"));

  if (!s.checkedOut) {
    bad("not checked out", "git submodule update --init --recursive");
    continue;
  }
  ok("checked out", s.path + (s.workdir ? "/" + s.workdir : ""));

  // Dependencies
  if (s.stack === "dotnet-worker") {
    existsSync(join(s.dir, "obj")) ? ok("restored") : warn("not restored yet", "npm run bootstrap " + s.id);
  } else {
    existsSync(join(s.dir, "node_modules"))
      ? ok("dependencies installed")
      : bad("node_modules missing", "npm run bootstrap " + s.id);
  }

  // Environment
  if (s.env?.file) {
    const file = join(s.root, s.env.file);
    if (existsSync(file)) {
      const keys = envKeys(file);
      ok("env present", s.env.file + c.dim(" · " + keys.size + " keys"));

      // Only the variables without which the system cannot boot at all.
      const required = {
        "connected-suite": ["DATABASE_URL", "NEXTAUTH_SECRET"],
        interchange: ["DATABASE_URL", "INTERCHANGE_SESSION_SECRET"],
        pwa: ["VITE_ENTITY_ID"],
      }[s.id] ?? [];

      const absent = required.filter((k) => !keys.has(k));
      absent.length
        ? bad("missing in " + s.env.file + ": " + absent.join(", "), "See " + (s.env.example ?? "the README") + ".")
        : required.length && ok("required variables set", required.join(", "));
    } else {
      bad("no " + s.env.file, s.env.example ? "cp " + s.env.example + " " + s.env.file : "Create it — see the README.");
    }
  }

  // Port
  if (s.port) {
    (await portFree(s.port))
      ? ok("port " + s.port + " free")
      : warn("port " + s.port + " is in use", "Either this system is already running, or something else took it.");
  }
}

// ── Meta-repo ────────────────────────────────────────────────────────────────
heading("  Meta-repo");
if (existsSync(join(ROOT, ".gitmodules"))) {
  ok(".gitmodules present");
  try {
    const status = execSync("git submodule status", { cwd: ROOT, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    for (const line of status.split("\n").filter(Boolean)) {
      // A leading '-' means uninitialised, '+' means the checkout is off the
      // pinned commit — the two states that make "it works on my machine" true.
      const flag = line[0];
      const name = line.trim().split(/\s+/)[1];
      if (flag === "-") bad(name + " uninitialised", "git submodule update --init --recursive");
      else if (flag === "+") warn(name + " is not at the pinned commit", "Commit the pointer in the meta-repo, or check out the pin.");
      else ok(name + " at pinned commit");
    }
  } catch {
    warn("could not read submodule status");
  }
} else {
  warn("no .gitmodules yet", "The meta-repo has not been wired. See ecosystem/ADDING-A-SYSTEM.md.");
}

console.log(
  "\n  " + (problems === 0 ? c.green("ready") : c.red(problems + " problem" + (problems === 1 ? "" : "s") + " to fix")) + "\n",
);
process.exit(problems === 0 ? 0 : 1);
