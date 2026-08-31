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
//   startRatiba()    NOT idempotent. Two standing orders is two debits a month.
//   verifyOtp()      NOT idempotent — a code is consumed on use.
//   everything else  reads, or writes the server already deduplicates.
// ─────────────────────────────────────────────────────────────────────────────
import { apiFetch } from "../net/transport";

/** Which lender's book this app is standing in. One build, many lenders. */
export const LENDER_SLUG = import.meta.env.VITE_LENDER_SLUG ?? "micromart";

// ── Session ──────────────────────────────────────────────────────────────────

export interface Session {
  success: boolean;
  verified: boolean;
  phone?: string;
  name?: string | null;
}

export const getSession = () => apiFetch<Session>("/api/portal/session", {}, { auth: false });

export const signOut = () => apiFetch<{ success: boolean }>("/api/portal/session", { method: "DELETE" }, { auth: true, idempotent: true });

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

// ── The loan ─────────────────────────────────────────────────────────────────

export interface Installment {
  index: number;
  dueDate: string;
  principal: number;
  interest: number;
  /** What the customer actually pays that period — the field they can reshape. */
  amount: number;
  paid?: number;
  status?: "DUE" | "PAID" | "PART" | "LATE";
}

export interface MyLoan {
  success: boolean;
  loan?: {
    id: string;
    reference: string;
    product: string;
    principal: number;
    outstanding: number;
    nextDueDate: string | null;
    nextDueAmount: number | null;
    daysPastDue: number;
    schedule: Installment[];
  } | null;
  limit?: number;
  available?: number;
}

export const myLoan = (nationalId: string) =>
  apiFetch<MyLoan>(
    "/api/portal/my-loan",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId }) },
    { auth: true, idempotent: true },
  );

export const getOffer = (offerId: string) =>
  apiFetch<unknown>(`/api/portal/offer/${encodeURIComponent(offerId)}`, {}, { auth: true });

export const acceptOffer = (offerId: string, schedule?: Installment[]) =>
  apiFetch<{ success: boolean; message?: string }>(
    `/api/portal/offer/${encodeURIComponent(offerId)}`,
    { method: "POST", body: JSON.stringify({ action: "accept", schedule }) },
    // Accepting twice is the same acceptance — the server settles on offer id,
    // so a retry after a dropped response is safe and is what the customer
    // expects when they press the button again.
    { auth: true, idempotent: true },
  );

// ── Money out ────────────────────────────────────────────────────────────────

/**
 * NOT IDEMPOTENT, DELIBERATELY. This raises an STK push against the customer's
 * registered phone. A transport-level retry after a timeout would prompt them
 * twice for the same debt, and the second prompt is indistinguishable from a
 * scam to the person holding the handset.
 */
export const pay = (nationalId: string, amount?: number) =>
  apiFetch<{ success: boolean; message?: string }>(
    "/api/portal/pay",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId, amount }) },
    { auth: true },
  );

// ── Ratiba (M-PESA standing order) ───────────────────────────────────────────

export type RatibaAction = "create" | "cancel" | "status";

export const ratiba = (nationalId: string, action: RatibaAction, standingOrderId?: string) =>
  apiFetch<{ success: boolean; standingOrder?: unknown; message?: string }>(
    "/api/portal/standing-order",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId, action, standingOrderId }) },
    // Reading status repeats safely. Creating one does not — two standing orders
    // is two debits every month, and the customer finds out on payday.
    { auth: true, idempotent: action === "status" },
  );

// ── Understanding yourself ───────────────────────────────────────────────────

export const whyThisDecision = (nationalId: string) =>
  apiFetch<unknown>(
    "/api/portal/decision",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId }) },
    { auth: true, idempotent: true },
  );

export const ladder = (nationalId: string) =>
  apiFetch<unknown>(
    "/api/portal/ladder",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId }) },
    { auth: true, idempotent: true },
  );

/** What the wider credit system can see — the Interchange view, consent-gated. */
export const exposure = (nationalId: string) =>
  apiFetch<unknown>(
    "/api/portal/exposure",
    { method: "POST", body: JSON.stringify({ lenderSlug: LENDER_SLUG, nationalId }) },
    { auth: true, idempotent: true },
  );

export const consents = () => apiFetch<unknown>("/api/portal/consent", {}, { auth: true, idempotent: true });
