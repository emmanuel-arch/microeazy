// ─────────────────────────────────────────────────────────────────────────────
// SET UP AUTO-REPAY — M-PESA Ratiba, explained to somebody who has never used it.
//
// Ratiba is a standing order on M-PESA: Safaricom moves the money on the day,
// from the customer's own wallet, on a mandate the customer authorises on their
// handset. That sentence is the whole screen, and almost nobody in this market
// has been given it — the word appears on lenders' screens as a toggle with no
// explanation, and a toggle that takes money out of your phone without saying
// who is doing the taking is a toggle people refuse.
//
// ── THE THREE THINGS THAT DECIDE WHETHER SOMEBODY SAYS YES ──────────────────
//   1. WHO IS DEBITING. Safaricom, on your instruction — not us, reaching in.
//   2. EXACTLY WHAT AND WHEN. The amount, the rhythm, the first date and the
//      LAST date, all four on screen before the button. An open-ended mandate
//      with no end date is the thing people are actually afraid of.
//   3. HOW TO STOP IT. Named before they agree, not buried in a settings screen
//      afterwards. Cancellation is theirs and does not need our permission, so
//      saying so costs us nothing and is the single most persuasive line here.
//
// ── AND THE THING NOBODY IS TOLD ────────────────────────────────────────────
// A standing order against an empty wallet does not overdraw anybody and does
// not fine them — it simply fails. But the INSTALMENT is still late, and the
// late instalment is what reaches the bureau. A customer who believes Ratiba
// guarantees their repayment will not check their balance on the day, and finds
// out a fortnight later that they have an arrear. It is on the screen, in the
// section that would otherwise be pure reassurance, because that is the honest
// place for it.
//
// ── SKIPPING IS A REAL CHOICE ───────────────────────────────────────────────
// The journey marks this step `allowed: ["on", "off"]`. A lender may turn it
// off; a CUSTOMER may decline it. Both are legitimate, and the skip is a plain
// control rather than a grey link, because dark-patterning somebody into a
// direct debit is exactly the behaviour this product exists to replace.
// ─────────────────────────────────────────────────────────────────────────────
import { useState } from "react";
import { AlertTriangle, ArrowRight, Ban, Check, Radio, ShieldCheck, Smartphone } from "lucide-react";
import { LiquidButton } from "../../components/ui/LiquidButton";
import { Artwork } from "../../components/media/Artwork";
import type { RatibaPlan } from "../../lib/api/portal";
import { SAMPLE_LENDER, SAMPLE_RATIBA } from "../../lib/api/samples";
import { everyUnit, longDate, money, shortDate } from "../../lib/format";

type State = "offer" | "sending" | "awaitingHandset" | "active" | "skipped";

