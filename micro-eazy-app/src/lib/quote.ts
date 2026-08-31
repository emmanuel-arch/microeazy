// ─────────────────────────────────────────────────────────────────────────────
// THE QUOTE — what a product costs, before there is an application.
//
// ── THIS FILE APPEARS TO CONTRADICT reshape.ts, AND DOES NOT ────────────────
// lib/schedule/reshape.ts says, in capitals, that interest is computed in
// exactly one place and never in the client. That rule is about the OFFER: the
// numbers a customer signs and the numbers the lender books have to come from
// one function, or the day they drift somebody signs one figure and owes
// another.
//
// A QUOTE is a different object with a different job. It is the shop window —
// "KSh 5,000 over ten weeks costs you KSh 4,125" — and it exists before any
// application row does, so there is nothing on the server to ask. Every lender
// in this market publishes one; the ones that do not are the ones customers
// distrust, because a product you cannot price until after you have applied is
// a product you are being walked into.
//
// The boundary is enforced by the TYPES rather than by good intentions:
//
//   Quote   is produced here, is marked indicative on every screen that shows
//           it, and is accepted by ProductChoice and by the schedule editor.
//   Offer   comes only from GET /api/portal/offer/:id, and is the ONLY thing
//           LoanAgreement will render or sign. There is no path from a Quote
//           to a signature.
//
// So a drift between this arithmetic and the lender's is a cosmetic bug on a
// comparison screen, not a contractual one — and to keep even that from
// happening, the two branches below are a line-for-line port of buildSchedule
// in connected-suite/src/lib/lending/schedule.ts, including its rounding and
// its remainder convention. scripts/test-quote.mjs checks them against the
// same figures the server produces.
// ─────────────────────────────────────────────────────────────────────────────
import { toCents, type Row } from "./schedule/reshape";

/** Two decimals, the server's convention. Ported verbatim so the two agree. */
const round2 = (n: number) => Math.round(n * 100) / 100;

/** One row of a lender's shelf, as POST /api/lms/products returns it. */
export interface Product {
  id: string;
  name: string;
  description: string | null;
  minPrincipal: number;
  maxPrincipal: number;
  /** As published — per `interestUnit`, NOT per term. See wholeTermRate(). */
  interestRate: number;
  interestUnit: string;
  interestMethod: "flat" | "reducing";
  repaymentPeriod: number;
  repaymentUnit: string;
  minCreditScore: number | null;
  disbursementMode?: string;
  /**
   * The lender's own charges, when the catalogue carries them.
   *
   * KNOWN GAP, STATED RATHER THAN HIDDEN: /api/lms/products does not return the
   * Charge rows today, so this is empty in practice and the screen says in words
   * that fees are itemised on the agreement. It is typed here because a quote
   * that omits a KSh 850 registration fee is the exact "cheap until you apply"
   * pricing this product exists to stop being — the moment the endpoint returns
   * them, the comparison picks them up with no screen change.
   */
  charges?: { name: string; amount: number; when: ChargeWhen }[];
}

export type ChargeWhen = "before-disbursement" | "on-disbursement" | "on-repayment";

/** How many days a repayment unit is worth. A month is taken as 30 — good
 *  enough to restate a rate, never used to place a date (stepDate does that on
 *  the calendar, exactly as the server does). */
const DAYS: Record<string, number> = { day: 1, week: 7, month: 30, year: 365 };
const unitDays = (u: string) => DAYS[u.toLowerCase().replace(/s$/, "")] ?? 30;

/**
 * The rate for the WHOLE TERM, which is what the arithmetic below wants.
 *
 * /api/lms/products restates a whole-term rate per repayment period so it reads
 * the way a lender quotes it — Micromart's 82.5% over ten weeks comes back as
 * "8.25%/week" — so the display rate has to be multiplied back up. Where the two
 * units differ (a monthly rate on a weekly product) they are converted through
 * days rather than assumed equal: assuming it would understate the cost roughly
 * fourfold, and understating a cost is the one error direction that is never a
 * rounding argument.
 */
export function wholeTermRate(p: Product): number {
  if (p.interestUnit.toLowerCase() === "term") return p.interestRate;
  const perPeriod = p.interestRate * (unitDays(p.repaymentUnit) / unitDays(p.interestUnit));
  return round2(perPeriod * p.repaymentPeriod);
}

