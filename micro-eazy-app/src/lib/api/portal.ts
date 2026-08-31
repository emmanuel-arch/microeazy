// ─────────────────────────────────────────────────────────────────────────────
// THE LENDER, TYPED.
//
// One function per borrower-facing endpoint the Connected Suite already exposes.
// The app calls these; nothing in a screen builds a URL or picks a road.
//
// The endpoints are not new — /api/portal/* has been serving the existing PWA.
// What is new is that every one of them now goes through the dual-road
// transport, and that each declares HERE whether it is safe to send twice.
// That declaration is the whole safety model, so it lives beside the call rather
// than at the call site where it would be forgotten:
//
//   pay()            NOT idempotent. Two of these is two STK pushes to a real
//                    phone for real money. It never fails over.
//   ratibaSetup()    NOT idempotent. Two standing orders is two debits a month.
//   signOffer()      NOT idempotent — a code is consumed on use.
//   sendSigningCode() NOT idempotent — a second SMS invalidates the first, so a
//                    silent retry makes the code the customer is holding wrong.
//   everything else  reads, or writes the server already deduplicates.
//
// ── THE TYPES ARE READ OFF THE ROUTES, NOT GUESSED ──────────────────────────
// Every interface below mirrors the JSON its route actually returns — the files
// are named above each block. That is worth the length: the previous draft of
// this file described /my-loan as { loan, limit, available } and the route has
// always returned { found, activeLoan, clearedLoans }, so every screen written
// against it would have compiled cleanly and rendered nothing. A client type
// that disagrees with its server is worse than no type at all, because it fails
// silently and at runtime.
// ─────────────────────────────────────────────────────────────────────────────
import { apiFetch } from "../net/transport";
import type { Product } from "../quote";

/** Which lender's book this app is standing in. One build, many lenders. */
export const LENDER_SLUG = import.meta.env.VITE_LENDER_SLUG ?? "micromart";

/** Every /api/portal route takes the slug and the ID in the body. */
const who = (nationalId: string) => JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId });

// ── Session ──────────────────────────────────────────────────────────────────

export interface Session {
  success: boolean;
  verified: boolean;
  phone?: string;
  name?: string | null;
}

export const getSession = () => apiFetch<Session>("/api/portal/session", {}, { auth: false });

export const signOut = () =>
  apiFetch<{ success: boolean }>("/api/portal/session", { method: "DELETE" }, { auth: true, idempotent: true });

export const sendOtp = (phone: string) =>
  apiFetch<{ success: boolean; message?: string }>(
    "/api/portal/otp",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, phone }) },
    // Safe to repeat: the server rate-limits, and a customer who did not get the
    // first SMS pressing "resend" is the expected case rather than an error.
    { auth: false, idempotent: true },
  );

export const verifyOtp = (phone: string, code: string) =>
  apiFetch<{ success: boolean; token?: string; message?: string }>(
    "/api/portal/otp/verify",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, phone, code }) },
    { auth: false },
  );

export const signInWithPin = (nationalId: string, pin: string) =>
  apiFetch<{ success: boolean; message?: string }>(
    "/api/portal/pin",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId, pin }) },
    { auth: false },
  );

// ── The shelf ────────────────────────────────────────────────────────────────
// connected-suite/src/app/api/lms/products/route.ts
//
// The one borrower-facing call in this file that needs NO SESSION: a lender's
// product catalogue is public marketing information, and on the white-label
// subdomains the customer has no account yet. That also makes it the only call
// that can fail over freely today — see the note in net/transport.ts.

export interface ProductsResponse {
  success: boolean;
  /** False when a bridged lender's ServiceSuite could not be reached. The
   *  wizard falls back to a manual amount rather than to an error page. */
  connected: boolean;
  lender: string;
  products: Product[];
}

export const listProducts = () =>
  apiFetch<ProductsResponse>(
    "/api/lms/products",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG }) },
    { auth: false, idempotent: true },
  );

// ── The loan ─────────────────────────────────────────────────────────────────
// connected-suite/src/app/api/portal/my-loan/route.ts

export interface ActiveLoan {
  ref: string;
  product: string;
  status: "ACTIVE" | "PENDING_DISBURSEMENT";
  loanAmount: number;
  balance: number;
  /** ISO date, no time. Null on a loan with no clear date set. */
  expectedClearDate: string | null;
  nextDue: { date: string; amount: number } | null;
}