export default function Ratiba({
  /** Swap for `await ratibaOffer(nationalId)`. The plan is derived server-side
   *  from the loan and its product — nothing about the money comes from here. */
  plan = SAMPLE_RATIBA,
  /**
   * WHO IS BEING PAID. Not defaulted to "your lender": this is the one screen
   * whose entire job is naming exactly who will be taking money out of somebody's
   * wallet, and a vague answer there is worse than no screen at all. It comes
   * from the session in the wired flow.
   */
  lender = SAMPLE_LENDER,
  onDone,
}: {
  plan?: RatibaPlan;
  lender?: string;
  onDone?: () => void;
}) {
  // An order already authorised for this loan. The route returns it precisely
  // so the UI does not offer to create a second one — two standing orders is
  // two debits a month, and the customer finds that out on payday.
  const live = plan.existing && (plan.existing.status === "ACTIVE" || plan.existing.status === "PENDING")
    ? plan.existing
    : null;
  const [state, setState] = useState<State>(live ? "active" : "offer");

  // Nothing to auto-repay: no active loan, or a lender whose book is not ours.
  // Not an error, and not a screen to dress up — it is simply not this
  // customer's step, and the honest thing is to let them past it.
  if (!plan.available) {
    return (
      <section className="card px-5 py-10 text-center">
        <p className="text-[15px] font-semibold">Auto-repay is not available yet</p>
        <p className="mx-auto mt-2 max-w-[34ch] text-[12.5px] leading-relaxed text-ink-faint">
          It is set up against a running loan. Once yours is disbursed you can turn it on from the Repay screen.
        </p>
        <LiquidButton size="lg" block className="mt-5" trailingIcon={ArrowRight} onClick={() => onDone?.()}>
          Continue
        </LiquidButton>
      </section>
    );
  }

  const amount = plan.amount ?? 0;
  const rhythm = plan.frequencyLabel ?? everyUnit(plan.frequency ?? "month");
  const simulated = plan.mpesaConfigured === false;

  if (state === "skipped") {
    return (
      <section className="card px-5 py-10 text-center">
        <span
          className="mx-auto grid h-12 w-12 place-items-center rounded-2xl"
          style={{ background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
        >
          <Ban className="h-5 w-5" strokeWidth={2.1} />
        </span>
        <p className="mt-3 text-[15px] font-semibold">You will pay each instalment yourself</p>
        <p className="mx-auto mt-2 max-w-[36ch] text-[12.5px] leading-relaxed text-ink-faint">
          We will remind you before each due date. You can switch auto-repay on later from the Repay screen — nothing
          about your loan changes either way.
        </p>
        <LiquidButton size="lg" block className="mt-5" trailingIcon={ArrowRight} onClick={() => onDone?.()}>
          Continue
        </LiquidButton>
      </section>
    );
  }

  if (state === "awaitingHandset" || state === "active") {
    const done = state === "active";
    return (
      <section className="card px-5 py-10 text-center">
        <span
          className="mx-auto grid h-12 w-12 place-items-center rounded-2xl"
          style={{
            background: done
              ? "color-mix(in oklab, var(--lime) 24%, transparent)"
              : "color-mix(in oklab, #5b8cff 18%, transparent)",
            color: done ? "var(--green-ink)" : "#3f6fd8",
          }}
        >
          {done ? <Check className="h-6 w-6" strokeWidth={2.6} /> : <Smartphone className="h-5 w-5" strokeWidth={2.2} />}
        </span>

        <p className="mt-3 text-[15px] font-semibold">
          {done ? (live ? "Auto-repay is already on" : "Auto-repay is on") : "Check your phone"}
        </p>
        <p className="mx-auto mt-2 max-w-[38ch] text-[12.5px] leading-relaxed text-ink-faint">
          {done ? (
            <>
              Safaricom will move {money(live?.amount ?? amount)} {rhythm} until {longDate(plan.endDate!)}, to{" "}
              {lender}. You do not need to do anything on those days.
            </>
          ) : (
            <>
              Safaricom has sent a request to authorise this standing order. Approve it with your M-PESA PIN — it can
              take a minute to arrive.
            </>
          )}
        </p>

        {!done && (
          <p className="mx-auto mt-3 max-w-[36ch] text-[11.5px] leading-snug text-ink-faint">
            Nothing is debited by approving it. The first payment is on {shortDate(plan.startDate!)}.
          </p>
        )}

        <LiquidButton
          size="lg"
          block
          className="mt-5"
          trailingIcon={ArrowRight}
          onClick={() => (done ? onDone?.() : setState("active"))}
        >
          {done ? "Continue" : "I have approved it"}
        </LiquidButton>

        {!done && (
          <button
            onClick={() => setState("offer")}
            className="mt-2 w-full py-2 text-[12px] font-semibold text-ink-faint"
          >
            Nothing arrived — go back
          </button>
        )}
      </section>
    );
  }

  return (
    <div className="space-y-3">
      <section className="card overflow-hidden">
        {/* Rings, assigned rather than hashed: a repeating signal is the right
            read for a standing instruction. The hash landed on the bar
            composition, which is a growth chart — the wrong promise entirely on
            a screen about money leaving your wallet. */}
        <Artwork slot="ratiba-setup" motif={0} rounded="rounded-none" />

        <div className="px-5 pb-4 pt-4">
          <p className="text-[13px] font-semibold">What Ratiba is</p>
          <p className="mt-1.5 text-[12.5px] leading-relaxed text-ink-soft">
            A standing order on M-PESA. <strong className="font-semibold text-ink">Safaricom</strong> moves the money
            from your wallet on the due date, on an instruction you approve on your own handset. We never reach into
            your M-PESA — we could not if we wanted to.
          </p>
        </div>
      </section>

      {/* ── Exactly what you are approving. All four facts, above the button. */}
      <section className="card overflow-hidden">
        <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
          <Radio className="h-[18px] w-[18px] shrink-0" style={{ color: "var(--green-ink)" }} strokeWidth={2.2} />
          <p className="flex-1 text-[13px] font-semibold">What you are approving</p>
        </div>

        <dl className="px-5 py-2 text-[12.5px]">
          {[
            ["Amount", money(amount)],
            ["How often", rhythm.charAt(0).toUpperCase() + rhythm.slice(1)],
            ["First payment", plan.startDate ? shortDate(plan.startDate) : "—"],
            ["Last payment", plan.endDate ? shortDate(plan.endDate) : "—"],
            ["Paid to", lender],
          ].map(([k, v]) => (
            <div
              key={k}
              className="flex items-baseline justify-between gap-3 border-b py-2.5 last:border-b-0"
              style={{ borderColor: "var(--line)" }}
            >
              <dt className="text-ink-faint">{k}</dt>
              <dd className="tnum shrink-0 font-semibold">{v}</dd>
            </div>
          ))}
        </dl>

        <p
          className="flex items-start gap-2 border-t px-5 py-3.5 text-[11.5px] leading-snug"
          style={{ borderColor: "var(--line)", background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
        >
          <ShieldCheck className="mt-px h-3.5 w-3.5 shrink-0" style={{ color: "var(--green-ink)" }} />
          <span>
            It <strong className="font-semibold text-ink">ends on its own</strong> when the loan clears. It cannot be
            used for anything else, and it cannot take more than the amount above.
          </span>
        </p>
      </section>

      {/* ── The part nobody is told. ────────────────────────────────────── */}
      <section className="card p-4">
        <div className="flex items-start gap-3">
          <span
            className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
            style={{ background: "color-mix(in oklab, #f0a92b 18%, transparent)", color: "#b45309" }}
          >
            <AlertTriangle className="h-[18px] w-[18px]" strokeWidth={2.2} />
          </span>
          <div className="min-w-0 space-y-1.5 text-[11.5px] leading-snug text-ink-soft">
            <p className="text-[13px] font-semibold text-ink">If there is no money in your M-PESA that day</p>
            <p>
              The debit simply fails. Safaricom does not overdraw you and there is no charge for the attempt.
            </p>
            <p>
              But <strong className="font-semibold text-ink">the instalment is still late</strong>, and a late
              instalment reaches the credit bureau. Auto-repay saves you from forgetting — it does not save you from an
              empty wallet, so keep an eye on the day.
            </p>
          </div>
        </div>
      </section>

      {/* ── How to stop it. Before they agree, not after. ───────────────── */}
      <section className="card flex items-start gap-3 p-4">
        <span
          className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
          style={{ background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
        >
          <Ban className="h-[18px] w-[18px]" strokeWidth={2.1} />
        </span>
        <span className="min-w-0">
          <span className="block text-[13px] font-semibold leading-tight">You can stop it at any time</span>
          <span className="mt-1 block text-[11.5px] leading-snug text-ink-soft">
            From the Repay screen here, or from Ratiba in your M-PESA app. You do not need our permission and you do
            not have to give a reason — cancelling does not affect the loan itself, only how it is collected.
          </span>
        </span>
      </section>

      {simulated && (
        <p
          className="flex items-start gap-2 rounded-xl border border-dashed p-3 text-[11.5px] leading-snug text-ink-soft"
          style={{ borderColor: "var(--line-strong)" }}
        >
          <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
          {lender} has not connected M-PESA yet, so this order is recorded but no money will move automatically. You
          will be told before that changes.
        </p>
      )}

      <LiquidButton
        size="lg"
        block
        icon={Radio}
        trailingIcon={ArrowRight}
        loading={state === "sending"}
        onClick={() => {
          setState("sending");
          // WIRING: ratibaSetup(nationalId) — never retried. Two standing orders
          // against one loan is two debits a month, and the customer finds out
          // on payday rather than from us.
          setTimeout(() => setState("awaitingHandset"), 800);
        }}
      >
        Turn on auto-repay
      </LiquidButton>

      <button
        onClick={() => setState("skipped")}
        className="w-full rounded-full border py-3 text-[13px] font-semibold text-ink-soft"
        style={{ borderColor: "var(--line-strong)" }}
      >
        No — I will pay each one myself
      </button>
    </div>
  );
}
