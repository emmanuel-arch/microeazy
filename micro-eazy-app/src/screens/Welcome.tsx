// ─────────────────────────────────────────────────────────────────────────────
// THE FRONT DOOR.
//
// The first screen a customer sees, and the only one on which this app has to
// earn the right to ask for a national ID number. Two halves and they do
// different jobs:
//
//   · THE DECK — four photographs of the people who actually borrow here, with
//     a promise beside each one. It is the whole argument for the product, made
//     in pictures, before a single field is asked for. See components/media/
//     Voices, and the note there about why these are promises and not
//     testimonials.
//   · THE FORM — a phone number and nothing else. Every extra field on a sign-in
//     screen is a percentage of people who do not finish, and this funnel is
//     opened on a prepaid bundle at the side of a road.
//
// ── THE ORDER IS DIFFERENT ON A PHONE, ON PURPOSE ────────────────────────────
// On a laptop the deck is the left column and the form is the right, read left
// to right. On a handset the deck comes FIRST and the form underneath, because
// the phone is the design target and the argument has to arrive before the ask.
// The one thing that never moves below the fold on a 360×640 screen is the
// continue button — hence the deck's aspect ratio dropping on small screens.
//
// ── WHAT THIS SCREEN DOES NOT DO ─────────────────────────────────────────────
// It does not verify anything. It collects a number and hands off to the
// onboarding host, which is where identity is actually proved against the
// server. Nothing typed here grants anything, which is the same rule every
// other screen in this app follows.
// ─────────────────────────────────────────────────────────────────────────────
import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowRight, Phone, ShieldCheck } from "lucide-react";
import { Voices } from "../components/media/Voices";
import { LiquidButton } from "../components/ui/LiquidButton";
import { ThemeToggle } from "../components/shell/ThemeToggle";

/**
 * Kenyan mobile numbers, loosely. Deliberately loose: this is a courtesy check
 * that stops an obvious typo before a round trip, NOT a validation — the server
 * owns that, and a client-side rule strict enough to be authoritative is a rule
 * that eventually rejects a real customer on a new prefix.
 */
const looksLikeAPhone = (v: string) => v.replace(/\D/g, "").length >= 9;

export default function Welcome() {
  const navigate = useNavigate();
  const [phone, setPhone] = useState("");
  const [touched, setTouched] = useState(false);

  const ok = looksLikeAPhone(phone);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    setTouched(true);
    if (!ok) return;
    navigate("/join");
  };

  return (
    <div className="min-h-full">
      {/* ── The band ───────────────────────────────────────────────────────
          A short one. The sky on every other screen is a header carrying a
          title; here it is just enough colour to seat the wordmark, because the
          photographs below are doing the work that a gradient does elsewhere. */}
      <header className="sky aurora relative overflow-hidden rounded-b-[28px] px-5 pb-10 pt-[max(env(safe-area-inset-top),1rem)] lg:rounded-b-[32px]">
        <div className="relative z-10 flex items-center gap-3 py-2">
          <span
            className="grid h-10 w-10 shrink-0 place-items-center rounded-xl text-[16px] font-black text-white"
            style={{ background: "rgb(255 255 255 / 0.14)", boxShadow: "inset 0 1px 0 rgb(255 255 255 / 0.28)" }}
          >
            M
          </span>
          <span className="min-w-0 flex-1 leading-none">
            <span className="block text-[16px] font-bold tracking-[-0.02em] text-sky-ink">Micro Eazy</span>
            <span className="block pt-1 text-[11.5px] text-sky-ink-soft">Quick loans. Better living.</span>
          </span>
          <ThemeToggle />
        </div>
      </header>

      {/* ── The two halves ────────────────────────────────────────────────
          `lg:items-center` rather than `items-start`: the form is much shorter
          than the deck, and pinned to the top it leaves a column of empty page
          under it that reads as a screen that failed to finish loading. */}
      <div className="mx-auto grid w-full max-w-[560px] gap-8 px-4 pb-16 pt-6 lg:max-w-[1080px] lg:grid-cols-2 lg:items-center lg:gap-14 lg:pt-10">
        <Voices />

        <div>
          <h1 className="text-[26px] font-bold leading-[1.15] tracking-[-0.025em] text-ink">
            Welcome.
          </h1>
          <p className="mt-2 max-w-[36ch] text-[14px] leading-relaxed text-ink-soft">
            Enter the number your M-Pesa is on. That is the whole of it — we will take you through the rest one step
            at a time.
          </p>

          <form onSubmit={submit} className="mt-6">
            <label htmlFor="phone" className="block text-[12px] font-semibold uppercase tracking-[0.08em] text-ink-faint">
              Phone number
            </label>
            <div
              className="mt-2 flex items-center gap-2.5 rounded-2xl border px-4 transition-colors focus-within:border-[var(--green-ink)]"
              style={{ background: "var(--surface)", borderColor: touched && !ok ? "var(--line-strong)" : "var(--line)" }}
            >
              <Phone className="h-[18px] w-[18px] shrink-0 text-ink-faint" strokeWidth={2} />
              <span className="shrink-0 text-[15px] font-medium text-ink-soft">+254</span>
              <input
                id="phone"
                type="tel"
                inputMode="numeric"
                autoComplete="tel-national"
                placeholder="7XX XXX XXX"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                aria-invalid={touched && !ok}
                aria-describedby={touched && !ok ? "phone-error" : undefined}
                className="tnum min-w-0 flex-1 bg-transparent py-4 text-[16px] text-ink outline-none placeholder:text-ink-faint"
              />
            </div>
            {/* Only after a submit. Marking a field wrong while somebody is
                still typing the first digit of it is how a form tells people
                they are failing at something they have not finished. */}
            {touched && !ok && (
              <p id="phone-error" className="mt-2 text-[12.5px] text-ink-soft">
                That does not look like a full number yet — nine digits after the +254.
              </p>
            )}

            <LiquidButton type="submit" size="lg" block trailingIcon={ArrowRight} className="mt-5">
              Continue
            </LiquidButton>
          </form>

          <p className="mt-4 flex items-start gap-2 text-[12px] leading-relaxed text-ink-faint">
            <ShieldCheck className="mt-px h-3.5 w-3.5 shrink-0" style={{ color: "var(--green-ink)" }} />
            <span>
              We check your number against your national ID before any money moves. Nothing is shared with anyone who
              is not lending to you.
            </span>
          </p>
        </div>
      </div>
    </div>
  );
}