/** Advance a date by `count` repayment units. Ported from schedule.ts. */
export function stepDate(from: Date, unit: string, count: number): Date {
  const d = new Date(from);
  const u = unit.toLowerCase();
  if (u.startsWith("month")) d.setMonth(d.getMonth() + count);
  else if (u.startsWith("week")) d.setDate(d.getDate() + 7 * count);
  else d.setDate(d.getDate() + count);
  return d;
}

export interface Quote {
  product: Product;
  principal: number;
  periods: number;
  unit: string;
  method: "flat" | "reducing";
  totalInterest: number;
  totalRepayable: number;
  /** The typical instalment — every row but the last, which carries the
   *  remainder. Shown as "about", because on most terms it is. */
  perPeriod: number;
  /** Charges due before the money moves. Zero until the catalogue supplies them. */
  upfrontCharges: number;
  /** Integer cents, ready for the reshape editor without a second conversion. */
  rows: Row[];
  firstDueDate: string;
  clearDate: string;
  /**
   * Settling early only costs less on a reducing-balance loan. Under flat the
   * interest was fixed the day the loan was written, and saying otherwise sells
   * a discount that does not exist.
   */
  earlySettlementApplies: boolean;
}

/**
 * Price a product at an amount.
 *
 * `from` is the notional borrow date. It defaults to today, which makes the
 * dates on a comparison screen indicative in the same way the money is — the
 * real first due date is set when the loan is booked.
 */
export function quote(product: Product, principal: number, from: Date = new Date()): Quote {
  const rate = wholeTermRate(product);
  const count = Math.max(1, product.repaymentPeriod);
  const unit = product.repaymentUnit;

  const amounts: number[] = [];
  let totalInterest: number;

  if (product.interestMethod === "reducing") {
    // Straight-line principal, interest on the balance still outstanding — the
    // shape the server builds, remainder absorbed by the final row.
    const periodicRate = rate / 100 / count;
    const perPrincipal = round2(principal / count);
    let outstanding = principal;
    let principalPlaced = 0;
    let interestAcc = 0;
    for (let i = 1; i <= count; i++) {
      const principalDue = i === count ? round2(principal - principalPlaced) : perPrincipal;
      const interestDue = round2(outstanding * periodicRate);
      amounts.push(round2(principalDue + interestDue));
      principalPlaced = round2(principalPlaced + principalDue);
      interestAcc = round2(interestAcc + interestDue);
      outstanding = round2(outstanding - principalDue);
    }
    totalInterest = interestAcc;
  } else {
    totalInterest = round2(principal * (rate / 100));
    const total = round2(principal + totalInterest);
    const per = round2(total / count);
    let placed = 0;
    for (let i = 1; i <= count; i++) {
      const amountDue = i === count ? round2(total - placed) : per;
      amounts.push(amountDue);
      placed = round2(placed + amountDue);
    }
  }

  const rows: Row[] = amounts.map((amountDue, i) => ({
    seq: i + 1,
    dueDate: stepDate(from, unit, i + 1).toISOString(),
    cents: toCents(amountDue),
  }));

  const upfrontCharges = (product.charges ?? [])
    .filter((c) => c.when !== "on-repayment")
    .reduce((n, c) => n + c.amount, 0);

  return {
    product,
    principal,
    periods: count,
    unit,
    method: product.interestMethod,
    totalInterest,
    totalRepayable: round2(principal + totalInterest),
    perPeriod: amounts[0],
    upfrontCharges,
    rows,
    firstDueDate: rows[0].dueDate,
    clearDate: rows[rows.length - 1].dueDate,
    earlySettlementApplies: product.interestMethod === "reducing",
  };
}

/**
 * What the customer may actually ask this product for, given their limit.
 *
 * Returns null when the product cannot serve them at all — a minimum above the
 * limit is a real answer and the screen SAYS it, rather than silently dropping
 * the product from the list. A shelf that quietly hides what you do not qualify
 * for is how a customer ends up believing they were never offered anything.
 */
export function affordableRange(p: Product, limit: number): { min: number; max: number } | null {
  const max = Math.min(p.maxPrincipal, limit);
  if (max < p.minPrincipal) return null;
  return { min: p.minPrincipal, max };
}
