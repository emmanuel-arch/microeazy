// ─────────────────────────────────────────────────────────────────────────────
// YOUR LOAN AGREEMENT — the step that makes every other step defensible.
//
// A customer who has not seen the charges has not agreed to them. Everything
// before this screen is preparation; this is the moment consent is actually
// given, and it is the document a regulator asks to see when they ask what the
// borrower was shown.
//
// ── WHAT IS ON THE SCREEN, IN THIS ORDER, AND WHY ───────────────────────────
//   1. What you receive and what you hand back. Two numbers, largest type on
//      the page. Everything else is the explanation of the gap between them.
//   2. EVERY charge, itemised, summing to a stated total cost of credit. Not a
//      rate. Not "terms apply". The line items, and their sum.
//   3. Every instalment, with its date. All ten, not the first three and a
//      "see more" — the schedule IS the agreement and hiding two thirds of it
//      behind a tap is how a customer signs a plan they have not read.
//   4. What happens if you are late, before the signature rather than after.
//   5. The signature.
//
// ── THE SIGNATURE IS THE PHONE ──────────────────────────────────────────────
// Possession of the verified handset is what signs this, so the flow is two
// calls: one that sends a code, one that returns it. The code is scoped to THIS
// offer by the server, which means a code issued to prove identity — or to sign
// a different offer — cannot accept this one. That scoping is what makes an SMS
// code a signature rather than a login.
//
// ── WHAT THIS SCREEN WILL NOT DO ────────────────────────────────────────────
// It will not render a Quote. lib/quote.ts prices the shop window and its
// numbers are indicative; the figures below come only from the offer the lender
// drew, because the alternative is a customer signing a client-side estimate.
// The type signature is the enforcement: this component takes an Offer.
//
// It will not pre-tick the confirmation, and it will not let the button work
// until it is ticked. A pre-ticked consent is not consent.
//
// It will not bury Decline. Turning down a loan is a legitimate outcome and a
// screen that offers only one way forward is a screen designed to funnel.
// ─────────────────────────────────────────────────────────────────────────────
import { useMemo, useState } from "react";
import {
  AlertTriangle, ArrowRight, Check, Clock, FileText, Info, MessageSquareText, ShieldCheck, TrendingDown, X,
} from "lucide-react";
import { LiquidButton } from "../../components/ui/LiquidButton";
import type { Offer } from "../../lib/api/portal";
import { SAMPLE_OFFER } from "../../lib/api/samples";
import { exact, longDate, money, periodCount, shortDate } from "../../lib/format";
import { sum, toCents, type Row } from "../../lib/schedule/reshape";

type SignState = "reading" | "sending" | "codeSent" | "signing" | "signed" | "declined";

