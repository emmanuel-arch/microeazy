// ─────────────────────────────────────────────────────────────────────────────
// REPAY — the screen a collections call centre exists to be.
//
// "How much do I owe and how do I pay it" is not a hard question, and in this
// market it is answered by ringing somebody. Putting the answer on the
// customer's own screen removes the call rather than deflecting it, which is a
// different and much better thing than a chatbot.
//
// ── THE ONE RULE THIS SCREEN IS BUILT AROUND ────────────────────────────────
// AN STK PUSH IS NEVER SENT TWICE ON ITS OWN. Pressing "Pay now" raises a PIN
// prompt on a real handset for real money. A timeout is not evidence that
// nothing happened — the request may have been received, processed, and the
// response lost coming back — so this screen never retries, never fails over
// (see lib/api/portal.ts: pay() declares itself non-idempotent), and never
// quietly fires a second push while the customer is looking at the first one.
//
// What it does instead is WAIT VISIBLY and say so. The elapsed counter is not
// decoration: it is the thing that stops somebody pressing the button again
// after four seconds because the screen looked frozen.
//
// ── AND THE FALLBACK NOBODY BUILDS ──────────────────────────────────────────
// Daraja fails. It fails at month end, it fails in the evening, and when it
// does, an app whose only route to payment is an STK push has stranded a
// customer who is TRYING TO GIVE US MONEY. The manual paybill route is
// therefore permanent furniture on this screen rather than an error state — it
// is how people paid before the integration existed and it works when the
// integration does not.
//
// The paybill NUMBER is lender configuration and is deliberately not invented
// here. A wrong paybill on a screen like this sends somebody's rent to a
// stranger, so when it is absent the screen says where to find it rather than
// guessing. The account reference — the part people actually get wrong — is
// known, and is shown large enough to copy.
// ─────────────────────────────────────────────────────────────────────────────
import { useEffect, useState } from "react";
import {
  ArrowRight, Banknote, Check, Clock, Info, Landmark, Radio, ShieldCheck, Smartphone,
} from "lucide-react";
import { Sky } from "../components/shell/Sky";
import { LiquidButton } from "../components/ui/LiquidButton";
import { Artwork } from "../components/media/Artwork";
import type { MyLoanResponse, RatibaPlan } from "../lib/api/portal";
import { SAMPLE_LOAN, SAMPLE_RATIBA_ACTIVE } from "../lib/api/samples";
import { money, shortDate } from "../lib/format";

type Choice = "instalment" | "balance" | "other";
type State = "idle" | "pushing" | "waiting" | "paid";

/** How long we watch for the callback before telling the customer to check
 *  their messages instead. Sixty seconds is roughly Safaricom's own patience
 *  with an unanswered prompt, and a spinner that outlives it is a lie. */
const WATCH_SECONDS = 60;