export interface MyLoanResponse {
  success: boolean;
  /** False when the ID did not match an account on this phone. NOT an error —
   *  it is the honest answer to "do you have anything for me". */
  found: boolean;
  /** True for a lender whose book lives in their own ServiceSuite. */
  bridged?: boolean;
  lender: string;
  firstName?: string;
  clearedLoans?: number;
  activeLoan?: ActiveLoan | null;
  message?: string;
}

export const myLoan = (nationalId: string) =>
  apiFetch<MyLoanResponse>(
    "/api/portal/my-loan",
    { method: "POST", body: who(nationalId) },
    { auth: true, idempotent: true },
  );

// ── The agreement ────────────────────────────────────────────────────────────
// connected-suite/src/app/api/portal/offer/[id]/route.ts
//
// SIGNING IS TWO CALLS, NOT ONE, and the shape of that is the legal point:
// possession of the verified phone IS the signature, so a code is sent, and the
// code coming back is what accepts the offer. The code is scoped to THIS offer,
// so one issued to prove identity — or to sign a different offer — will not
// accept this one.

export interface OfferScheduleRow {
  seq: number;
  dueDate: string;
  amountDue: number;
  principalDue: number;
  interestDue: number;
}

export interface Offer {
  id: string;
  status: "OFFERED" | "ACCEPTED" | "DECLINED" | "EXPIRED" | string;
  lender: string;
  productName: string;
  principal: number;
  interestRate: number;
  interestMethod: "flat" | "reducing" | string;
  termCount: number;
  termUnit: string;
  totalInterest: number;
  totalRepayable: number;
  firstDueDate: string;
  expectedClearDate: string;
  expiresAt: string;
  schedule: OfferScheduleRow[];
  acceptedAt: string | null;
  payEarly: { savingKes: number; applies: boolean; note: string };
  /**
   * NOT RETURNED BY THE ROUTE TODAY, and named here because it must be.
   *
   * The Charge catalogue (schema.prisma, model Charge) holds the lender's own
   * fees and the offer does not project them, so an agreement rendered from
   * this response alone quotes interest and is silent on a registration fee the
   * customer will actually be charged. LoanAgreement renders whatever is here
   * and says so in words when it is empty — the fix is on the server, and it is
   * one select away.
   */
  charges?: { name: string; amount: number; when: string }[];
}

export const getOffer = (offerId: string) =>
  apiFetch<{ success: boolean; offer: Offer; message?: string }>(
    `/api/portal/offer/${encodeURIComponent(offerId)}`,
    {},
    { auth: true, idempotent: true },
  );

/**
 * Step one of signing: ask for the code. NOT idempotent, and this is the case
 * where that matters most subtly — a silent retry does not double-charge
 * anybody, it sends a SECOND code and invalidates the first, so the customer
 * carefully types the code they are looking at and is told it is wrong.
 */
export const sendSigningCode = (offerId: string, lang?: "en" | "sw") =>
  apiFetch<{ success: boolean; codeSent?: boolean; delivered?: boolean; devCode?: string; message?: string }>(
    `/api/portal/offer/${encodeURIComponent(offerId)}`,
    { method: "POST", body: JSON.stringify({ action: "sign", ...(lang ? { lang } : {}) }) },
    { auth: true },
  );

/** Step two: the code IS the signature. A code is consumed on use. */
export const signOffer = (offerId: string, code: string) =>
  apiFetch<{ success: boolean; status?: string; acceptedAt?: string; reason?: string; message?: string }>(
    `/api/portal/offer/${encodeURIComponent(offerId)}`,
    { method: "POST", body: JSON.stringify({ action: "sign", code }) },
    { auth: true },
  );

/**
 * Declining is terminal and it is the customer's right, so it is offered with
 * the same weight as signing rather than hidden as a link.
 *
 * Safe to repeat: the server settles on the offer id and answers a second
 * decline with 409 and the status, which is the same outcome by a different
 * route — so a dropped response does not strand somebody on a screen they have
 * already left.
 */
