// ─────────────────────────────────────────────────────────────────────────────
// THE SAMPLE BOOK — one customer, consistent across every screen.
//
// ── WHY THIS FILE EXISTS AND WHY IT IS NOT "MOCK DATA" ──────────────────────
// Every screen here is authenticated: /decision, /ladder, /exposure and
// /my-loan all want a verified OTP session AND a national ID, and this app has
// no sign-in screen yet. Without something to render, seven finished screens
// would be seven spinners, and a screen nobody can look at is a screen nobody
// reviews.
//
// So each screen renders from here until its call is wired, and the swap is one
// line per screen because every constant below is typed as its route's actual
// RESPONSE — not as a convenient shape. If a field is optional here it is
// optional there; if the route can return `found: false`, the screen already
// handles it. That is the whole discipline: sample data whose type is a lie
// makes wiring a rewrite, and makes the demo a promise the software cannot keep.
//
// ── ONE CUSTOMER, NOT SEVEN ────────────────────────────────────────────────
// Emmanuel Kiptoo, ID 32145678, of Micromart Fintech: limit 45,000, one loan
// running, three cleared, score 712, band Kuza. The same person on Home, on the
// ladder, on the decision and on the credit file — because a demo where the
// limit is 45,000 on one screen and 30,000 on the next is a demo the audience
// stops believing at the second screen, and Morris will notice.
// ─────────────────────────────────────────────────────────────────────────────
import type { Product } from "../quote";
import type {
  DecisionResponse, ExposureResponse, LadderResponse, MyLoanResponse, Offer, RatibaPlan,
} from "./portal";

/** The customer every sample below is about. */
export const SAMPLE_ID = "32145678";
export const SAMPLE_LENDER = "Micromart Fintech";

/**
 * Micromart's shelf.
 *
 * Two products, and the pair is the point: the same money at two rhythms, so
 * the comparison screen has something real to compare. Rates are as
 * /api/lms/products restates them — per repayment period, which is how a lender
 * quotes them and how a customer hears them. Micro Eazy is the live one: 82.5%
 * flat over ten weeks, which the endpoint returns as 8.25%/week.
 */
export const SAMPLE_PRODUCTS: Product[] = [
  {
    id: "micro-eazy",
    name: "Micro Eazy",
    description: "The weekly one. Small amounts, cleared in ten weeks, for stock and short gaps.",
    minPrincipal: 1_000,
    maxPrincipal: 50_000,
    interestRate: 8.25,
    interestUnit: "week",
    interestMethod: "flat",
    repaymentPeriod: 10,
    repaymentUnit: "week",
    minCreditScore: 400,
    charges: [{ name: "Registration fee", amount: 450, when: "before-disbursement" }],
  },
  {
    id: "micro-eazy-monthly",
    name: "Micro Eazy Monthly",
    description: "The monthly one. Larger amounts over four months, on a reducing balance.",
    minPrincipal: 10_000,
    maxPrincipal: 150_000,
    interestRate: 12,
    interestUnit: "month",
    interestMethod: "reducing",
    repaymentPeriod: 4,
    repaymentUnit: "month",
    minCreditScore: 620,
    charges: [{ name: "Registration fee", amount: 850, when: "before-disbursement" }],
  },
];

/** POST /api/portal/my-loan */
export const SAMPLE_LOAN: MyLoanResponse = {
  success: true,
  found: true,
  lender: SAMPLE_LENDER,
  firstName: "Emmanuel",
  clearedLoans: 3,
  activeLoan: {
    ref: "7F3C1A22",
    product: "Micro Eazy",
    status: "ACTIVE",
    loanAmount: 26_000,
    balance: 12_500,
    expectedClearDate: "2026-10-17",
    nextDue: { date: "2026-09-05", amount: 2_600 },
  },
};

/**
 * GET /api/portal/offer/:id
 *
 * An APPROVED offer on the weekly product: 5,000 borrowed, 4,125 interest, ten
 * weeks of 912.50. The same figures scripts/test-quote.mjs checks the client
 * quote against, so a drift between the two shows up as a failing test rather
 * than as a customer signing one number and owing another.
 *
 * `charges` is populated here and is NOT returned by the route today — see the
 * note on Offer in portal.ts. The agreement is rendered with it so the screen
 * can be reviewed complete; the route needs one select to catch up.
 */
