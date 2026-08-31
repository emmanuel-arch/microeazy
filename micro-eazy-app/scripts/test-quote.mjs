// ─────────────────────────────────────────────────────────────────────────────
// THE QUOTE ARITHMETIC, CHECKED AGAINST THE SERVER'S.
//
//   npm run test:quote
//
// lib/quote.ts is a port of buildSchedule() in the Connected Suite, and a port
// is a copy that is one edit away from disagreeing with its original. When it
// does, the customer sees one price on the comparison screen and a different
// one on the agreement — which is not a rounding argument, it is the single
// thing that makes somebody close a lending app and not come back.
//
// So the figures below are the ones the server actually produces, written down.
// The most important assertion is not any individual number: it is that the
// rows sum to the total IN INTEGER CENTS, exactly, because that is the
// invariant the schedule editor's whole "Balanced" state rests on. A quote whose
// rows are a cent short hands the customer a workspace they cannot finish.
//
// esbuild is already a dependency of Vite, so this needs no new tooling.
// ─────────────────────────────────────────────────────────────────────────────
import { build } from "esbuild";
import { pathToFileURL } from "node:url";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const outfile = join(mkdtempSync(join(tmpdir(), "microeazy-quote-")), "quote.mjs");
await build({
  entryPoints: ["src/lib/quote.ts"],
  outfile,
  format: "esm",
  bundle: true,
  logLevel: "error",
});

const { quote, wholeTermRate, affordableRange } = await import(pathToFileURL(outfile).href);

let failed = 0;
const check = (name, cond, extra = "") => {
  if (!cond) failed++;
  console.log(`  ${cond ? "\x1b[32mPASS\x1b[0m" : "\x1b[31mFAIL\x1b[0m"}  ${name}${extra}`);
};

const sumCents = (rows) => rows.reduce((n, r) => n + r.cents, 0);

/** Micromart's live product, exactly as /api/lms/products restates it. */
const WEEKLY = {
  id: "micro-eazy", name: "Micro Eazy", description: null,
  minPrincipal: 1_000, maxPrincipal: 50_000,
  interestRate: 8.25, interestUnit: "week", interestMethod: "flat",
  repaymentPeriod: 10, repaymentUnit: "week", minCreditScore: 400,
};

const MONTHLY = {
  id: "micro-eazy-monthly", name: "Micro Eazy Monthly", description: null,
  minPrincipal: 10_000, maxPrincipal: 150_000,
  interestRate: 12, interestUnit: "month", interestMethod: "reducing",
  repaymentPeriod: 4, repaymentUnit: "month", minCreditScore: 620,
};

console.log("\nWhole-term rate — the per-period display rate, multiplied back up");
check("8.25%/week over 10 weeks is 82.5% for the term", wholeTermRate(WEEKLY) === 82.5);
check("12%/month over 4 months is 48% for the term", wholeTermRate(MONTHLY) === 48);
check(
  "a rate already quoted for the term is not multiplied again",
  wholeTermRate({ ...WEEKLY, interestRate: 82.5, interestUnit: "term" }) === 82.5,
);
check(
  "a MONTHLY rate on a WEEKLY product converts through days, it does not assume",
  // 5%/month on a 10-week product ≈ 5 × (7/30) × 10 = 11.67%, NOT 50%.
  wholeTermRate({ ...WEEKLY, interestRate: 5, interestUnit: "month" }) === 11.67,
);

console.log("\nThe live Micro Eazy shape — 5,000 over ten weeks");
const q = quote(WEEKLY, 5_000);
check("interest is 4,125", q.totalInterest === 4_125, `  (got ${q.totalInterest})`);
check("total repayable is 9,125", q.totalRepayable === 9_125, `  (got ${q.totalRepayable})`);
check("ten rows", q.rows.length === 10);
check("each instalment is 912.50", q.perPeriod === 912.5, `  (got ${q.perPeriod})`);
check(
  "THE INVARIANT: rows sum to the total, exactly, in integer cents",
  sumCents(q.rows) === 912_500,
  `  (got ${sumCents(q.rows)})`,
);
check("the first due date is one week out, not today", new Date(q.rows[0].dueDate) > new Date());
check("flat interest does not reward early settlement", q.earlySettlementApplies === false);

console.log("\nReducing balance — 40,000 over four months");
const r = quote(MONTHLY, 40_000);
check("four rows", r.rows.length === 4);
check(
  "THE INVARIANT holds on reducing balance too",
  sumCents(r.rows) === Math.round(r.totalRepayable * 100),
  `  (rows ${sumCents(r.rows)} vs total ${Math.round(r.totalRepayable * 100)})`,
);
check("instalments fall as the balance does", r.rows[0].cents > r.rows[3].cents);
check("reducing balance does reward early settlement", r.earlySettlementApplies === true);
check(
  "principal is fully repaid — the total is principal plus interest and nothing else",
  Math.round((r.totalRepayable - r.totalInterest) * 100) === 4_000_000,
);

console.log("\nThe ugly ones — terms where the division leaves a remainder");
for (const [periods, principal] of [[3, 10_000], [7, 5_000], [13, 9_999], [24, 33_333]]) {
  const ugly = quote({ ...WEEKLY, repaymentPeriod: periods }, principal);
  check(
    `${periods} instalments of ${principal} still sum exactly`,
    sumCents(ugly.rows) === Math.round(ugly.totalRepayable * 100),
    `  (off by ${sumCents(ugly.rows) - Math.round(ugly.totalRepayable * 100)} cents)`,
  );
}

console.log("\nWhat a customer may actually ask for");
check("a limit above the minimum opens the product", affordableRange(WEEKLY, 45_000)?.max === 45_000);
check("the product ceiling still applies below the limit", affordableRange(WEEKLY, 90_000)?.max === 50_000);
check(
  "a limit below the minimum closes it, rather than quoting a loan that cannot book",
  affordableRange(MONTHLY, 4_000) === null,
);

console.log(failed ? `\n\x1b[31m${failed} failed\x1b[0m\n` : "\n\x1b[32mAll good\x1b[0m\n");
process.exit(failed ? 1 : 0);