export const declineOffer = (offerId: string) =>
  apiFetch<{ success: boolean; status?: string; message?: string }>(
    `/api/portal/offer/${encodeURIComponent(offerId)}`,
    { method: "POST", body: JSON.stringify({ action: "decline" }) },
    { auth: true, idempotent: true },
  );

// ── Money out ────────────────────────────────────────────────────────────────
// connected-suite/src/app/api/portal/pay/route.ts

/**
 * NOT IDEMPOTENT, DELIBERATELY. This raises an STK push against the customer's
 * registered phone. A transport-level retry after a timeout would prompt them
 * twice for the same debt, and the second prompt is indistinguishable from a
 * scam to the person holding the handset.
 *
 * The response says the push was SENT, never that it was paid — the money is
 * confirmed by Safaricom's callback, so the screen that calls this watches the
 * balance rather than believing the 200.
 */
export const pay = (nationalId: string, amount?: number) =>
  apiFetch<{ success: boolean; message?: string; amount?: number }>(
    "/api/portal/pay",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId, amount }) },
    { auth: true },
  );

// ── Ratiba (M-PESA standing order) ───────────────────────────────────────────
// connected-suite/src/app/api/portal/standing-order/route.ts

export type RatibaFrequency = "ONCE" | "DAILY" | "WEEKLY" | "MONTHLY" | "BIMONTHLY" | "QUARTERLY" | "HALFYEAR" | "YEARLY";

export interface RatibaPlan {
  success: boolean;
  /** False where the lender has no active loan for this customer, or is bridged.
   *  Not an error: there is simply nothing to auto-repay. */
  available: boolean;
  amount?: number;
  frequency?: RatibaFrequency;
  frequencyLabel?: string;
  startDate?: string;
  endDate?: string;
  /** False when the lender has no M-PESA credentials — the order is simulated,
   *  and the screen must say so rather than promise a debit that cannot happen. */
  mpesaConfigured?: boolean;
  existing?: { id: string; status: string; amount: number; frequency: string; simulated: boolean } | null;
}

/** What an auto-repay would look like. A read — safe to repeat. */
export const ratibaOffer = (nationalId: string) =>
  apiFetch<RatibaPlan>(
    "/api/portal/standing-order",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId, action: "offer" }) },
    { auth: true, idempotent: true },
  );

/**
 * Create it. NOT idempotent.
 *
 * The route does guard on an existing PENDING/ACTIVE order and answer
 * `alreadySet`, which makes a retry safe MOST of the time — but the guard reads
 * a row that the first attempt may not have committed yet, and the failure it
 * would miss is two standing orders against one loan. The customer finds that
 * out on payday. A cost that lands on the customer and not on us is exactly the
 * kind we do not gamble with, so this road is never retried.
 */
export const ratibaSetup = (nationalId: string) =>
  apiFetch<{ success: boolean; standingOrderId?: string; status?: string; alreadySet?: boolean; simulated?: boolean; message?: string }>(
    "/api/portal/standing-order",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId, action: "setup" }) },
    { auth: true },
  );

/** Stop it. Repeating a cancellation cancels nothing twice. */
export const ratibaCancel = (nationalId: string, standingOrderId: string) =>
  apiFetch<{ success: boolean; cancelled?: boolean; message?: string }>(
    "/api/portal/standing-order",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId, action: "cancel", standingOrderId }) },
    { auth: true, idempotent: true },
  );

// ── Understanding yourself ───────────────────────────────────────────────────
// connected-suite/src/app/api/portal/decision/route.ts

export type ReasonDirection = "up" | "down" | "neutral";

export interface CustomerReason {
  code: string | null;
  title: string;
  /** What the assessment found — restated, never re-decided. */
  why: string;
  /** What to do about it. NULL MEANS NOTHING THE CUSTOMER DOES CHANGES THIS,
   *  and the screen says that in words rather than rendering a blank. */
  howToFix: string | null;
  direction: ReasonDirection;
}

export interface Decision {
  ref: string;
  verdict: "APPROVE" | "DECLINE" | "REFER" | string | null;
  status: string;
  decidedAt: string;
  product: string | null;
  requested: number;
  /** What they could have had — the most actionable number on a decline. */
  qualifiedFor: number | null;
  askingAboveLimit: boolean;
  tone: "declined" | "review" | "approved" | "pending";
  headline: string;
  body: string;
  reasons: CustomerReason[];
  /** A disclosure, not a support link. It ships with the decline or the decline
   *  is incomplete. */
  appeal: { available: boolean; note: string };
}

