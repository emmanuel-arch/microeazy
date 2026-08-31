// ─────────────────────────────────────────────────────────────────────────────
// WHY THIS DECISION — the screen the whole product ethic rests on.
//
// A decline the customer cannot act on is not a decision, it is a door. The
// engine has always recorded WHY (LoanApplication.reasonCodes); what has never
// existed anywhere the customer can see it is the other half — what to actually
// DO about it. Both halves are on this screen, side by side, per reason.
//
// ── FOUR RULES THIS SCREEN KEEPS ────────────────────────────────────────────
//
// 1. AN APPROVAL GETS THE SAME EXPLANATION AS A DECLINE. It is easy to build a
//    considerate decline screen; the harder and far more common case is the
//    customer who GOT the money and still wants to know why the number stopped
//    where it did. If this only appeared on declines it would become a screen
//    people associate with bad news and stop opening.
//
// 2. "NOTHING YOU DO CHANGES THIS" IS SAID OUT LOUD. `howToFix: null` is a real
//    value with a real meaning, and rendering it as a blank space implies the
//    customer simply has not been told the trick yet. Waiting for time to pass
//    is not a failing, and listing it beside actionable advice as though it were
//    another thing they are neglecting is quietly cruel.
//
// 3. THE APPEAL IS A DISCLOSURE, NOT A SUPPORT LINK. Where the route says an
//    appeal is available, it appears as a section with the right stated — the
//    right to a human review and the right to see what the decision was based
//    on — not as "contact us" in the footer.
//
// 4. NO REASON IS INVENTED. Every line comes from the assessment that actually
//    ran. Where we cannot name a factor honestly the library says so, and this
//    screen renders that admission rather than smoothing it over. A
//    confident-sounding wrong explanation is worse than an admitted gap.
// ─────────────────────────────────────────────────────────────────────────────
import { Link } from "react-router-dom";
import {
  ArrowRight, ChevronRight, Gauge, Minus, Scale, ShieldQuestion, TrendingDown, TrendingUp,
} from "lucide-react";
import { Sky } from "../components/shell/Sky";
import { Artwork } from "../components/media/Artwork";
import type { CustomerReason, DecisionResponse, ReasonDirection } from "../lib/api/portal";
import { SAMPLE_DECISION } from "../lib/api/samples";
import { dateWithYear, money } from "../lib/format";

/**
 * Direction is carried by an ICON AND A WORD, never by colour alone.
 *
 * Roughly one man in twelve cannot separate the green from the amber here, and
 * this is a screen about money — "helped" and "held it back" have to survive
 * being read in greyscale, in sunlight, by somebody who is worried.
 */
const DIRECTION: Record<ReasonDirection, { label: string; icon: typeof TrendingUp; tint: string; wash: string }> = {
  up: { label: "Helped", icon: TrendingUp, tint: "var(--green-ink)", wash: "color-mix(in oklab, var(--lime) 20%, transparent)" },
  down: { label: "Held it back", icon: TrendingDown, tint: "#b45309", wash: "color-mix(in oklab, #f0a92b 20%, transparent)" },
  neutral: { label: "Considered", icon: Minus, tint: "var(--ink-soft)", wash: "var(--surface-sunk)" },
};

const TONE: Record<string, { tint: string; wash: string }> = {
  approved: { tint: "var(--green-ink)", wash: "color-mix(in oklab, var(--lime) 18%, transparent)" },
  declined: { tint: "#b91c1c", wash: "color-mix(in oklab, #e11d48 12%, transparent)" },
  review: { tint: "#b45309", wash: "color-mix(in oklab, #f0a92b 18%, transparent)" },
  pending: { tint: "var(--ink-soft)", wash: "var(--surface-sunk)" },
};