export default function Repay({
  /** Swap for `await myLoan(nationalId)`. */
  data = SAMPLE_LOAN,
  /** Swap for `await ratibaOffer(nationalId)`. */
  ratiba = SAMPLE_RATIBA_ACTIVE,
  /** Lender configuration. Never guessed — see the header note. */
  payBill = null,
}: {
  data?: MyLoanResponse;
  ratiba?: RatibaPlan;
  payBill?: string | null;
}) {
  const loan = data.activeLoan ?? null;
  const [choice, setChoice] = useState<Choice>("instalment");
  const [other, setOther] = useState("");
  const [state, setState] = useState<State>("idle");
  const [elapsed, setElapsed] = useState(0);

  // The counter that keeps somebody from pressing the button a second time.
  // It also gives the wiring its shape: each tick is where myLoan() is
  // re-read to see whether the balance has actually moved.
  useEffect(() => {
    if (state !== "waiting") return;
    const id = setInterval(() => setElapsed((n) => n + 1), 1_000);
    return () => clearInterval(id);
  }, [state]);

  if (!loan) return <NothingOwed lender={data.lender} />;

  const instalment = loan.nextDue?.amount ?? 0;
  const custom = Math.max(0, Number(other.replace(/[^\d.]/g, "")) || 0);
  const amount = choice === "instalment" ? instalment : choice === "balance" ? loan.balance : custom;
  const ratibaOn = ratiba.existing?.status === "ACTIVE" || ratiba.existing?.status === "PENDING";
  const payable = amount > 0 && amount <= loan.balance;

  if (state === "paid") {
    return (
      <>
        <Sky title="Repay" />
        <div className="relative z-10 -mt-12 px-4">
          <section className="card overflow-hidden">
            <Artwork slot="repay-done" rounded="rounded-none" />
            <div className="px-5 py-6 text-center">
              <p className="text-[15px] font-semibold">{money(amount)} received</p>
              <p className="mx-auto mt-2 max-w-[34ch] text-[12.5px] leading-relaxed text-ink-faint">
                Your balance is now {money(Math.max(loan.balance - amount, 0))}. Safaricom has sent you a confirmation
                message with the reference.
              </p>
              <LiquidButton
                size="lg"
                block
                className="mt-5"
                onClick={() => {
                  setState("idle");
                  setElapsed(0);
                }}
              >
                Done
              </LiquidButton>
            </div>
          </section>
        </div>
      </>
    );
  }

  return (
    <>
      <Sky title="Repay">
        <p className="max-w-[34ch] text-[13px] leading-relaxed text-sky-ink-soft">
          {loan.product} · {loan.ref}
        </p>
      </Sky>

      <div className="relative z-10 -mt-12 px-4 xl:grid xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] xl:items-start xl:gap-4">
        <div className="space-y-3">
          {/* ── What is outstanding. ─────────────────────────────────────── */}
          <section className="card p-5">
            <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">Still to repay</p>
            <p className="tnum mt-1 text-[34px] font-bold leading-none tracking-[-0.03em]">{money(loan.balance)}</p>
            <p className="mt-1.5 text-[12px] text-ink-soft">
              of {money(loan.loanAmount)} borrowed
              {loan.expectedClearDate && <> · clears {shortDate(loan.expectedClearDate)}</>}
            </p>

            <div className="mt-4 h-2 overflow-hidden rounded-full" style={{ background: "var(--surface-sunk)" }}>
              <div
                className="h-full rounded-full transition-[width] duration-700"
                style={{
                  width: `${Math.min(100, ((loan.loanAmount - loan.balance) / Math.max(loan.loanAmount, 1)) * 100)}%`,
                  background: "linear-gradient(90deg, var(--green), var(--lime))",
                }}
              />
            </div>
            <p className="mt-1.5 text-[11.5px] text-ink-faint">
              {money(loan.loanAmount - loan.balance)} paid so far
            </p>
          </section>

          {/* ── How much to pay. ─────────────────────────────────────────── */}
          {state === "idle" ? (
            <section className="card overflow-hidden">
              <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
                <p className="flex-1 text-[13px] font-semibold">How much are you paying?</p>
              </div>

              <div className="p-3">
                {[
                  {
                    id: "instalment" as const,
                    label: loan.nextDue ? `Next instalment — due ${shortDate(loan.nextDue.date)}` : "Next instalment",
                    value: instalment,
                    note: ratibaOn ? "Ratiba will collect this automatically" : "Keeps you exactly on schedule",
                  },
                  {
                    id: "balance" as const,
                    label: "Clear the whole loan",
                    value: loan.balance,
                    note: "Settles it today and closes the schedule",
                  },
                ].map((o) => {
                  const on = choice === o.id;
                  return (
                    <button
                      key={o.id}
                      onClick={() => setChoice(o.id)}
                      className="flex w-full items-center gap-3 rounded-xl p-3 text-left transition-colors"
                      style={{ background: on ? "color-mix(in oklab, var(--lime) 12%, transparent)" : "transparent" }}
                    >
                      <span
                        aria-hidden
                        className="grid h-5 w-5 shrink-0 place-items-center rounded-full border"
                        style={{
                          borderColor: on ? "transparent" : "var(--line-strong)",
                          background: on ? "var(--lime)" : "transparent",
                        }}
                      >
                        {on && <Check className="h-3 w-3" strokeWidth={3} style={{ color: "var(--navy-deep)" }} />}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block text-[13px] font-semibold leading-tight">{o.label}</span>
                        <span className="mt-0.5 block text-[11.5px] leading-snug text-ink-faint">{o.note}</span>
                      </span>
                      <span className="tnum shrink-0 text-[14px] font-bold">{money(o.value)}</span>
                    </button>
                  );
                })}

                <button
                  onClick={() => setChoice("other")}
                  className="flex w-full items-center gap-3 rounded-xl p-3 text-left transition-colors"
                  style={{
                    background: choice === "other" ? "color-mix(in oklab, var(--lime) 12%, transparent)" : "transparent",
                  }}
                >
                  <span
                    aria-hidden
                    className="grid h-5 w-5 shrink-0 place-items-center rounded-full border"
                    style={{
                      borderColor: choice === "other" ? "transparent" : "var(--line-strong)",
                      background: choice === "other" ? "var(--lime)" : "transparent",
                    }}
                  >
                    {choice === "other" && <Check className="h-3 w-3" strokeWidth={3} style={{ color: "var(--navy-deep)" }} />}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[13px] font-semibold leading-tight">Another amount</span>
                    <span className="mt-0.5 block text-[11.5px] leading-snug text-ink-faint">
                      Anything you can manage today counts — part payments are applied straight away.
                    </span>
                  </span>
                </button>

                {choice === "other" && (
                  <label
                    className="mx-3 mt-1 mb-2 flex items-center gap-2 rounded-xl border px-3.5"
                    style={{ borderColor: "var(--line-strong)", background: "var(--surface-sunk)" }}
                  >
                    <span className="text-[12px] font-semibold text-ink-faint">KSh</span>
                    <input
                      inputMode="decimal"
                      autoFocus
                      aria-label="Amount to pay"
                      value={other}
                      onChange={(e) => setOther(e.target.value.replace(/[^\d.]/g, ""))}
                      placeholder="0"
                      className="tnum w-full bg-transparent py-3.5 text-[17px] font-semibold outline-none placeholder:font-normal placeholder:text-ink-faint"
                    />
                  </label>
                )}
              </div>

              <div className="border-t px-4 py-4" style={{ borderColor: "var(--line)" }}>
                <LiquidButton
                  size="lg"
                  block
                  icon={Smartphone}
                  trailingIcon={ArrowRight}
                  disabled={!payable}
                  onClick={() => {
                    setState("pushing");
                    setElapsed(0);
                    // WIRING: pay(nationalId, amount). Non-idempotent by
                    // declaration — one call, one push, no failover, no retry.
                    setTimeout(() => setState("waiting"), 900);
                  }}
                >
                  {payable
                    ? `Pay ${money(amount)} from M-PESA`
                    : custom > loan.balance
                      ? "That is more than you owe"
                      : "Enter an amount"}
                </LiquidButton>
                <p className="mt-2.5 flex items-start gap-2 text-[11px] leading-snug text-ink-faint">
                  <ShieldCheck className="mt-px h-3.5 w-3.5 shrink-0" style={{ color: "var(--green-ink)" }} />
                  The prompt goes to your registered M-PESA number. We cannot send it anywhere else, and we never see
                  your PIN.
                </p>
              </div>
            </section>
          ) : (
            <WaitingForHandset
              amount={amount}
              elapsed={elapsed}
              pushing={state === "pushing"}
              onGiveUp={() => {
                setState("idle");
                setElapsed(0);
              }}
              onConfirmed={() => setState("paid")}
            />
          )}
        </div>

        {/* ── Right: the things that are true whether or not they pay now. */}
        <aside className="mt-3 space-y-3 xl:mt-0">
          <section className="card p-5">
            <div className="flex items-center gap-2.5">
              <span
                className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
                style={{
                  background: ratibaOn
                    ? "color-mix(in oklab, var(--lime) 20%, transparent)"
                    : "var(--surface-sunk)",
                  color: ratibaOn ? "var(--green-ink)" : "var(--ink-faint)",
                }}
              >
                <Radio className="h-[18px] w-[18px]" strokeWidth={2.2} />
              </span>
              <p className="text-[13px] font-semibold">Auto-repay</p>
            </div>

            {ratibaOn ? (
              <>
                <p className="mt-3 text-[12.5px] leading-relaxed text-ink-soft">
                  Safaricom collects{" "}
                  <strong className="tnum font-semibold text-ink">{money(ratiba.existing?.amount ?? 0)}</strong>{" "}
                  {ratiba.frequencyLabel ?? ""} until the loan clears. You do not need to do anything on those days.
                </p>
                <button className="mt-3 text-[12.5px] font-semibold underline text-ink-faint">
                  Stop auto-repay
                </button>
              </>
            ) : (
              <>
                <p className="mt-3 text-[12.5px] leading-relaxed text-ink-soft">
                  Let Safaricom move each instalment on its due date, so a missed payment is never just a forgotten
                  one.
                </p>
                {/* Metal, not lime. Two full-width lime buttons on one screen
                    is two primary actions, and the customer came here to pay —
                    setting up a standing order is the good idea sitting beside
                    the thing they actually opened the app to do. */}
                <LiquidButton variant="metal" size="sm" block className="mt-3">
                  Turn on auto-repay
                </LiquidButton>
              </>
            )}
          </section>

          {/* ── The route that works when the integration does not. ──────── */}
          <section className="card overflow-hidden">
            <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
              <Landmark className="h-[18px] w-[18px] shrink-0 text-ink-faint" strokeWidth={2.1} />
              <p className="flex-1 text-[13px] font-semibold">Pay from M-PESA yourself</p>
            </div>

            <div className="space-y-3 px-5 py-4">
              <p className="text-[12px] leading-relaxed text-ink-soft">
                If the prompt does not arrive, you can pay the same way you would pay anyone else — Lipa na M-PESA,
                Pay Bill. It reaches the same place.
              </p>

              <div className="rounded-xl p-3.5" style={{ background: "var(--surface-sunk)" }}>
                <p className="text-[10.5px] font-semibold uppercase tracking-[0.06em] text-ink-faint">
                  Business number
                </p>
                <p className="tnum mt-0.5 text-[18px] font-bold tracking-[0.04em]">
                  {payBill ?? <span className="text-[13px] font-medium text-ink-faint">See your loan SMS</span>}
                </p>

                <p className="mt-3 text-[10.5px] font-semibold uppercase tracking-[0.06em] text-ink-faint">
                  Account number
                </p>
                <p className="tnum mt-0.5 text-[18px] font-bold tracking-[0.06em]">{loan.ref}</p>
              </div>

              <p className="flex items-start gap-2 text-[11px] leading-snug text-ink-faint">
                <Info className="mt-px h-3.5 w-3.5 shrink-0" />
                The account number is your loan reference. Getting it right is what makes the payment land on your loan
                instead of sitting unallocated.
              </p>
            </div>
          </section>
        </aside>
      </div>
    </>
  );
}

