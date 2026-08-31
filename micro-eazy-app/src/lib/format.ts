// ─────────────────────────────────────────────────────────────────────────────
// MONEY AND DATES, ONCE.
//
// Every screen in this app prints shillings and prints a due date, and until now
// each one carried its own two-line helper. Three copies is a coincidence; nine
// is a bug waiting for the day one of them rounds differently from the others
// and a customer sees KSh 2,600 on Home and KSh 2,599.50 on the agreement.
//
// ── WHY TWO MONEY FORMATTERS AND NOT ONE ────────────────────────────────────
// Cents are shown where a cent is REAL and hidden where it is noise, and which
// is which is a judgement about the screen rather than about the number:
//
//   money()   whole shillings. Balances, limits, tiles, anything glanced.
//             "KSh 45,000" — nobody reads ".00" and it steals width on a 360px
//             screen from the digits that matter.
//   exact()   two decimals. The agreement, the schedule editor, anything that
//             must RECONCILE against the lender's own figure. Ten instalments
//             of 912.50 rounded to 913 sum to 9,130 against a total of 9,125,
//             and the customer who adds them up is right and we look wrong.
//
// The rule: if the number is going to be checked, it is exact().
// ─────────────────────────────────────────────────────────────────────────────

const KE = "en-KE";

/** Whole shillings. For anything glanced rather than reconciled. */
export const money = (kes: number) => `KSh ${Math.round(kes).toLocaleString(KE)}`;

/** Two decimals. For anything the customer might add up. */
export const exact = (kes: number) =>
  `KSh ${kes.toLocaleString(KE, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** The same pair, from integer cents — the schedule editor's native unit. */
export const moneyCents = (cents: number) => money(cents / 100);
export const exactCents = (cents: number) => exact(cents / 100);

/** Signed, for a limit that moved. The sign is the whole message, so it is never
 *  dropped and never inferred from a colour — colour is not available to every
 *  reader, and "+KSh 5,000" is legible to all of them. */
export const signedMoney = (kes: number) => `${kes >= 0 ? "+" : "−"}${money(Math.abs(kes))}`;

const asDate = (d: string | Date) => (d instanceof Date ? d : new Date(d));

/** "Fri 5 Sep" — a due date on a row, where the year is obvious from context. */
export const shortDate = (d: string | Date) =>
  asDate(d).toLocaleDateString(KE, { weekday: "short", day: "numeric", month: "short" });

/** "5 Sep 2026" — a date on its own, where the year is not obvious. */
export const dateWithYear = (d: string | Date) =>
  asDate(d).toLocaleDateString(KE, { day: "numeric", month: "short", year: "numeric" });

/** "5 September 2026" — the agreement. A legal document does not abbreviate. */
export const longDate = (d: string | Date) =>
  asDate(d).toLocaleDateString(KE, { day: "numeric", month: "long", year: "numeric" });

/** "2 days ago" / "in 3 days". Relative time is right for a thing that HAPPENED
 *  and wrong for a thing that is DUE — a customer needs the actual date of a
 *  debit, so the callers that print due dates use shortDate and not this. */
export function sinceNow(d: string | Date): string {
  const days = Math.round((Date.now() - asDate(d).getTime()) / 86_400_000);
  if (days === 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 30) return `${days} days ago`;
  const months = Math.round(days / 30);
  if (months < 12) return `${months} month${months === 1 ? "" : "s"} ago`;
  const years = Math.round(months / 12);
  return `${years} year${years === 1 ? "" : "s"} ago`;
}

/** "week" → "weekly" · "month" → "monthly". The unit is stored as ServiceSuite
 *  stores it (prefix-matched, singular), and every screen needs the adverb. */
export function everyUnit(unit: string): string {
  const u = unit.toLowerCase();
  if (u.startsWith("week")) return "weekly";
  if (u.startsWith("month")) return "monthly";
  if (u.startsWith("day")) return "daily";
  return `every ${unit}`;
}

/** "10 weeks" — pluralised against a count. */
export function periodCount(n: number, unit: string): string {
  const u = unit.toLowerCase().replace(/s$/, "");
  return `${n} ${u}${n === 1 ? "" : "s"}`;
}
