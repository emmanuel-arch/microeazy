// ─────────────────────────────────────────────────────────────────────────────
// THE STATEMENT STEP — the one that decides the number.
//
// This is where most self-service lending funnels die, and the reason is always
// the same: the app says "upload your 6-month M-PESA statement" and the customer
// does not know how to get one. They are not being difficult. It is seven
// keypresses buried three levels into *334#, and nobody has ever shown them.
//
// So the instruction is not a sentence. It is the film, and under it the seven
// keypresses as a rail — each one a key, because that is what the customer is
// actually doing. Both are here, because a person on a matatu cannot watch a
// video and a person who cannot read English comfortably needs the film.
//
// The seven steps are the same list the lending console shows an officer on
// /console/crunch. They must not drift: an officer reading one script down the
// phone while the customer's screen shows another is worse than no script.
// ─────────────────────────────────────────────────────────────────────────────
import { useState } from "react";
import { FileUp, Lock, ShieldCheck, ArrowRight, Mail } from "lucide-react";
import { LiquidButton } from "../../components/ui/LiquidButton";
import { Film } from "../../components/media/Film";

/** Kept in step with connected-suite/src/components/statement/StatementHowTo.tsx.
 *  If Safaricom moves the menu, both change together or neither does. */
const USSD_STEPS: { key: string; label: string; detail?: string }[] = [
  { key: "*334#", label: "Dial the M-PESA menu" },
  { key: "7", label: "My Account" },
  { key: "3", label: "M-PESA Statement" },
  { key: "1", label: "Request Statement" },
  { key: "1", label: "Full Statement" },
  { key: "4", label: "Last 6 months", detail: "Six months is what we read. A shorter one cannot be scored." },
  { key: "OK", label: "Your email, again, then your M-PESA PIN", detail: "Safaricom texts you the password that opens it." },
];

export default function Statement({ onDone }: { onDone?: () => void }) {
  const [file, setFile] = useState<File | null>(null);
  const [password, setPassword] = useState("");

  return (
    <div className="space-y-3">
      {/* ── How to get it. Film first: it is the fastest route for most people. */}
      <section className="card overflow-hidden">
        <div className="p-3.5 pb-0">
          <Film slot="statement-walkthrough" />
        </div>

        <div className="px-5 pb-4 pt-4">
          <p className="text-[13px] font-semibold">Or follow the seven steps</p>
          <ol className="mt-3 space-y-0">
            {USSD_STEPS.map((s, i) => (
              <li key={i} className="relative flex gap-3 pb-3.5 last:pb-0">
                {i < USSD_STEPS.length - 1 && (
                  <span
                    aria-hidden
                    className="absolute left-[27px] top-9 bottom-0 w-px"
                    style={{ background: "var(--line)" }}
                  />
                )}
                <span
                  // FIXED WIDTH, not min-width. With chips sized to their own
                  // content the labels beside them started at seven different
                  // x positions and the rail read as ragged — the exact kind of
                  // detail that makes an app feel homemade. One width, one
                  // left edge for the text, and the thread can be centred.
                  className="tnum z-10 grid h-9 w-[3.5rem] shrink-0 place-items-center rounded-lg border px-1 font-mono text-[12.5px] font-bold"
                  style={{
                    borderColor: "var(--line-strong)",
                    background: "var(--surface-sunk)",
                    color: "var(--green-ink)",
                  }}
                >
                  {s.key}
                </span>
                <span className="min-w-0 pt-1.5">
                  <span className="block text-[13px] font-medium leading-snug">{s.label}</span>
                  {s.detail && (
                    <span className="mt-0.5 block text-[11.5px] leading-snug text-ink-faint">{s.detail}</span>
                  )}
                </span>
              </li>
            ))}
          </ol>

          <p
            className="mt-3 flex items-start gap-2 rounded-lg p-3 text-[11.5px] leading-snug text-ink-soft"
            style={{ background: "var(--surface-sunk)" }}
          >
            <Mail className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
            Safaricom emails the statement as a locked PDF. The password is in the SMS they send you — on older
            statements it is your ID number.
          </p>
        </div>
      </section>

      {/* ── Hand it over. ────────────────────────────────────────────────── */}
      <section className="card p-5">
        <label
          className="flex cursor-pointer flex-col items-center gap-2 rounded-xl border border-dashed px-4 py-8 text-center transition-colors"
          style={{ borderColor: "var(--line-strong)", background: "var(--surface-sunk)" }}
        >
          <span
            className="grid h-11 w-11 place-items-center rounded-xl"
            style={{ background: "color-mix(in oklab, var(--green) 16%, transparent)", color: "var(--green-ink)" }}
          >
            <FileUp className="h-5 w-5" strokeWidth={2.1} />
          </span>
          <span className="text-[13.5px] font-semibold">{file ? file.name : "Choose the statement PDF"}</span>
          <span className="text-[11.5px] leading-snug text-ink-faint">
            {file ? "Tap to choose a different one" : "The file Safaricom emailed you"}
          </span>
          <input
            type="file"
            accept="application/pdf,.pdf"
            className="hidden"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          />
        </label>

        <div
          className="mt-3 flex items-center gap-2.5 rounded-xl border px-3.5"
          style={{ borderColor: "var(--line-strong)", background: "var(--surface-sunk)" }}
        >
          <Lock className="h-[18px] w-[18px] shrink-0 text-ink-faint" strokeWidth={2} />
          <input
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Statement password"
            autoComplete="off"
            className="w-full bg-transparent py-3.5 text-[15px] font-medium outline-none placeholder:font-normal placeholder:text-ink-faint"
          />
        </div>

        <p className="mt-3 flex items-start gap-2 text-[11.5px] leading-snug text-ink-soft">
          <ShieldCheck className="mt-px h-3.5 w-3.5 shrink-0" style={{ color: "var(--green-ink)" }} />
          We read the statement to work out what you can afford. We do not keep the PDF after it is scored, and we
          never share it.
        </p>
      </section>

      <LiquidButton size="lg" block trailingIcon={ArrowRight} disabled={!file} onClick={() => onDone?.()}>
        {file ? "Read my statement" : "Choose your statement first"}
      </LiquidButton>
    </div>
  );
}
