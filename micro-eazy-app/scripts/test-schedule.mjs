// ─────────────────────────────────────────────────────────────────────────────
// THE SCHEDULE ARITHMETIC, CHECKED.
//
//   npm run test:schedule
//
// This is the one piece of the app where being wrong by a cent is a real defect
// rather than a cosmetic one: a schedule that does not sum to the total is a
// schedule the server will reject after the customer has spent two minutes
// building it, or — worse — one it accepts and then reconciles against a
// different figure.
//
// A screenshot cannot catch that, so it is checked here instead. The cases that
// matter are the ugly ones: instalment counts where the integer division leaves
// a remainder (13, 24), skipping the LAST row when there is nowhere forward to
// push the money, and presets applied to a schedule that already has settled
// rows locked in it.
//
// esbuild is already a dependency of Vite, so this needs no new tooling.
// ─────────────────────────────────────────────────────────────────────────────
import { build } from "esbuild";
import { pathToFileURL } from "node:url";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const outfile = join(mkdtempSync(join(tmpdir(), "microeazy-")), "reshape.mjs");
await build({
  entryPoints: ["src/lib/schedule/reshape.ts"],
  outfile,
  format: "esm",
  bundle: true,
  logLevel: "error",
});

const { applyPreset, balance, isBalanced, skip, sum, setRow, toCents } = await import(
  pathToFileURL(outfile).href
);

/** The real Micro Eazy shape: 5,000 borrowed, 4,125 interest, ten weeks. */
const TOTAL = toCents(9125);
const rowsOf = (n) =>
  Array.from({ length: n }, (_, i) => ({ seq: i + 1, dueDate: "2026-09-06", cents: TOTAL / n }));

let failed = 0;
const check = (name, cond, extra = "") => {
  if (!cond) failed++;
  console.log(`  ${cond ? "[32mPASS[0m" : "[31mFAIL[0m"}  ${name}${extra}`);
};

// ── The invariant everything else rests on ───────────────────────────────────
// Counts chosen so integer division does NOT come out even: 9125 / 13 and
// 9125 / 24 both leave a remainder, which is exactly where a naive
// implementation loses or invents a cent.
for (const n of [1, 2, 3, 5, 7, 10, 13, 24]) {
  for (const preset of ["even", "front", "back"]) {
    const rows = applyPreset(rowsOf(n), TOTAL, preset);
    check(`${preset} n=${n} sums exactly`, sum(rows) === TOTAL, `  (off by ${sum(rows) - TOTAL})`);
    check(`${preset} n=${n} no negative instalment`, rows.every((r) => r.cents >= 0));
  }
}

// ── The presets have to do what they say ─────────────────────────────────────
const front = applyPreset(rowsOf(10), TOTAL, "front");
check("front-load: first week heavier than last", front[0].cents > front[9].cents);
const back = applyPreset(rowsOf(10), TOTAL, "back");
check("back-load: last week heavier than first", back[9].cents > back[0].cents);

// ── Skipping ─────────────────────────────────────────────────────────────────
const skipped = skip(rowsOf(10), 3, TOTAL);
check("skip zeroes that week", skipped[2].cents === 0);
check("skip loses nothing", sum(skipped) === TOTAL, `  (off by ${sum(skipped) - TOTAL})`);
check("skip pushes onto the next week", skipped[3].cents === (TOTAL / 10) * 2);

const skippedLast = skip(rowsOf(10), 10, TOTAL);
check("skipping the LAST week still balances", sum(skippedLast) === TOTAL, `  (off by ${sum(skippedLast) - TOTAL})`);

// ── Clamping ─────────────────────────────────────────────────────────────────
check("an instalment cannot exceed the total", setRow(rowsOf(10), 1, TOTAL * 5, TOTAL)[0].cents === TOTAL);
check("an instalment cannot go negative", setRow(rowsOf(10), 1, -500, TOTAL)[0].cents === 0);

// ── Settled rows are history ─────────────────────────────────────────────────
const withLocked = rowsOf(10).map((r, i) => (i < 3 ? { ...r, locked: true } : r));
const afterPreset = applyPreset(withLocked, TOTAL, "back");
check("locked rows are not moved", afterPreset.slice(0, 3).every((r) => r.cents === TOTAL / 10));
check("preset around locked rows still sums", sum(afterPreset) === TOTAL, `  (off by ${sum(afterPreset) - TOTAL})`);

// ── balance() is the "fix it for me" button ──────────────────────────────────
let gapped = setRow(rowsOf(10), 5, 0, TOTAL);
check("a gap is detected", !isBalanced(gapped, TOTAL));
gapped = balance(gapped, TOTAL);
check("balance() closes the gap exactly", isBalanced(gapped, TOTAL), `  (off by ${sum(gapped) - TOTAL})`);

console.log(failed ? `\n  ${failed} check(s) failed\n` : "\n  all green\n");
process.exit(failed ? 1 : 0);
