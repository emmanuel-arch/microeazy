// ─────────────────────────────────────────────────────────────────────────────
// RESHAPING A SCHEDULE — the customer's half of the arithmetic.
//
// ── WHAT THIS FILE DELIBERATELY DOES NOT DO ─────────────────────────────────
// It does not compute interest, and it never will. That lives in exactly one
// place — connected-suite/src/lib/lending/schedule.ts — because the offer a
// borrower signs and the loan that gets booked have to be the same numbers, and
// the only way to guarantee that is for both to come from one function. A second
// implementation in the client would drift, and the day it drifted the customer
// would sign one figure and owe another.
//
// So the app RECEIVES a schedule and only ever moves money BETWEEN its rows.
// The total is an input here, not a result. That is why this file is forty lines
// of addition and no finance.
//
// ── WHY CENTS ───────────────────────────────────────────────────────────────
// Ten installments of 912.50 is the real Micro Eazy shape, and in floating point
// ten of them do not sum to 9125 — they sum to 9124.999999999998. A validator
// comparing that to the target with === refuses a schedule the customer got
// exactly right, and a validator using an epsilon lets through a schedule that
// is genuinely a cent short. Everything here is integer cents; the boundary
// converts once, at the edges.
// ─────────────────────────────────────────────────────────────────────────────

export interface Row {
  seq: number;
  /** ISO date. Presentation formats it; nothing here reads it. */
  dueDate: string;
  /** Integer CENTS. Never a float, never a display string. */
  cents: number;
  /** True once money has actually been taken for this period — it is history,
   *  and history is not reshapeable. */
  locked?: boolean;
}

export const toCents = (kes: number) => Math.round(kes * 100);
export const toKes = (cents: number) => cents / 100;

export const sum = (rows: Row[]) => rows.reduce((n, r) => n + r.cents, 0);

/** What is still to be placed. Positive means under-allocated. */
export const remaining = (rows: Row[], targetCents: number) => targetCents - sum(rows);

export const isBalanced = (rows: Row[], targetCents: number) => remaining(rows, targetCents) === 0;

/** Rows the customer is allowed to move money into or out of. */
export const editable = (rows: Row[]) => rows.filter((r) => !r.locked);

/**
 * Set one row, clamped so a single edit can never make the rest impossible:
 * no negative installment, and nothing larger than the whole outstanding total
 * minus what is already locked away in settled periods.
 */
export function setRow(rows: Row[], seq: number, cents: number, targetCents: number): Row[] {
  const lockedTotal = rows.filter((r) => r.locked).reduce((n, r) => n + r.cents, 0);
  const ceiling = Math.max(targetCents - lockedTotal, 0);
  const next = Math.min(Math.max(Math.round(cents), 0), ceiling);
  return rows.map((r) => (r.seq === seq && !r.locked ? { ...r, cents: next } : r));
}

export type Preset = "even" | "front" | "back";

/**
 * Three shapes people actually ask for, and the reason each exists:
 *
 *   even   the default — equal instalments.
 *   front  pay more early. Cheaper in interest on a reducing product and the
 *          right shape for somebody with money now and uncertainty later.
 *   back   pay less early. The shape a trader with stock to sell needs, and the
 *          one most apps refuse to offer, which is why they get defaults they
 *          were never going to meet.
 *
 * Every preset lands on the target EXACTLY: the remainder from integer division
 * is pushed into the last open row rather than spread as fractions of a cent.
 */
export function applyPreset(rows: Row[], targetCents: number, preset: Preset): Row[] {
  const open = editable(rows);
  if (open.length === 0) return rows;

  const lockedTotal = rows.filter((r) => r.locked).reduce((n, r) => n + r.cents, 0);
  const pot = Math.max(targetCents - lockedTotal, 0);
  const n = open.length;

  // Weights, then normalise. Front-loading is a descending ramp, back-loading
  // the same ramp reversed — deliberately gentle (2:1 across the term rather
  // than 5:1), because a customer who cannot meet the first instalment has been
  // given a worse schedule by a feature meant to help them.
  const weights = open.map((_, i) => {
    if (preset === "even") return 1;
    const t = n === 1 ? 0 : i / (n - 1);
    return preset === "front" ? 2 - t : 1 + t;
  });
  const wTotal = weights.reduce((a, b) => a + b, 0);

  let placed = 0;
  const share = new Map<number, number>();
  open.forEach((r, i) => {
    const c = i === n - 1 ? pot - placed : Math.round((pot * weights[i]) / wTotal);
    placed += c;
    share.set(r.seq, Math.max(c, 0));
  });

  return rows.map((r) => (r.locked ? r : { ...r, cents: share.get(r.seq) ?? r.cents }));
}

/**
 * Absorb whatever is left over into the last open row. This is the "fix it for
 * me" button, and it is also what the server does with rounding remainder in
 * buildSchedule — same convention, so a customer who presses it lands on a
 * schedule the server would have produced anyway.
 */
export function balance(rows: Row[], targetCents: number): Row[] {
  const left = remaining(rows, targetCents);
  if (left === 0) return rows;
  const open = editable(rows);
  if (open.length === 0) return rows;
  const last = open[open.length - 1];
  return setRow(rows, last.seq, last.cents + left, targetCents);
}

/** Zero a row and push what it held onto the next open one, so "skip this week"
 *  is one tap and does not silently leave the schedule short. */
export function skip(rows: Row[], seq: number, targetCents: number): Row[] {
  const i = rows.findIndex((r) => r.seq === seq);
  if (i < 0 || rows[i].locked) return rows;
  const moving = rows[i].cents;
  const nextOpen = rows.slice(i + 1).find((r) => !r.locked);
  const cleared = setRow(rows, seq, 0, targetCents);
  if (!nextOpen) return balance(cleared, targetCents);
  return setRow(cleared, nextOpen.seq, nextOpen.cents + moving, targetCents);
}