/**
 * The wait.
 *
 * Two states people confuse and this separates: the push is being SENT (ours,
 * fast, a spinner is honest) and the push has ARRIVED and is waiting for a PIN
 * (theirs, slow, and a spinner here just looks broken). The second one gets a
 * counter and an instruction instead.
 */
function WaitingForHandset({
  amount, elapsed, pushing, onGiveUp, onConfirmed,
}: {
  amount: number;
  elapsed: number;
  pushing: boolean;
  onGiveUp: () => void;
  onConfirmed: () => void;
}) {
  const expired = elapsed >= WATCH_SECONDS;

  return (
    <section className="card px-5 py-8 text-center">
      <span
        className="mx-auto grid h-12 w-12 place-items-center rounded-2xl"
        style={{ background: "color-mix(in oklab, #5b8cff 18%, transparent)", color: "#3f6fd8" }}
      >
        {pushing ? (
          <Banknote className="h-5 w-5 animate-pulse" strokeWidth={2.2} />
        ) : (
          <Smartphone className="h-5 w-5" strokeWidth={2.2} />
        )}
      </span>

      <p className="mt-3 text-[15px] font-semibold">
        {pushing ? "Sending the request" : expired ? "Still nothing?" : "Check your phone"}
      </p>

      <p className="mx-auto mt-2 max-w-[36ch] text-[12.5px] leading-relaxed text-ink-faint">
        {pushing ? (
          <>Asking Safaricom to prompt you for {money(amount)}.</>
        ) : expired ? (
          <>
            The prompt may not have arrived. Do not press pay again yet — if it did arrive and you approved it, the
            money is already on its way and a second request would take {money(amount)} twice.
          </>
        ) : (
          <>
            Enter your M-PESA PIN to send {money(amount)}. It can take up to a minute to arrive.
          </>
        )}
      </p>

      {!pushing && !expired && (
        <p className="tnum mt-4 text-[12px] font-semibold text-ink-faint">
          <Clock className="mr-1.5 inline h-3.5 w-3.5 align-[-2px]" />
          waiting · {elapsed}s
        </p>
      )}

      {expired && (
        <div className="mt-5 space-y-2">
          {/* Confirming is a READ, and re-reading the balance is always safe —
              which is why it is the first thing offered and paying again is not. */}
          <LiquidButton size="lg" block onClick={onConfirmed}>
            Check whether it went through
          </LiquidButton>
          <button onClick={onGiveUp} className="w-full py-2 text-[12.5px] font-semibold text-ink-faint underline">
            Pay a different way instead
          </button>
        </div>
      )}
    </section>
  );
}

/** Nothing owed. An empty state that encourages rather than accuses — see the
 *  brief on `empty-no-loans` in lib/media/assets.ts. */
function NothingOwed({ lender }: { lender: string }) {
  return (
    <>
      <Sky title="Repay" />
      <div className="relative z-10 -mt-12 px-4">
        <section className="card overflow-hidden">
          <Artwork slot="empty-no-loans" rounded="rounded-none" />
          <div className="px-5 py-6 text-center">
            <p className="text-[15px] font-semibold">You owe nothing</p>
            <p className="mx-auto mt-2 max-w-[32ch] text-[12.5px] leading-relaxed text-ink-faint">
              There is no running loan with {lender}. When you take one, everything you need to repay it is on this
              screen.
            </p>
          </div>
        </section>
      </div>
    </>
  );
}
