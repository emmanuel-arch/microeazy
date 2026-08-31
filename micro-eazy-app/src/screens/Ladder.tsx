// ─────────────────────────────────────────────────────────────────────────────
// YOUR LIMIT LADDER — how the number got to where it is.
//
// A credit limit that arrives without a history is a number handed down. The
// same limit with the four steps that produced it beside it is something the
// customer EARNED, and the difference between those two readings is most of the
// difference between a lender people tolerate and one they stay with.
//
// ── THE LADDER GOES DOWN AS WELL AS UP, AND THIS SCREEN SHOWS IT ────────────
// The route returns `direction` on every rung precisely because the engine can
// lower a limit. A screen that renders only increases would quietly drop the
// decreases — and the customer whose limit fell would open the one screen built
// to explain limits and find no mention of the only event they came to ask
// about. Worse, they would conclude the fall was hidden from them deliberately,
// which is a fair conclusion from that evidence.
//
// So a decrease renders in full, with the same weight as an increase, in amber
// rather than red. Amber is a warning; red is an accusation. A limit that came
// down after an arrear is a fact about a loan, not a verdict about a person.
//
// ── AND THE CAP IS DISCLOSED ────────────────────────────────────────────────
// `cappedByCeiling` is the difference between "you earned 40%" and "you earned
// 40% but the per-step ceiling paid out less than that". It is the one case
// where the ladder does not do what its own percentage implies, and hiding it
// is what makes the whole mechanism look arbitrary — the single most expensive
// thing that can happen to a screen whose entire job is to look principled.
//
// ── NOTHING HERE PROMISES A RUNG ────────────────────────────────────────────
// The route states the RULE and never a date, because the engine decides on the
// evidence at the time. "Your limit will rise next month" is a cheque this
// screen has no authority to sign, so what it shows instead is the one action
// that is actually in the customer's hands.
// ─────────────────────────────────────────────────────────────────────────────
import { ArrowDownRight, ArrowUpRight, Info, Minus, Target, TrendingUp } from "lucide-react";
import { Sky } from "../components/shell/Sky";
import { Artwork } from "../components/media/Artwork";
import type { LadderResponse, Rung } from "../lib/api/portal";
import { SAMPLE_LADDER } from "../lib/api/samples";
import { dateWithYear, money, signedMoney } from "../lib/format";

const DIRECTION = {
  up: { label: "Limit raised", icon: ArrowUpRight, tint: "var(--green-ink)", wash: "color-mix(in oklab, var(--lime) 22%, transparent)" },
  down: { label: "Limit lowered", icon: ArrowDownRight, tint: "#b45309", wash: "color-mix(in oklab, #f0a92b 20%, transparent)" },
  flat: { label: "Reviewed, unchanged", icon: Minus, tint: "var(--ink-soft)", wash: "var(--surface-sunk)" },
} as const;