export const SAMPLE_OFFER: Offer = {
  id: "8a41f0c2-9e77-4d1b-9d0a-2c3b5e6f7a80",
  status: "OFFERED",
  lender: SAMPLE_LENDER,
  productName: "Micro Eazy",
  principal: 5_000,
  interestRate: 82.5,
  interestMethod: "flat",
  termCount: 10,
  termUnit: "week",
  totalInterest: 4_125,
  totalRepayable: 9_125,
  firstDueDate: "2026-09-06T00:00:00.000Z",
  expectedClearDate: "2026-11-08T00:00:00.000Z",
  expiresAt: "2026-09-03T00:00:00.000Z",
  acceptedAt: null,
  schedule: Array.from({ length: 10 }, (_, i) => ({
    seq: i + 1,
    dueDate: new Date(Date.UTC(2026, 8, 6 + i * 7)).toISOString(),
    amountDue: 912.5,
    principalDue: 500,
    interestDue: 412.5,
  })),
  payEarly: {
    savingKes: 0,
    applies: false,
    note: "This loan charges flat interest, so settling early does not reduce what you owe.",
  },
  charges: [{ name: "Registration fee", amount: 450, when: "before-disbursement" }],
};

/**
 * POST /api/portal/standing-order { action: "offer" }
 *
 * Two of these, because the same endpoint answers two different moments and the
 * screens that read it need opposite states to be worth looking at: the
 * onboarding step is somebody who has NO standing order and is deciding, and
 * Repay is somebody who already has one running. One sample would leave one of
 * those two screens demonstrating the state it is least about.
 *
 * They also have to agree with Home, which shows this customer as having
 * auto-repay on. A demo where Home says Ratiba is collecting and Repay offers
 * to switch it on is a demo the room stops believing at the second screen.
 */
export const SAMPLE_RATIBA: RatibaPlan = {
  success: true,
  available: true,
  amount: 913,
  frequency: "WEEKLY",
  frequencyLabel: "weekly",
  startDate: "2026-09-06T00:00:00.000Z",
  endDate: "2026-11-08T00:00:00.000Z",
  mpesaConfigured: true,
  existing: null,
};

/** The same plan, already authorised on the handset. */
export const SAMPLE_RATIBA_ACTIVE: RatibaPlan = {
  ...SAMPLE_RATIBA,
  amount: 2_600,
  existing: { id: "so_4c81", status: "ACTIVE", amount: 2_600, frequency: "WEEKLY", simulated: false },
};

/**
 * POST /api/portal/decision
 *
 * An APPROVE, not a decline — deliberately. A decline explainer is easy to make
 * look considerate; the harder and more common case is a customer who got the
 * money and still wants to know why the limit stopped where it did, and that is
 * the screen that earns the trust. `howToFix: null` on the last reason is real:
 * some things a customer cannot change, and saying so is the point.
 */
export const SAMPLE_DECISION: DecisionResponse = {
  success: true,
  found: true,
  lender: SAMPLE_LENDER,
  firstName: "Emmanuel",
  decision: {
    ref: "7F3C1A22",
    verdict: "APPROVE",
    status: "DISBURSED",
    decidedAt: "2026-08-14T09:12:00.000Z",
    product: "Micro Eazy",
    requested: 60_000,
    qualifiedFor: 45_000,
    askingAboveLimit: true,
    tone: "approved",
    headline: "This application was approved",
    body: "Here is what the assessment weighed, including what is holding the limit where it is.",
    reasons: [
      {
        code: "RPY",
        title: "Repayment record",
        why: "Three loans cleared, all on or before their due dates. This is the strongest single factor in your favour.",
        howToFix: "Loans cleared on time are the strongest factor. Each one you clear improves this.",
        direction: "up",
      },
      {
        code: "INC",
        title: "Income",
        why: "Six months of M-PESA showed steady inflows averaging KSh 61,400 a month.",
        howToFix: "Assessed from the inflows on your M-PESA statement. A fuller statement reads more of your income.",
        direction: "up",
      },
      {
        code: "EXPOSURE",
        title: "Existing loan load",
        why: "A KSh 12,500 balance is still running here, and the instalments on it are counted against what you could take on next.",
        howToFix:
          "A large share of your income is already going to loan repayments. Clearing one existing loan before applying again lifts this more than any other single action.",
        direction: "down",
      },
      {
        code: "LIM_FIRST_CYCLE",
        title: "Room to grow",
        why: "The ladder caps how far a limit may move in one step, so the full amount your cashflow supports is released over cycles rather than at once.",
        howToFix: null,
        direction: "neutral",
      },
    ],
    appeal: {
      available: false,
      note: "You can ask for this decision to be looked at by a person, and to see the information it was based on.",
    },
  },
};

