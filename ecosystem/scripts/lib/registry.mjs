// Shared registry loader. Every orchestration script goes through this, so
// "what is in the ecosystem" is answered in exactly one place.
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

/** The meta-repo root — three levels up from ecosystem/scripts/lib. */
export const ROOT = resolve(here, "..", "..", "..");
export const REGISTRY_PATH = join(ROOT, "ecosystem", "registry.json");

export function loadRegistry() {
  if (!existsSync(REGISTRY_PATH)) {
    throw new Error("No registry at " + REGISTRY_PATH);
  }
  const registry = JSON.parse(readFileSync(REGISTRY_PATH, "utf8"));

  for (const s of registry.systems) {
    // The directory a command actually runs in. Distinct from `path` because a
    // monorepo submodule (the Interchange) is checked out at its root but built
    // from apps/interchange-console.
    s.dir = s.workdir ? join(ROOT, s.path, s.workdir) : join(ROOT, s.path);
    s.root = join(ROOT, s.path);
    // A submodule that has never been initialised is an empty directory. Telling
    // that apart from a missing checkout is the difference between a useful
    // message and "command not found".
    s.present = existsSync(s.dir) && existsSync(join(s.dir, s.stack === "dotnet-worker" ? "." : "package.json"));
    s.checkedOut = existsSync(s.root) && readdirSafe(s.root).length > 0;
    s.url = s.port ? "http://localhost:" + s.port : null;
  }
  return registry;
}

function readdirSafe(p) {
  try {
    return readdirSync(p);
  } catch {
    return [];
  }
}

/** Filter by ids given on the command line; everything when none were given. */
export function select(registry, argv) {
  const ids = argv.filter((a) => !a.startsWith("-"));
  if (!ids.length) return registry.systems;
  const chosen = [];
  for (const id of ids) {
    const found = registry.systems.find((s) => s.id === id || s.short?.toLowerCase() === id.toLowerCase());
    if (!found) {
      throw new Error(
        'Unknown system "' + id + '". Known: ' + registry.systems.map((s) => s.id).join(", "),
      );
    }
    chosen.push(found);
  }
  return chosen;
}

// ── Terminal ─────────────────────────────────────────────────────────────────
const useColour = process.stdout.isTTY && !process.env.NO_COLOR;
const wrap = (code) => (s) => (useColour ? "\x1b[" + code + "m" + s + "\x1b[0m" : String(s));

export const c = {
  bold: wrap("1"),
  dim: wrap("2"),
  red: wrap("31"),
  green: wrap("32"),
  yellow: wrap("33"),
  blue: wrap("34"),
  magenta: wrap("35"),
  cyan: wrap("36"),
};

/** A stable colour per system, so one system's output is scannable in a mixed log. */
const PALETTE = [c.cyan, c.magenta, c.yellow, c.green, c.blue];
export function colourFor(index) {
  return PALETTE[index % PALETTE.length];
}

export function heading(text) {
  console.log("\n" + c.bold(text));
  console.log(c.dim("─".repeat(Math.max(text.length, 40))));
}