export default function Ladder({
  /** Swap for `await ladder(nationalId)`. */
  data = SAMPLE_LADDER,
}: {
  data?: LadderResponse;
}) {
  const current = data.current;
  const rungs = data.rungs ?? [];

  // The tallest rung the bars are drawn against. Taken from the rungs
  // themselves rather than from the current limit, so a ladder that has come
  // DOWN still draws its own high-water mark at full width instead of
  // overflowing the track.
  const ceiling = Math.max(current?.limit ?? 0, ...rungs.map((r) => Math.max(r.newLimit, r.previousLimit)), 1);

  return (
    <>
      <Sky title="Your limit ladder">
        <p className="max-w-[36ch] text-[13px] leading-relaxed text-sky-ink-soft">
          Every step your limit has taken, and what earned it.
        </p>
      </Sky>

      <div className="relative z-10 -mt-12 px-4 xl:grid xl:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)] xl:items-start xl:gap-4">
        <div className="space-y-3">
          {/* ── Where it started, where it is. ──────────────────────────── */}
          <section className="card p-5">
            <div className="flex items-end justify-between gap-4">
              <div>
                <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">Started at</p>
                <p className="tnum mt-1 text-[20px] font-bold leading-none tracking-[-0.02em] text-ink-soft">
                  {data.startedAt != null ? money(data.startedAt) : "—"}
                </p>
              </div>
              <TrendingUp className="mb-1 h-5 w-5 shrink-0 text-ink-faint" strokeWidth={2.2} />
              <div className="text-right">
                <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">Now</p>
                <p className="tnum mt-1 text-[30px] font-bold leading-none tracking-[-0.03em]">
                  {current?.limit != null ? money(current.limit) : "—"}
                </p>
              </div>
            </div>

            {data.totalGained != null && data.totalGained > 0 && (
              <p
                className="mt-4 rounded-lg p-2.5 text-center text-[12.5px] font-semibold"
                style={{ background: "color-mix(in oklab, var(--lime) 16%, transparent)", color: "var(--green-ink)" }}
              >
                {money(data.totalGained)} earned across {rungs.filter((r) => r.direction === "up").length} increases
              </p>
            )}

            {current && (
              <dl className="mt-4 grid grid-cols-3 gap-2 text-center">
                {[
                  ["Loans cleared", String(current.clearedLoans)],
                  ["Reviews passed", String(current.graduationCount)],
                  ["Band", current.riskBand ?? "—"],
                ].map(([k, v]) => (
                  <div key={k} className="rounded-xl py-2.5" style={{ background: "var(--surface-sunk)" }}>
                    <dd className="tnum text-[16px] font-bold leading-none">{v}</dd>
                    <dt className="mt-1 text-[10.5px] leading-snug text-ink-faint">{k}</dt>
                  </div>
                ))}
              </dl>
            )}
          </section>

          {/* ── The rungs. ─────────────────────────────────────────────── */}
          {rungs.length === 0 ? (
            <section className="card px-5 py-10 text-center">
              <p className="text-[15px] font-semibold">Your ladder starts with your first loan</p>
              <p className="mx-auto mt-2 max-w-[34ch] text-[12.5px] leading-relaxed text-ink-faint">
                Limits are reviewed after each loan you clear. Once you have cleared one, every step it takes appears
                here with the reason beside it.
              </p>
            </section>
          ) : (
            <section className="card overflow-hidden">
              <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
                <p className="flex-1 text-[13px] font-semibold">Every step, newest first</p>
                <span className="tnum text-[11.5px] text-ink-faint">{rungs.length} reviews</span>
              </div>
              <ol>
                {rungs.map((r, i) => (
                  <RungRow key={r.id} rung={r} ceiling={ceiling} last={i === rungs.length - 1} />
                ))}
              </ol>
            </section>
          )}
        </div>

        {/* ── Right: what earns the next one. ─────────────────────────── */}
        <aside className="mt-3 space-y-3 xl:mt-0">
          {data.next && (
            <section className="card p-5">
              <div className="flex items-center gap-2.5">
                <span
                  className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
                  style={{ background: "color-mix(in oklab, var(--lime) 20%, transparent)", color: "var(--green-ink)" }}
                >
                  <Target className="h-[18px] w-[18px]" strokeWidth={2.2} />
                </span>
                <p className="text-[13px] font-semibold">Earning the next step</p>
              </div>

              <p className="mt-3 rounded-xl p-3.5 text-[13px] font-semibold leading-snug"
                style={{ background: "var(--surface-sunk)" }}>
                {data.next.action}
              </p>

              <p className="mt-3 text-[12px] leading-relaxed text-ink-soft">{data.next.rule}</p>

              {/* Said plainly, because it is the question underneath the whole
                  screen and leaving it implied is how a customer ends up
                  believing a rise was promised to them. */}
              <p className="mt-3 flex items-start gap-2 text-[11px] leading-snug text-ink-faint">
                <Info className="mt-px h-3.5 w-3.5 shrink-0" />
                We cannot tell you a date or an amount in advance. Each review looks at the evidence as it stands on
                the day, which is also why nobody can talk it upwards.
              </p>
            </section>
          )}

          <section className="card overflow-hidden">
            <Artwork slot="ladder-climb" rounded="rounded-none" />
            <div className="px-5 py-4">
              <p className="text-[13.5px] font-semibold leading-tight">A limit is earned, not granted</p>
              <p className="mt-1.5 text-[11.5px] leading-relaxed text-ink-soft">
                Every rung above was paid for by a loan you cleared. That is the whole mechanism — there is no
                application for a higher limit, and there is nobody to ask.
              </p>
            </div>
          </section>
        </aside>
      </div>
    </>
  );
}

