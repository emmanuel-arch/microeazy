// ─────────────────────────────────────────────────────────────────────────────
// SHAPE YOUR OWN REPAYMENTS.
//
// A lender decides the total. A customer knows their week. Almost every lending
// product in this market conflates those two and hands over a schedule of equal
// instalments on fixed dates, and then treats the resulting misses as a credit
// problem. Very often they are a TIMING problem: a trader whose stock turns on
// the 20th cannot pay on the 5th, and never could.
//
// So the total is fixed and untouchable — it is the lender's number and this
// screen cannot change it by a cent — while the SHAPE is the customer's. Ten of
// 912.50, or 2,000 then four of 1,000, or nothing this week and more next. Same
// money, same clear date, a schedule they can actually meet.
//
// ── WHAT MAKES IT SAFE TO OFFER ─────────────────────────────────────────────
// One invariant, enforced in one place: the rows must sum to the total EXACTLY,
// in integer cents (see lib/schedule/reshape.ts for why floats cannot be used
// here). The button is inert until they do, and it says why rather than leaving
// somebody prodding a dead control.
//
// The client is not trusted with this. Risk sees the reshaped schedule and can
// return it to the default, and the server re-derives the totals on accept —
// this screen is a proposal, not a decision. That is exactly what lets us give
// the customer real freedom: nothing here can create a schedule the lender has
// not agreed to. LoanAgreement is where that distinction is made visible, and
// it says so on the page when the two differ.
//
// ── WHERE THE ROWS COME FROM ────────────────────────────────────────────────
// The product step hands over a Quote, and its rows arrive here already in
// integer cents summing exactly to the total — lib/quote.ts uses the server's
// own rounding and remainder convention, so a schedule that balances here is
// one the server would have produced. Opened without a quote (support jumping
// straight to ?step=schedule) it falls back to the live Micro Eazy shape, so
// the screen is never a blank workspace.
// ─────────────────────────────────────────────────────────────────────────────
import { useMemo, useState } from "react";
import { ArrowRight, RotateCcw, SkipForward, Wand2, Info } from "lucide-react";
import { LiquidButton } from "../../components/ui/LiquidButton";
import { exact, money, periodCount, shortDate } from "../../lib/format";
import type { Quote } from "../../lib/quote";
import {
  applyPreset, balance, isBalanced, remaining, setRow, skip, sum, toCents,
  type Preset, type Row,
} from "../../lib/schedule/reshape";

/** The shape the ServiceSuite preview produces for a 5,000 Micro Eazy loan:
 *  10 weekly instalments of 912.50, total 9,125. Used only when this screen is
 *  opened without a quote in hand. */
const DEMO = { principal: 5_000, interest: 4_125, unit: "week", periods: 10 };
const DEMO_TOTAL_CENTS = toCents(DEMO.principal + DEMO.interest);
const DEMO_START = new Date("2026-09-06T00:00:00");
const DEMO_ROWS: Row[] = Array.from({ length: DEMO.periods }, (_, i) => {
  const d = new Date(DEMO_START);
  d.setDate(d.getDate() + i * 7);
  return { seq: i + 1, dueDate: d.toISOString(), cents: DEMO_TOTAL_CENTS / DEMO.periods };
});

const PRESETS: { id: Preset; label: string; note: string }[] = [
  { id: "even", label: "Even", note: "The same every time" },
  { id: "front", label: "More now", note: "Heavier early, lighter later" },
  { id: "back", label: "More later", note: "Lighter early, heavier later" },
];

/** "week" → "Weeks". The unit is the product's, so a monthly loan does not talk
 *  about weeks — the kind of mismatch that makes a customer distrust the maths
 *  in front of them even when it is right. */
const plural = (unit: string) => {
  const u = unit.toLowerCase().replace(/s$/, "");
  return `${u.charAt(0).toUpperCase()}${u.slice(1)}s`;
};