export default function WhyThisDecision({
  /** Swap for `await whyThisDecision(nationalId)`. */
  data = SAMPLE_DECISION,
  /** From the ladder or my-loan. Shown as the headline number because it is the
   *  one the customer came to ask about. */
  limit = 45_000,
  score = 712,
}: {
  data?: DecisionResponse;
  limit?: number;
  score?: number;
}) {
  const decision = data.decision ?? null;

  return (
    <>
      <Sky title="Your score">
        <p className="max-w-[36ch] text-[13px] leading-relaxed text-sky-ink-soft">
          Every number here was produced by a process we can show you, line by line.
        </p>
      </Sky>

      <div className="relative z-10 -mt-12 px-4 xl:grid xl:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)] xl:items-start xl:gap-4">
        <div className="space-y-3">
          {/* ── The two numbers. ─────────────────────────────────────────── */}
          <section className="card p-5">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">Your score</p>
                <p className="tnum mt-1 text-[34px] font-bold leading-none tracking-[-0.03em]">
                  {score}
                  <span className="text-[16px] font-semibold text-ink-faint"> / 900</span>
                </p>
              </div>
              <div className="text-right">
                <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">Your limit</p>
                <p className="tnum mt-1 text-[26px] font-bold leading-none tracking-[-0.02em]">{money(limit)}</p>
              </div>
            </div>

            {/* The same information as the number, glanced rather than read.
                The scale starts at 300 because that is where the scorecard
                starts — a bar drawn from zero would make 712 look like a pass
                mark rather than the strong score it is. */}
            <div className="mt-4 h-2 overflow-hidden rounded-full" style={{ background: "var(--surface-sunk)" }}>
              <div
                className="h-full rounded-full transition-[width] duration-700"
                style={{
                  width: `${Math.min(100, Math.max(0, ((score - 300) / 600) * 100))}%`,
                  background: "linear-gradient(90deg, var(--green), var(--lime))",
                }}
              />
            </div>
            <div className="tnum mt-1.5 flex justify-between text-[11px] text-ink-faint">
              <span>300</span>
              <span>900</span>
            </div>
          </section>

          {!decision ? (
            <NoDecisionYet found={data.found} lender={data.lender} />
          ) : (
            <>
              {/* ── The verdict, in the assessment's own words. ─────────── */}
              <section className="card p-5">
                <span
                  className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold"
                  style={{ background: TONE[decision.tone].wash, color: TONE[decision.tone].tint }}
                >
                  <Scale className="h-3.5 w-3.5" strokeWidth={2.4} />
                  {decision.product ?? "Application"} · {decision.ref}
                </span>
                <p className="mt-3 text-[17px] font-bold leading-tight tracking-[-0.02em]">{decision.headline}</p>
                <p className="mt-1.5 text-[12.5px] leading-relaxed text-ink-soft">{decision.body}</p>
                <p className="mt-2.5 text-[11.5px] text-ink-faint">
                  Decided {dateWithYear(decision.decidedAt)} by {data.lender}.
                </p>

                {/* The single most actionable line on a decline, and the route
                    only sets it when the arithmetic actually supports it. */}
                {decision.askingAboveLimit && decision.qualifiedFor != null && (
                  <div
                    className="mt-4 rounded-xl p-3.5"
                    style={{ background: "var(--surface-sunk)" }}
                  >
                    <p className="text-[12.5px] leading-relaxed text-ink-soft">
                      You asked for <strong className="tnum font-semibold text-ink">{money(decision.requested)}</strong>{" "}
                      and qualified for{" "}
                      <strong className="tnum font-semibold text-ink">{money(decision.qualifiedFor)}</strong>. Applying
                      at or below that figure usually goes straight through.
                    </p>
                  </div>
                )}
              </section>

              {/* ── The reasons. ────────────────────────────────────────── */}
              <section className="space-y-3">
                <h2 className="px-1 text-[15px] font-bold tracking-[-0.015em]">What the assessment weighed</h2>
                {decision.reasons.map((r, i) => (
                  <Reason key={r.code ?? i} reason={r} />
                ))}
              </section>

              {/* ── The appeal. A right, stated. ────────────────────────── */}
              {decision.appeal.available && (
                <section className="card p-5">
                  <div className="flex items-start gap-3">
                    <span
                      className="grid h-10 w-10 shrink-0 place-items-center rounded-xl"
                      style={{ background: "color-mix(in oklab, var(--navy) 12%, transparent)", color: "var(--navy-ink)" }}
                    >
                      <ShieldQuestion className="h-[18px] w-[18px]" strokeWidth={2.2} />
                    </span>
                    <div className="min-w-0">
                      <p className="text-[14px] font-semibold leading-tight">You can ask a person to look at this</p>
                      <p className="mt-1.5 text-[12px] leading-relaxed text-ink-soft">{decision.appeal.note}</p>
                    </div>
                  </div>
                  <button
                    className="mt-4 w-full rounded-full border py-3 text-[13px] font-semibold"
                    style={{ borderColor: "var(--line-strong)", color: "var(--ink)" }}
                  >
                    Request a human review
                  </button>
                </section>
              )}
            </>
          )}
        </div>

        {/* ── Right: where the number goes next. ───────────────────────── */}
        <aside className="mt-3 space-y-3 xl:mt-0">
          <Link to="/ladder" className="card flex w-full items-center gap-3 p-4 text-left">
            <span
              className="grid h-10 w-10 shrink-0 place-items-center rounded-xl"
              style={{ background: "color-mix(in oklab, var(--lime) 20%, transparent)", color: "var(--green-ink)" }}
            >
              <TrendingUp className="h-[18px] w-[18px]" strokeWidth={2.2} />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-[14px] font-semibold leading-tight">How your limit got here</span>
              <span className="mt-0.5 block text-[11.5px] leading-snug text-ink-faint">
                Every step it has taken, up and down, and what earned each one.
              </span>
            </span>
            <ChevronRight className="h-4 w-4 shrink-0 text-ink-faint" />
          </Link>

          <Link to="/exposure" className="card flex w-full items-center gap-3 p-4 text-left">
            <span
              className="grid h-10 w-10 shrink-0 place-items-center rounded-xl"
              style={{ background: "color-mix(in oklab, #a78bfa 20%, transparent)", color: "#6d43d8" }}
            >
              <Gauge className="h-[18px] w-[18px]" strokeWidth={2.2} />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-[14px] font-semibold leading-tight">What other lenders can see</span>
              <span className="mt-0.5 block text-[11.5px] leading-snug text-ink-faint">
                Your bureau file, and your position across the network.
              </span>
            </span>
            <ChevronRight className="h-4 w-4 shrink-0 text-ink-faint" />
          </Link>

          <section className="card overflow-hidden">
            <Artwork slot="score-explained" rounded="rounded-none" />
            <div className="px-5 py-4">
              <p className="text-[13.5px] font-semibold leading-tight">A score is a measurement, not a verdict</p>
              <p className="mt-1.5 text-[11.5px] leading-relaxed text-ink-soft">
                It describes what your repayment record and your cashflow have shown so far. It is not a judgement
                about you, and it changes as those change — which is why every reason above comes with what moves it.
              </p>
            </div>
          </section>
        </aside>
      </div>
    </>
  );
}