function RungRow({ rung, ceiling, last }: { rung: Rung; ceiling: number; last: boolean }) {
  const d = DIRECTION[rung.direction];
  const Icon = d.icon;

  return (
    <li className="relative flex gap-3 px-5 py-4" style={{ borderBottom: last ? undefined : "1px solid var(--line)" }}>
      {/* The thread down the ladder. Drawn behind the node so the node reads as
          sitting ON the rail rather than beside it. */}
      {!last && (
        <span aria-hidden className="absolute bottom-0 left-[2.34rem] top-12 w-px" style={{ background: "var(--line)" }} />
      )}

      <span
        className="z-10 grid h-9 w-9 shrink-0 place-items-center rounded-xl"
        style={{ background: d.wash, color: d.tint }}
      >
        <Icon className="h-[18px] w-[18px]" strokeWidth={2.4} />
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <p className="text-[13.5px] font-semibold leading-tight">
            {d.label}
            <span className="ml-1.5 font-normal text-ink-faint">{dateWithYear(rung.at)}</span>
          </p>
          <p className="tnum text-[14px] font-bold" style={{ color: d.tint }}>
            {signedMoney(rung.change)}
          </p>
        </div>

        <p className="tnum mt-0.5 text-[12px] text-ink-soft">
          {money(rung.previousLimit)} → <strong className="font-semibold text-ink">{money(rung.newLimit)}</strong>
        </p>

        {/* The climb, glanced. Two bars against one scale say "this step was
            big" faster than the two numbers above them ever will. */}
        <span className="mt-2 block h-1.5 overflow-hidden rounded-full" style={{ background: "var(--surface-sunk)" }}>
          <span
            className="block h-full rounded-full"
            style={{
              width: `${(rung.newLimit / ceiling) * 100}%`,
              background:
                rung.direction === "down"
                  ? "linear-gradient(90deg, #b45309, #f0a92b)"
                  : "linear-gradient(90deg, var(--green), var(--lime))",
            }}
          />
        </span>

        <p className="mt-2 text-[11.5px] leading-snug text-ink-faint">
          {rung.direction === "up" ? (
            <>
              After {rung.clearedLoans} loan{rung.clearedLoans === 1 ? "" : "s"} cleared and{" "}
              {money(rung.provenPrincipal)} repaid in full
              {rung.graduationPercent != null && <> · {rung.graduationPercent}% earned</>}
            </>
          ) : rung.direction === "down" ? (
            <>Reviewed after a repayment fell behind. It climbs again the same way it climbed before.</>
          ) : (
            <>Reviewed with no change to the limit.</>
          )}
        </p>

        {/* The one case where the ladder does not do what its own percentage
            says. Disclosed, because concealing it is what makes the mechanism
            look arbitrary. */}
        {rung.cappedByCeiling && (
          <p
            className="mt-2 flex items-start gap-2 rounded-lg p-2.5 text-[11px] leading-snug"
            style={{ background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
          >
            <Info className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
            <span>
              You earned more than this. A limit may only move so far in one step, so the rest carries into your next
              review rather than being lost.
            </span>
          </p>
        )}
      </div>
    </li>
  );
}