export default function ScheduleEditor({
  /** What the product step priced. Absent when this screen is opened directly. */
  quote,
  onDone,
}: {
  quote?: Quote | null;
  onDone?: (rows: Row[]) => void;
}) {
  const initial = quote?.rows ?? DEMO_ROWS;
  const totalCents = useMemo(() => sum(initial), [initial]);
  const principal = quote?.principal ?? DEMO.principal;
  const interest = quote?.totalInterest ?? DEMO.interest;
  const unit = quote?.unit ?? DEMO.unit;

  const [rows, setRows] = useState<Row[]>(initial);
  const [preset, setPreset] = useState<Preset | null>("even");

  const left = remaining(rows, totalCents);
  const ok = isBalanced(rows, totalCents);
  const biggest = useMemo(() => Math.max(...rows.map((r) => r.cents), 1), [rows]);

  const edit = (seq: number, kesValue: string) => {
    const n = Number(kesValue.replace(/[^\d.]/g, ""));
    setPreset(null);
    setRows((rs) => setRow(rs, seq, toCents(Number.isFinite(n) ? n : 0), totalCents));
  };

  return (
    <div className="space-y-3 xl:grid xl:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)] xl:items-start xl:gap-4 xl:space-y-0">
      <div className="space-y-3">
        {/* ── The one number that cannot move. ─────────────────────────── */}
        <section className="card p-5">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">Total to repay</p>
              <p className="tnum mt-1 text-[30px] font-bold leading-none tracking-[-0.03em]">
                {money(totalCents / 100)}
              </p>
              <p className="mt-1.5 text-[12px] text-ink-soft">
                {money(principal)} borrowed · {money(interest)} interest
              </p>
            </div>
            <div className="text-right">
              <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">Left to place</p>
              <p
                className="tnum mt-1 text-[22px] font-bold leading-none tracking-[-0.02em]"
                style={{ color: ok ? "var(--green-ink)" : left > 0 ? "var(--ink)" : "#e11d48" }}
              >
                {ok ? "Balanced" : exact(Math.abs(left) / 100)}
              </p>
              {!ok && (
                <p className="mt-1 text-[11px] font-medium" style={{ color: left > 0 ? "var(--ink-faint)" : "#e11d48" }}>
                  {left > 0 ? "still to place" : "over the total"}
                </p>
              )}
            </div>
          </div>

          <div className="mt-4 flex flex-wrap gap-2">
            {PRESETS.map((p) => {
              const on = preset === p.id;
              return (
                <button
                  key={p.id}
                  onClick={() => {
                    setPreset(p.id);
                    setRows((rs) => applyPreset(rs, totalCents, p.id));
                  }}
                  title={p.note}
                  className="rounded-full border px-3.5 py-2 text-[12.5px] font-semibold transition-colors"
                  style={{
                    borderColor: on ? "transparent" : "var(--line-strong)",
                    background: on ? "color-mix(in oklab, var(--lime) 26%, transparent)" : "transparent",
                    color: on ? "var(--green-ink)" : "var(--ink-soft)",
                  }}
                >
                  {p.label}
                </button>
              );
            })}
            {!ok && (
              <button
                onClick={() => setRows((rs) => balance(rs, totalCents))}
                className="flex items-center gap-1.5 rounded-full border px-3.5 py-2 text-[12.5px] font-semibold"
                style={{ borderColor: "var(--line-strong)", color: "var(--ink)" }}
              >
                <Wand2 className="h-3.5 w-3.5" strokeWidth={2.2} /> Balance it for me
              </button>
            )}
            <button
              onClick={() => {
                setPreset("even");
                setRows(initial);
              }}
              className="flex items-center gap-1.5 rounded-full px-2.5 py-2 text-[12.5px] font-semibold text-ink-faint"
            >
              <RotateCcw className="h-3.5 w-3.5" strokeWidth={2.2} /> Reset
            </button>
          </div>
        </section>

        {/* ── The rows. ────────────────────────────────────────────────── */}
        <section className="card overflow-hidden">
          <ul>
            {rows.map((r) => (
              <li
                key={r.seq}
                className="flex items-center gap-3 border-b px-4 py-3 last:border-b-0"
                style={{ borderColor: "var(--line)" }}
              >
                <span
                  className="tnum grid h-8 w-8 shrink-0 place-items-center rounded-lg text-[12px] font-bold"
                  style={{ background: "var(--surface-sunk)", color: "var(--ink-faint)" }}
                >
                  {r.seq}
                </span>

                <span className="min-w-0 flex-1">
                  <span className="block text-[13px] font-medium leading-tight">{shortDate(r.dueDate)}</span>
                  {/* The bar is the whole reason this reads as SHAPING rather
                      than as filling in ten boxes: you can see the plan. */}
                  <span
                    className="mt-1.5 block h-1.5 overflow-hidden rounded-full"
                    style={{ background: "var(--surface-sunk)" }}
                  >
                    <span
                      className="block h-full rounded-full transition-[width] duration-300"
                      style={{
                        width: `${(r.cents / biggest) * 100}%`,
                        background:
                          r.cents === 0 ? "transparent" : "linear-gradient(90deg, var(--green), var(--lime))",
                      }}
                    />
                  </span>
                </span>

                <label className="flex shrink-0 items-center gap-1 rounded-xl border px-2.5"
                  style={{ borderColor: "var(--line-strong)", background: "var(--surface-sunk)" }}>
                  <span className="text-[11px] font-semibold text-ink-faint">KSh</span>
                  <input
                    inputMode="decimal"
                    aria-label={`Amount for instalment ${r.seq}, due ${shortDate(r.dueDate)}`}
                    value={(r.cents / 100).toFixed(2)}
                    onChange={(e) => edit(r.seq, e.target.value)}
                    onFocus={(e) => e.currentTarget.select()}
                    className="tnum w-[5.5rem] bg-transparent py-2.5 text-right text-[14px] font-semibold outline-none"
                  />
                </label>

                <button
                  onClick={() => {
                    setPreset(null);
                    setRows((rs) => skip(rs, r.seq, totalCents));
                  }}
                  disabled={r.cents === 0}
                  title={`Skip this ${unit} — move it to the next one`}
                  aria-label={`Skip instalment ${r.seq}`}
                  className="grid h-9 w-9 shrink-0 place-items-center rounded-lg text-ink-faint transition-colors disabled:opacity-30"
                >
                  <SkipForward className="h-4 w-4" strokeWidth={2.1} />
                </button>
              </li>
            ))}
          </ul>
        </section>
      </div>

      {/* ── What it adds up to. ─────────────────────────────────────────── */}
      <aside className="space-y-3">
        <section className="card p-5">
          <p className="text-[13px] font-semibold">Your plan</p>
          <dl className="mt-3 space-y-2 text-[12.5px]">
            {[
              [plural(unit), String(rows.length)],
              [`${plural(unit)} you pay`, String(rows.filter((r) => r.cents > 0).length)],
              [`Largest ${unit}`, money(Math.max(...rows.map((r) => r.cents)) / 100)],
              [`Smallest ${unit}`, money(Math.min(...rows.map((r) => r.cents)) / 100)],
              ["Clear date", shortDate(rows[rows.length - 1].dueDate)],
            ].map(([k, v]) => (
              <div key={k} className="flex items-baseline justify-between gap-3">
                <dt className="text-ink-faint">{k}</dt>
                <dd className="tnum font-semibold">{v}</dd>
              </div>
            ))}
            <div
              className="flex items-baseline justify-between gap-3 border-t pt-2"
              style={{ borderColor: "var(--line)" }}
            >
              <dt className="font-semibold">Adjusted total</dt>
              <dd className="tnum font-bold" style={{ color: ok ? "var(--green-ink)" : "#e11d48" }}>
                {exact(sum(rows) / 100)}
              </dd>
            </div>
          </dl>

          <p className="mt-3 flex items-start gap-2 rounded-lg p-2.5 text-[11.5px] leading-snug text-ink-soft"
            style={{ background: "var(--surface-sunk)" }}>
            <Info className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
            Changing the shape does not change what you owe or when the loan clears — it is still{" "}
            {periodCount(rows.length, unit)}. Your lender reviews the plan before the money moves.
          </p>
        </section>

        <LiquidButton
          size="lg"
          block
          trailingIcon={ArrowRight}
          disabled={!ok}
          onClick={() => onDone?.(rows)}
        >
          {ok ? "Use this plan" : left > 0 ? `Place ${exact(left / 100)} more` : `Remove ${exact(-left / 100)}`}
        </LiquidButton>
      </aside>
    </div>
  );
}