/**
 * POST /api/portal/ladder
 *
 * Four rungs, and one of them goes DOWN. That is not padding: the route returns
 * decreases and a screen that has only ever been looked at with increases in it
 * is a screen that will be wrong on the day it matters most to somebody.
 */
export const SAMPLE_LADDER: LadderResponse = {
  success: true,
  found: true,
  lender: SAMPLE_LENDER,
  firstName: "Emmanuel",
  current: { limit: 45_000, graduationCount: 3, riskBand: "Kuza", clearedLoans: 3, activeLoans: 1 },
  startedAt: 5_000,
  totalGained: 42_000,
  rungs: [
    {
      id: "r4", at: "2026-08-14T09:12:00.000Z",
      previousLimit: 33_000, newLimit: 45_000, change: 12_000, direction: "up", move: "graduate",
      clearedLoans: 3, provenPrincipal: 26_000, graduationPercent: 40, riskBand: "Kuza", cappedByCeiling: true,
    },
    {
      id: "r3", at: "2026-06-02T11:40:00.000Z",
      previousLimit: 36_000, newLimit: 33_000, change: -3_000, direction: "down", move: "reduce",
      clearedLoans: 2, provenPrincipal: 16_000, graduationPercent: null, riskBand: "Kuza", cappedByCeiling: false,
    },
    {
      id: "r2", at: "2026-04-18T08:05:00.000Z",
      previousLimit: 12_000, newLimit: 36_000, change: 24_000, direction: "up", move: "graduate",
      clearedLoans: 2, provenPrincipal: 16_000, graduationPercent: 200, riskBand: "Kuza", cappedByCeiling: false,
    },
    {
      id: "r1", at: "2026-02-21T14:22:00.000Z",
      previousLimit: 5_000, newLimit: 12_000, change: 7_000, direction: "up", move: "graduate",
      clearedLoans: 1, provenPrincipal: 5_000, graduationPercent: 140, riskBand: "Chipua", cappedByCeiling: false,
    },
  ],
  next: {
    rule: "Limits are reviewed after each loan you clear. Clearing on time is what moves the ladder up; falling into arrears is what moves it down.",
    hasActiveLoan: true,
    action: "Clear the loan you have running now, on or before its due dates.",
  },
};

/**
 * POST /api/portal/exposure
 *
 * `partial` rather than `ok` — on purpose. It is the state that most needs
 * looking at, because it is the one where a careless screen says "nothing found
 * elsewhere" about an answer that is really "we could not ask everybody".
 */
export const SAMPLE_EXPOSURE: ExposureResponse = {
  success: true,
  crb: {
    consented: true,
    available: true,
    checkedAt: "2026-08-14T09:10:00.000Z",
    report: { score: 712, grade: "B", accounts: 6, openAccounts: 2, npaAccounts: 0, worstArrears: 0, stale: false },
    message: null,
  },
  withThisLender: { lender: SAMPLE_LENDER, openLoans: 1 },
  interchange: {
    connected: true,
    state: "partial",
    lenders: 2,
    activeLoans: 2,
    outstandingBand: "KSh 10,000 – 25,000",
    worstBucket: "current",
    velocity14d: 1,
    asOf: "2026-08-31T06:00:00.000Z",
    queried: 5,
    responded: 4,
    message:
      "Some lenders could not be reached, so you may owe more elsewhere than is shown here.",
  },
};