export interface DecisionResponse {
  success: boolean;
  found: boolean;
  lender: string;
  firstName?: string;
  /** Null when nothing has been decided yet — a real state, not an error. */
  decision?: Decision | null;
}

export const whyThisDecision = (nationalId: string) =>
  apiFetch<DecisionResponse>(
    "/api/portal/decision",
    { method: "POST", body: who(nationalId) },
    { auth: true, idempotent: true },
  );

// connected-suite/src/app/api/portal/ladder/route.ts

export interface Rung {
  id: string;
  at: string;
  previousLimit: number;
  newLimit: number;
  /** Signed, so the screen never infers direction from the label. */
  change: number;
  direction: "up" | "down" | "flat";
  move: string;
  clearedLoans: number;
  provenPrincipal: number;
  graduationPercent: number | null;
  riskBand: string | null;
  /** True when the percentage earned was more than the per-step ceiling paid
   *  out. Hiding it makes the ladder look arbitrary the one time it does not do
   *  what the percentage implies. */
  cappedByCeiling: boolean;
}

export interface LadderResponse {
  success: boolean;
  found: boolean;
  lender: string;
  firstName?: string;
  current?: {
    limit: number | null;
    graduationCount: number;
    riskBand: string | null;
    clearedLoans: number;
    activeLoans: number;
  };
  startedAt?: number | null;
  totalGained?: number;
  rungs?: Rung[];
  /** The RULE, never a promise or a date. */
  next?: { rule: string; hasActiveLoan: boolean; action: string };
}

export const ladder = (nationalId: string) =>
  apiFetch<LadderResponse>(
    "/api/portal/ladder",
    { method: "POST", body: who(nationalId) },
    { auth: true, idempotent: true },
  );

// connected-suite/src/app/api/portal/exposure/route.ts

/**
 * Five states, five different sentences on the screen — and only ONE of them
 * means "you owe nothing elsewhere". Collapsing any of the others into that
 * would tell a customer their record is clean when it is merely unknown.
 */
export type InterchangeState = "not-configured" | "not-consented" | "refused" | "partial" | "ok";

export interface Interchange {
  connected: boolean;
  state: InterchangeState;
  message?: string | null;
  detail?: string;
  lenders?: number;
  activeLoans?: number;
  /** A band, never an amount. "none" when nothing was found. */
  outstandingBand?: string;
  worstBucket?: string | null;
  /** New credit taken anywhere in the network in the last fortnight. */
  velocity14d?: number;
  asOf?: string;
  queried?: number;
  responded?: number;
}

export interface CrbFile {
  consented: boolean;
  available: boolean;
  checkedAt: string | null;
  report: {
    score?: number;
    grade?: string;
    accounts?: number;
    openAccounts?: number;
    npaAccounts?: number;
    worstArrears?: number;
    /** True past 90 days — shown, but flagged as possibly out of date. */
    stale: boolean;
    [k: string]: unknown;
  } | null;
  message: string | null;
}

export interface ExposureResponse {
  success: boolean;
  crb: CrbFile;
  withThisLender: { lender: string; openLoans: number };
  interchange: Interchange;
}

/** What the wider credit system can see — consent-gated, and never a paid pull. */
export const exposure = (nationalId: string) =>
  apiFetch<ExposureResponse>(
    "/api/portal/exposure",
    { method: "POST", body: who(nationalId) },
    { auth: true, idempotent: true },
  );

// connected-suite/src/app/api/portal/consent/route.ts

export interface ConsentGrant {
  key: string;
  label: string;
  detail: string;
  /** Mandatory grants are not un-togglable — a customer may withdraw anything —
   *  but the UI is told which ones stop a future application, so it can say so
   *  BEFORE the toggle rather than after. */
  mandatory: boolean;
  granted?: boolean;
}

export const consents = () =>
  apiFetch<{ success: boolean; catalogue: ConsentGrant[]; grants: Record<string, boolean>; version?: string }>(
    "/api/portal/consent",
    {},
    { auth: true, idempotent: true },
  );