export default function LoanAgreement({
  /** The lender's own document. Swap for `(await getOffer(id)).offer` once the
   *  application call lands — this constant is the response shape exactly. */
  offer = SAMPLE_OFFER,
  /** What the customer built in the schedule editor, when they reshaped it. */
  proposed,
  onDone,
}: {
  offer?: Offer;
  proposed?: Row[] | null;
  onDone?: (offer: Offer) => void;
}) {
  const [agreed, setAgreed] = useState(false);
  const [state, setState] = useState<SignState>("reading");
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);

  const charges = offer.charges ?? [];
  const upfront = charges.filter((c) => c.when !== "on-repayment").reduce((n, c) => n + c.amount, 0);
  const costOfCredit = offer.totalInterest + charges.reduce((n, c) => n + c.amount, 0);

  /**
   * Did the customer's reshape make it into this document?
   *
   * The schedule editor is a PROPOSAL — risk may return it to the default, and
   * the offer is drawn by the lender either way. So the agreement renders the
   * lender's rows, always, and where the two differ it says so plainly instead
   * of showing the customer their own preferred plan on a page they are about
   * to sign. Being told "your request is still with them" is survivable. Signing
   * a schedule that is not the one being booked is not.
   */
  const reshapeHonoured = useMemo(() => {
    if (!proposed?.length) return null;
    const asOffered: Row[] = offer.schedule.map((r) => ({
      seq: r.seq,
      dueDate: r.dueDate,
      cents: toCents(r.amountDue),
    }));
    if (proposed.length !== asOffered.length) return false;
    return proposed.every((r, i) => r.cents === asOffered[i].cents);
  }, [proposed, offer.schedule]);

  const signable = offer.status === "OFFERED";

  async function requestCode() {
    setError(null);
    setState("sending");
    // WIRING: sendSigningCode(offer.id). Held back with the rest of the
    // authenticated surface until the app has a sign-in screen — the flow, its
    // states and its failure text are all real, and the call is one line.
    await new Promise((r) => setTimeout(r, 700));
    setState("codeSent");
  }

  async function submitCode() {
    setError(null);
    setState("signing");
    // WIRING: signOffer(offer.id, code) — never retried; a code is consumed on use.
    await new Promise((r) => setTimeout(r, 900));
    if (code.trim().length !== 6) {
      setError("That code is not six digits. Check the SMS and try again.");
      setState("codeSent");
      return;
    }
    setState("signed");
    onDone?.(offer);
  }

  if (state === "declined") {
    return (
      <section className="card flex flex-col items-center gap-3 px-5 py-12 text-center">
        <span
          className="grid h-12 w-12 place-items-center rounded-2xl"
          style={{ background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
        >
          <X className="h-5 w-5" strokeWidth={2.2} />
        </span>
        <p className="text-[15px] font-semibold">You turned this offer down</p>
        <p className="max-w-[34ch] text-[12.5px] leading-relaxed text-ink-faint">
          Nothing has been borrowed and nothing is owed. Your limit is unchanged, and you can apply again whenever you
          want to.
        </p>
      </section>
    );
  }

  if (state === "signed") {
    return (
      <section className="card flex flex-col items-center gap-3 px-5 py-12 text-center">
        <span
          className="grid h-12 w-12 place-items-center rounded-2xl"
          style={{ background: "color-mix(in oklab, var(--lime) 24%, transparent)", color: "var(--green-ink)" }}
        >
          <Check className="h-6 w-6" strokeWidth={2.6} />
        </span>
        <p className="text-[15px] font-semibold">Agreement signed</p>
        <p className="max-w-[36ch] text-[12.5px] leading-relaxed text-ink-faint">
          A copy has been sent to your phone. {offer.lender} reviews it before the money moves — you will get a message
          either way.
        </p>
      </section>
    );
  }

  return (
    <div className="space-y-3">
      {/* ── What you receive, what you hand back. ───────────────────────── */}
      <section className="card overflow-hidden">
        <div
          className="flex items-center gap-2.5 border-b px-5 py-3.5"
          style={{ borderColor: "var(--line)" }}
        >
          <FileText className="h-[18px] w-[18px] shrink-0 text-ink-faint" strokeWidth={2.1} />
          <p className="flex-1 text-[13px] font-semibold">
            {offer.productName} <span className="font-normal text-ink-faint">from {offer.lender}</span>
          </p>
        </div>

        <div className="grid grid-cols-2">
          <div className="px-5 py-4">
            <p className="text-[10.5px] font-semibold uppercase tracking-[0.06em] text-ink-faint">You receive</p>
            <p className="tnum mt-1 text-[26px] font-bold leading-none tracking-[-0.03em]">{money(offer.principal)}</p>
          </div>
          <div className="px-5 py-4" style={{ borderLeft: "1px solid var(--line)" }}>
            <p className="text-[10.5px] font-semibold uppercase tracking-[0.06em] text-ink-faint">You repay</p>
            <p className="tnum mt-1 text-[26px] font-bold leading-none tracking-[-0.03em]">
              {money(offer.totalRepayable)}
            </p>
          </div>
        </div>

        <p
          className="border-t px-5 py-3 text-[12px] leading-snug text-ink-soft"
          style={{ borderColor: "var(--line)" }}
        >
          {periodCount(offer.termCount, offer.termUnit)}, first payment {shortDate(offer.firstDueDate)}, cleared by{" "}
          <strong className="font-semibold text-ink">{longDate(offer.expectedClearDate)}</strong>.
        </p>
      </section>

      {/* ── Every charge. ──────────────────────────────────────────────────
          The section this whole screen exists for. A rate is not a charge and
          "terms apply" is not a disclosure; these are the line items, and they
          add up on screen so nobody has to take the total on trust. */}
      <section className="card overflow-hidden">
        <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
          <p className="flex-1 text-[13px] font-semibold">What this loan costs you</p>
        </div>

        <dl className="px-5 py-2 text-[12.5px]">
          <Line label="Amount borrowed" value={exact(offer.principal)} muted />
          <Line
            label={`Interest — ${offer.interestRate}% ${offer.interestMethod}`}
            value={exact(offer.totalInterest)}
          />
          {charges.map((c) => (
            <Line
              key={c.name}
              label={c.name}
              value={exact(c.amount)}
              note={c.when === "before-disbursement" ? "payable before the money is sent" : undefined}
            />
          ))}
          <div
            className="mt-1 flex items-baseline justify-between gap-3 border-t py-3"
            style={{ borderColor: "var(--line-strong)" }}
          >
            <dt className="text-[13px] font-bold">Total cost of credit</dt>
            <dd className="tnum text-[15px] font-bold">{exact(costOfCredit)}</dd>
          </div>
        </dl>

        {charges.length === 0 && (
          <p
            className="flex items-start gap-2 border-t px-5 py-3 text-[11.5px] leading-snug text-ink-soft"
            style={{ borderColor: "var(--line)", background: "var(--surface-sunk)" }}
          >
            <Info className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
            Interest is the only charge on this agreement. If {offer.lender} adds a fee, it must appear here before you
            sign — not afterwards.
          </p>
        )}

        {upfront > 0 && (
          <p
            className="flex items-start gap-2 border-t px-5 py-3.5 text-[11.5px] leading-snug"
            style={{ borderColor: "var(--line)", background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
          >
            <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" style={{ color: "#b45309" }} strokeWidth={2.2} />
            <span>
              <strong className="font-semibold text-ink">{money(upfront)} is payable before the money is sent.</strong>{" "}
              You pay it, then {offer.lender} disburses {money(offer.principal)} to your M-PESA. It is not deducted
              from the loan.
            </span>
          </p>
        )}
      </section>

      {/* ── Pay early. ─────────────────────────────────────────────────────
          The server decides whether this is true, because it depends on the
          interest method, and a "pay early, pay less" line on a flat loan is a
          discount that does not exist. */}
      <section className="card flex items-start gap-3 p-4">
        <span
          className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
          style={{
            background: offer.payEarly.applies
              ? "color-mix(in oklab, var(--lime) 20%, transparent)"
              : "var(--surface-sunk)",
            color: offer.payEarly.applies ? "var(--green-ink)" : "var(--ink-faint)",
          }}
        >
          <TrendingDown className="h-[18px] w-[18px]" strokeWidth={2.2} />
        </span>
        <span className="min-w-0">
          <span className="block text-[13px] font-semibold leading-tight">
            {offer.payEarly.applies ? `Settle early and save about ${money(offer.payEarly.savingKes)}` : "Settling early"}
          </span>
          <span className="mt-1 block text-[11.5px] leading-snug text-ink-soft">{offer.payEarly.note}</span>
        </span>
      </section>

      {/* ── The schedule. All of it. ───────────────────────────────────── */}
      <section className="card overflow-hidden">
        <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
          <p className="flex-1 text-[13px] font-semibold">Every payment you are agreeing to</p>
          <span className="tnum text-[11.5px] text-ink-faint">{offer.schedule.length} payments</span>
        </div>

        {reshapeHonoured === false && (
          <p
            className="flex items-start gap-2 border-b px-5 py-3 text-[11.5px] leading-snug"
            style={{ borderColor: "var(--line)", background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
          >
            <Info className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
            <span>
              You asked to move some of these amounts around. That request is with {offer.lender} and has not changed
              this agreement — <strong className="font-semibold text-ink">the dates and amounts below are what you
              are signing today</strong>. The totals are the same either way.
            </span>
          </p>
        )}

        <ul>
          {offer.schedule.map((r) => (
            <li
              key={r.seq}
              className="flex items-center gap-3 border-b px-5 py-2.5 last:border-b-0"
              style={{ borderColor: "var(--line)" }}
            >
              <span
                className="tnum grid h-7 w-7 shrink-0 place-items-center rounded-lg text-[11.5px] font-bold"
                style={{ background: "var(--surface-sunk)", color: "var(--ink-faint)" }}
              >
                {r.seq}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[13px] font-medium leading-tight">{shortDate(r.dueDate)}</span>
                <span className="tnum mt-0.5 block text-[11px] text-ink-faint">
                  {exact(r.principalDue)} of the loan · {exact(r.interestDue)} interest
                </span>
              </span>
              <span className="tnum shrink-0 text-[13.5px] font-semibold">{exact(r.amountDue)}</span>
            </li>
          ))}
        </ul>

        <div
          className="flex items-baseline justify-between gap-3 border-t px-5 py-3"
          style={{ borderColor: "var(--line-strong)", background: "var(--surface-sunk)" }}
        >
          <span className="text-[12.5px] font-bold">Total</span>
          <span className="tnum text-[14px] font-bold">
            {exact(sum(offer.schedule.map((r) => ({ seq: r.seq, dueDate: r.dueDate, cents: toCents(r.amountDue) }))) / 100)}
          </span>
        </div>
      </section>

      {/* ── If you are late. Before the signature, not after it. ────────── */}
      <section className="card p-4">
        <div className="flex items-start gap-3">
          <span
            className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
            style={{ background: "color-mix(in oklab, #f0a92b 18%, transparent)", color: "#b45309" }}
          >
            <Clock className="h-[18px] w-[18px]" strokeWidth={2.2} />
          </span>
          <div className="min-w-0 space-y-1.5 text-[11.5px] leading-snug text-ink-soft">
            <p className="text-[13px] font-semibold text-ink">If a payment is late</p>
            <p>
              A late payment is reported to the credit reference bureau, and it lowers your limit here — the ladder
              moves down as well as up.
            </p>
            <p>
              Talk to {offer.lender} before the date rather than after it. A payment that is rescheduled in advance is
              not an arrear; one that is simply missed is.
            </p>
          </div>
        </div>
      </section>

      {/* ── The signature. ─────────────────────────────────────────────── */}
      {!signable ? (
        <section className="card p-5 text-center">
          <p className="text-[13px] font-semibold">
            {offer.status === "EXPIRED" ? "This offer has expired" : `This offer was already ${offer.status.toLowerCase()}`}
          </p>
          <p className="mx-auto mt-1.5 max-w-[34ch] text-[12px] leading-relaxed text-ink-faint">
            Offers are held for a few days because the assessment behind them ages. Apply again and a fresh one is
            drawn on today's figures.
          </p>
        </section>
      ) : (
        <section className="card overflow-hidden">
          <label className="flex cursor-pointer items-start gap-3 px-5 py-4">
            <input
              type="checkbox"
              checked={agreed}
              onChange={(e) => setAgreed(e.target.checked)}
              disabled={state !== "reading" && state !== "codeSent"}
              className="mt-0.5 h-[18px] w-[18px] shrink-0 rounded"
              style={{ accentColor: "var(--lime)" }}
            />
            <span className="text-[12.5px] leading-relaxed text-ink-soft">
              I have read this agreement. I understand that I will repay{" "}
              <strong className="font-semibold text-ink">{money(offer.totalRepayable)}</strong> in{" "}
              {offer.schedule.length} payments, and that the total cost of this credit is{" "}
              <strong className="font-semibold text-ink">{money(costOfCredit)}</strong>.
            </span>
          </label>

          {state === "codeSent" || state === "signing" ? (
            <div className="border-t px-5 py-4" style={{ borderColor: "var(--line)" }}>
              <p className="flex items-start gap-2 text-[12px] leading-snug text-ink-soft">
                <MessageSquareText className="mt-px h-3.5 w-3.5 shrink-0" style={{ color: "var(--green-ink)" }} />
                <span>
                  We sent a six-digit code to your phone. Typing it here is your signature — that is why it goes to the
                  number you verified, and why it only works on this agreement.
                </span>
              </p>

              <input
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                inputMode="numeric"
                // The one attribute that matters on this field: it lets the
                // handset offer the code straight from the SMS, which is the
                // difference between a signature and a memory test.
                autoComplete="one-time-code"
                aria-label="Signing code"
                placeholder="······"
                className="tnum mt-3 w-full rounded-xl border bg-transparent py-3.5 text-center text-[24px] font-bold tracking-[0.4em] outline-none placeholder:text-ink-faint"
                style={{ borderColor: error ? "#e11d48" : "var(--line-strong)", background: "var(--surface-sunk)" }}
              />
              {error && (
                <p className="mt-1.5 text-center text-[11.5px] font-medium" style={{ color: "#e11d48" }}>
                  {error}
                </p>
              )}

              <LiquidButton
                size="lg"
                block
                className="mt-3"
                trailingIcon={ArrowRight}
                loading={state === "signing"}
                disabled={!agreed || code.length < 6}
                onClick={submitCode}
              >
                Sign and accept
              </LiquidButton>

              <button
                onClick={requestCode}
                disabled={state === "signing"}
                className="mt-2 w-full py-2 text-[12px] font-semibold text-ink-faint"
              >
                Send the code again
              </button>
            </div>
          ) : (
            <div className="border-t px-5 py-4" style={{ borderColor: "var(--line)" }}>
              <LiquidButton
                size="lg"
                block
                trailingIcon={ArrowRight}
                loading={state === "sending"}
                disabled={!agreed}
                onClick={requestCode}
              >
                {agreed ? "Agree and sign" : "Tick the box to continue"}
              </LiquidButton>
              <p className="mt-2.5 flex items-start gap-2 text-[11px] leading-snug text-ink-faint">
                <ShieldCheck className="mt-px h-3.5 w-3.5 shrink-0" style={{ color: "var(--green-ink)" }} />
                We will send a code to your phone. Nothing is agreed until you type it back.
              </p>
            </div>
          )}
        </section>
      )}

      {/* Turning it down is an outcome, not an escape hatch. */}
      {signable && (
        <button
          onClick={() => setState("declined")}
          className="w-full py-2 text-center text-[12.5px] font-semibold text-ink-faint underline"
        >
          No thanks — turn this offer down
        </button>
      )}
    </div>
  );
}

function Line({ label, value, note, muted }: { label: string; value: string; note?: string; muted?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3 py-2">
      <dt className={muted ? "text-ink-faint" : "text-ink-soft"}>
        {label}
        {note && <span className="mt-0.5 block text-[11px] text-ink-faint">{note}</span>}
      </dt>
      <dd className={`tnum shrink-0 font-semibold ${muted ? "text-ink-faint" : ""}`}>{value}</dd>
    </div>
  );
}
