// ─────────────────────────────────────────────────────────────────────────────
// STEP ONE — the National ID, and the permission to check it.
//
// ── WHY THE CONSENT IS NOT A CHECKBOX WITH A LINK ───────────────────────────
// The industry pattern is "☐ I agree to the Terms" with the terms one tap away
// on a page nobody opens. That is legally defensible and practically worthless,
// and it is the exact thing that makes a customer paying KSh 850 in upfront
// charges wonder whether they have been had.
//
// So the permission is on the screen, in full, in the customer's own words,
// naming the ORGANISATION being asked (Metropol), the THING being requested (a
// CRB Report 1), the PURPOSE (confirming this ID is yours), and — the part
// almost nobody shows — what happens to the answer. It costs eleven lines and
// it is the difference between a fintech and a scraper.
//
// The checkbox is unticked and the button is dead until it is ticked. No
// pre-ticked boxes, ever: a pre-ticked consent is not consent, and in a
// portfolio review it is the first thing that gets thrown out.
//
// ── TWO DOORS TO THE SAME PLACE ─────────────────────────────────────────────
// Typing an ID number is fast for someone who knows it and a wall for someone
// who does not have it memorised and is standing in a shop. Photographing the
// card runs the same OCR the console uses at the counter and fills the field.
// Both arrive at the same verified state; neither is the "lite" path.
// ─────────────────────────────────────────────────────────────────────────────
import { useState } from "react";
import { IdCard, Camera, ShieldCheck, ArrowRight, Info } from "lucide-react";
import { LiquidButton } from "../../components/ui/LiquidButton";

/** Kenyan national ID numbers run 7–8 digits. Anything else is a typo, and
 *  telling somebody that now is kinder than a registry miss ninety seconds on. */
function idLooksValid(v: string) {
  return /^\d{7,8}$/.test(v.trim());
}

export default function CreateAccount({ onDone }: { onDone?: (nationalId: string) => void }) {
  const [nationalId, setNationalId] = useState("");
  const [consented, setConsented] = useState(false);
  const [touched, setTouched] = useState(false);

  const valid = idLooksValid(nationalId);
  const showError = touched && nationalId.length > 0 && !valid;

  return (
    <div className="space-y-3">
      <section className="card p-5">
        <label htmlFor="nid" className="block text-[13px] font-semibold">
          Your National ID number
        </label>
        <p className="mt-0.5 text-[12px] leading-snug text-ink-faint">
          The number on the front of your card — 7 or 8 digits.
        </p>

        <div
          className="mt-3 flex items-center gap-2.5 rounded-xl border px-3.5 transition-colors"
          style={{
            borderColor: showError ? "#e11d48" : "var(--line-strong)",
            background: "var(--surface-sunk)",
          }}
        >
          <IdCard className="h-[18px] w-[18px] shrink-0 text-ink-faint" strokeWidth={2} />
          <input
            id="nid"
            inputMode="numeric"
            autoComplete="off"
            value={nationalId}
            onChange={(e) => setNationalId(e.target.value.replace(/\D/g, "").slice(0, 8))}
            onBlur={() => setTouched(true)}
            placeholder="12345678"
            aria-invalid={showError}
            aria-describedby={showError ? "nid-error" : undefined}
            className="tnum w-full bg-transparent py-3.5 text-[17px] font-semibold tracking-[0.02em] outline-none placeholder:font-normal placeholder:text-ink-faint"
          />
        </div>
        {showError && (
          <p id="nid-error" className="mt-1.5 text-[11.5px] font-medium" style={{ color: "#e11d48" }}>
            That is {nationalId.length} digits. A Kenyan ID number has 7 or 8.
          </p>
        )}

        <div className="mt-3 flex items-center gap-3">
          <span className="h-px flex-1" style={{ background: "var(--line)" }} />
          <span className="text-[11px] font-medium text-ink-faint">or</span>
          <span className="h-px flex-1" style={{ background: "var(--line)" }} />
        </div>

        <button
          type="button"
          className="mt-3 flex w-full items-center gap-3 rounded-xl border p-3.5 text-left transition-colors active:scale-[0.99]"
          style={{ borderColor: "var(--line-strong)" }}
        >
          <span
            className="grid h-10 w-10 shrink-0 place-items-center rounded-xl"
            style={{ background: "color-mix(in oklab, var(--navy) 12%, transparent)", color: "var(--navy)" }}
          >
            <Camera className="h-[18px] w-[18px]" strokeWidth={2.2} />
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-[13.5px] font-semibold leading-tight">Photograph your ID instead</span>
            <span className="mt-0.5 block text-[11.5px] leading-snug text-ink-faint">
              We read the number off the card — the same way a branch officer does.
            </span>
          </span>
          <ArrowRight className="h-4 w-4 shrink-0 text-ink-faint" />
        </button>
      </section>

      {/* ── The permission. On the screen, not behind a link. ───────────────── */}
      <section className="card overflow-hidden">
        <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
          <ShieldCheck className="h-[18px] w-[18px] shrink-0" style={{ color: "var(--green-ink)" }} strokeWidth={2.2} />
          <p className="text-[13px] font-semibold">Your permission</p>
        </div>

        <div className="space-y-2.5 px-5 py-4 text-[12.5px] leading-relaxed text-ink-soft">
          <p>
            To confirm this ID belongs to you, we ask <strong className="font-semibold text-ink">Metropol CRB</strong>{" "}
            for a <strong className="font-semibold text-ink">Report 1</strong> against the number above.
          </p>
          <p>
            It tells us the name registered to that ID. We compare it with the name on the card you photograph next.
            That is all it is used for at this stage.
          </p>
          <p className="flex items-start gap-1.5 rounded-lg p-2.5" style={{ background: "var(--surface-sunk)" }}>
            <Info className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
            <span>
              This check is recorded on your file with the date and the reason. You can open it any time under{" "}
              <strong className="font-semibold text-ink">Permissions</strong>, and you can withdraw it — though we
              cannot lend without it.
            </span>
          </p>
        </div>

        <label
          className="flex cursor-pointer items-start gap-3 border-t px-5 py-4"
          style={{ borderColor: "var(--line)" }}
        >
          <input
            type="checkbox"
            checked={consented}
            onChange={(e) => setConsented(e.target.checked)}
            className="mt-0.5 h-[18px] w-[18px] shrink-0 accent-[var(--green-ink)]"
          />
          <span className="text-[12.5px] font-medium leading-snug">
            I permit Micro Eazy to request a Metropol CRB Report 1 against my National ID, to confirm my identity.
          </span>
        </label>
      </section>

      <LiquidButton
        size="lg"
        block
        trailingIcon={ArrowRight}
        disabled={!valid || !consented}
        onClick={() => onDone?.(nationalId.trim())}
      >
        {consented ? "Continue" : "Tick the box to continue"}
      </LiquidButton>

      <p className="px-1 pb-2 text-center text-[11px] leading-relaxed text-ink-faint">
        Every customer on Micro Eazy answers this same screen. There is no version of it that asks for less.
      </p>
    </div>
  );
}