function Reason({ reason }: { reason: CustomerReason }) {
  const d = DIRECTION[reason.direction];
  const Icon = d.icon;

  return (
    <article className="card overflow-hidden">
      <div className="flex items-start gap-3 p-5 pb-3.5">
        <span
          className="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-xl"
          style={{ background: d.wash, color: d.tint }}
        >
          <Icon className="h-[18px] w-[18px]" strokeWidth={2.3} />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
            <h3 className="text-[14px] font-semibold leading-tight">{reason.title}</h3>
            <span className="text-[11px] font-bold uppercase tracking-[0.06em]" style={{ color: d.tint }}>
              {d.label}
            </span>
          </div>
          <p className="mt-1.5 text-[12.5px] leading-relaxed text-ink-soft">{reason.why}</p>
        </div>
      </div>

      {/* The other half. `howToFix: null` is not a missing string — it is the
          assessment saying nothing the customer does changes this, and it is
          rendered as that sentence rather than as an empty box. */}
      <div
        className="flex items-start gap-2.5 border-t px-5 py-3.5 text-[12px] leading-relaxed"
        style={{ borderColor: "var(--line)", background: "var(--surface-sunk)" }}
      >
        {reason.howToFix ? (
          <>
            <ArrowRight className="mt-0.5 h-3.5 w-3.5 shrink-0" style={{ color: "var(--green-ink)" }} strokeWidth={2.4} />
            <span className="text-ink-soft">
              <strong className="font-semibold text-ink">What moves it: </strong>
              {reason.howToFix}
            </span>
          </>
        ) : (
          <>
            <Minus className="mt-0.5 h-3.5 w-3.5 shrink-0 text-ink-faint" strokeWidth={2.4} />
            <span className="text-ink-faint">
              There is nothing you need to do about this one. It is not something you are getting wrong.
            </span>
          </>
        )}
      </div>
    </article>
  );
}

/**
 * No decision on file. Two different situations behind one screen, and they get
 * different words: an account we cannot match, and an account with nothing
 * assessed yet. Neither is an error and neither should look like one.
 */
function NoDecisionYet({ found, lender }: { found: boolean; lender: string }) {
  return (
    <section className="card px-5 py-10 text-center">
      <p className="text-[15px] font-semibold">
        {found ? "Nothing has been assessed yet" : `No account with ${lender} on this number`}
      </p>
      <p className="mx-auto mt-2 max-w-[36ch] text-[12.5px] leading-relaxed text-ink-faint">
        {found
          ? "Once you apply, this screen shows exactly what the assessment weighed and what would change it."
          : "Check the ID number you signed in with. If it is right, this number has not been registered with them yet."}
      </p>
    </section>
  );
}
