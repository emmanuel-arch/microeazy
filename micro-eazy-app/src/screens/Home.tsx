// ─────────────────────────────────────────────────────────────────────────────
// HOME — the screen the whole app is judged on in the first four seconds.
//
// The layout is the one Safaricom's mini-apps use, and it is used here for a
// reason rather than as homage: a saturated brand SKY at the top, and the real
// content on CARDS THAT OVERLAP IT. The overlap is the entire trick. It puts the
// most important number — what this person can borrow — on a surface that is
// definitely readable, while the brand still owns the top third. A gradient with
// text sitting directly on it looks like a splash screen; a card lifted onto it
// looks like a bank.
//
// The order down the page is the order of the questions a borrower actually
// asks, which is not the order a lender would put them in:
//   1. How much can I get, and what do I owe?      (the balance)
//   2. What can I do right now?                     (the four tiles)
//   3. Why did you decide that?                     (the reason strip)
//   4. Has anyone told me anything?                 (the lender's own messages)
//
// ── ON THE DESKTOP SPLIT ────────────────────────────────────────────────────
// Above `xl` this becomes two columns, and which things move right is not
// arbitrary. The left column is everything the customer CAME to do — the
// balance, the actions, the reason behind the number. The right column is
// everything that is true whether or not they act: what is next, what the lender
// has said, what they might want to learn. On a phone that same split becomes
// simple vertical order, because a phone has no right-hand side.
// ─────────────────────────────────────────────────────────────────────────────
import { Link, useNavigate } from "react-router-dom";
import {
  ArrowRight, Banknote, Gauge, ShieldCheck, FileText, Landmark, ChevronRight,
  CalendarClock, MessageSquareText, Radio,
} from "lucide-react";
import { Sky } from "../components/shell/Sky";
import { LiquidButton } from "../components/ui/LiquidButton";
import { Artwork } from "../components/media/Artwork";
import { ChannelBadge } from "../components/shell/ChannelBadge";

// Placeholder shape only — lib/api/portal.ts is the wiring, and it lands screen
// by screen. Kept in one object so the swap to `myLoan()` touches one line.
const customer = {
  firstName: "Emmanuel",
  limit: 45_000,
  outstanding: 12_500,
  score: 712,
  band: "Kuza",
  nextDueDate: "Fri 5 Sep",
  nextDueAmount: 2_600,
  ratibaOn: true,
};

const available = Math.max(customer.limit - customer.outstanding, 0);

const kes = (n: number) => `KSh ${n.toLocaleString("en-KE")}`;

/** Short enough to be read while walking. Each answers a question people
 *  actually ask a call centre, which is why they are here and not in a FAQ. */
const TIPS = [
  { slot: "tip-credit-score", motif: 0 as const, title: "What is a credit score?", body: "What it measures, and why yours moves every time you repay." },
  { slot: "tip-what-moves-limit", motif: 1 as const, title: "What moves your limit", body: "The four things we look at, in plain language." },
  { slot: "tip-charges", motif: 2 as const, title: "Understanding the charges", body: "What you pay, when, and what happens if you are late." },
];

/** Weekly, the Micro Eazy shape. Replaced by `myLoan().loan.schedule`. */
const SCHEDULE: { n: number; due: string; amount: number; status: "PAID" | "NEXT" | "DUE" }[] = [
  { n: 1, due: "Fri 15 Aug", amount: 2_600, status: "PAID" },
  { n: 2, due: "Fri 22 Aug", amount: 2_600, status: "PAID" },
  { n: 3, due: "Fri 29 Aug", amount: 2_600, status: "PAID" },
  { n: 4, due: "Fri 5 Sep", amount: 2_600, status: "NEXT" },
  { n: 5, due: "Fri 12 Sep", amount: 2_600, status: "DUE" },
  { n: 6, due: "Fri 19 Sep", amount: 2_600, status: "DUE" },
];

const ACTIONS = [
  { icon: Banknote, label: "New loan", note: "Decision in minutes", tint: "#5ec22a", to: "/join" },
  { icon: Landmark, label: "Repay", note: "M-PESA or Ratiba", tint: "#5b8cff", to: "/repay" },
  { icon: Gauge, label: "My score", note: "Out of 900", tint: "#f0a92b", to: "/score" },
  // Straight to the one step, not to the top of the wizard. `?step=` is a
  // presenter and grants nothing — see the note in onboarding/Onboarding.tsx.
  { icon: FileText, label: "Statements", note: "Crunch a new one", tint: "#a78bfa", to: "/join?step=statement" },
];

/** Straight from the lender, not a marketing blast. The distinction matters:
 *  a channel used for offers stops being read, and then the one message that
 *  mattered — a missed debit, a limit change — is missed with it. */
const MESSAGES = [
  { from: "Micromart Fintech", when: "2 days ago", body: "Your limit went up to KSh 45,000 after your last three repayments landed on time.", unread: true },
  { from: "Micromart Fintech", when: "1 week ago", body: "Ratiba is active. We will collect KSh 2,600 on the 5th — no action needed from you.", unread: false },
];

export default function Home() {
  const used = customer.limit > 0 ? customer.outstanding / customer.limit : 0;
  // The commit buttons navigate imperatively rather than being wrapped in a
  // Link: an <a> around a <button> is two nested interactive elements, which
  // screen readers announce twice and keyboards tab into twice.
  const go = useNavigate();

  return (
    <>
      <Sky title={`Hello, ${customer.firstName}`}>
        <p className="max-w-[34ch] text-[13px] leading-relaxed text-sky-ink-soft">
          Your limit is reviewed every time you repay. Nothing here is decided by a person.
        </p>
      </Sky>

      {/* `relative z-10` is load-bearing, not tidiness. The Sky is a positioned
          element, so it paints ABOVE any static sibling regardless of DOM order —
          which meant the header covered the top of this card and swallowed both
          the label and the tier badge. Only visible in the light theme, because
          in the dark one the card is translucent and it read as a tint. */}
      <div className="relative z-10 -mt-12">
        <ChannelBadge />

        <div className="px-4 xl:grid xl:grid-cols-[minmax(0,1.55fr)_minmax(0,1fr)] xl:items-start xl:gap-4">
          {/* ── LEFT: what you came to do. ───────────────────────────────── */}
          <div className="space-y-3">
            <section className="card p-5">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">
                    Available to borrow
                  </p>
                  <p className="tnum mt-1 text-[34px] font-bold leading-none tracking-[-0.03em]">{kes(available)}</p>
                  <p className="mt-1.5 text-[12px] text-ink-soft">
                    of {kes(customer.limit)} limit
                    {customer.outstanding > 0 && <> · {kes(customer.outstanding)} outstanding</>}
                  </p>
                </div>
                <span
                  className="flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold"
                  style={{ background: "color-mix(in oklab, var(--lime) 22%, transparent)", color: "var(--green-ink)" }}
                >
                  <ShieldCheck className="h-3.5 w-3.5" strokeWidth={2.4} /> {customer.band}
                </span>
              </div>

              {/* The bar carries the same information as the numbers above it,
                  which is the point: a number is read, a bar is GLANCED. */}
              <div className="mt-4 h-2 overflow-hidden rounded-full" style={{ background: "var(--surface-sunk)" }}>
                <div
                  className="h-full rounded-full transition-[width] duration-700"
                  style={{
                    width: `${Math.max(used * 100, customer.outstanding > 0 ? 6 : 0)}%`,
                    background: "linear-gradient(90deg, var(--green), var(--lime))",
                  }}
                />
              </div>

              <div className="mt-4 flex flex-col gap-2 sm:flex-row">
                <LiquidButton icon={Banknote} trailingIcon={ArrowRight} size="lg" block onClick={() => go("/join")}>
                  Apply for a loan
                </LiquidButton>
                <LiquidButton variant="metal" size="lg" block onClick={() => go("/repay")}>
                  Repay
                </LiquidButton>
              </div>
            </section>

            <section className="grid grid-cols-2 gap-3">
              {ACTIONS.map((a) => (
                <Link
                  key={a.label}
                  to={a.to}
                  className="card group flex items-start gap-3 p-4 text-left transition-transform duration-200 active:scale-[0.985]"
                >
                  <span
                    className="grid h-10 w-10 shrink-0 place-items-center rounded-xl"
                    style={{ background: `color-mix(in oklab, ${a.tint} 16%, transparent)`, color: a.tint }}
                  >
                    <a.icon className="h-[18px] w-[18px]" strokeWidth={2.2} />
                  </span>
                  <span className="min-w-0">
                    <span className="block text-[14px] font-semibold leading-tight">{a.label}</span>
                    <span className="mt-0.5 block text-[11.5px] leading-snug text-ink-faint">{a.note}</span>
                  </span>
                </Link>
              ))}
            </section>

            {/* The commitment, not a footnote. */}
            <Link to="/score" className="card flex w-full items-center gap-3 p-4 text-left">
              <span
                className="grid h-10 w-10 shrink-0 place-items-center rounded-xl"
                style={{ background: "color-mix(in oklab, var(--navy) 12%, transparent)", color: "var(--navy-ink)" }}
              >
                <Gauge className="h-[18px] w-[18px]" strokeWidth={2.2} />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[14px] font-semibold leading-tight">
                  Why your limit is {kes(customer.limit)}
                </span>
                <span className="mt-0.5 block text-[11.5px] leading-snug text-ink-faint">
                  The four things that moved your score, in plain language.
                </span>
              </span>
              <ChevronRight className="h-4 w-4 shrink-0 text-ink-faint" />
            </Link>

            {/* ── The schedule. ────────────────────────────────────────────
                Every collections call centre in Kenya exists largely to answer
                "how much do I still owe and when is the next one" down a phone.
                It is not a hard question. It has simply never been on the
                customer's own screen — so putting it here removes calls rather
                than deflecting them, which is a different and better thing. */}
            <section className="card overflow-hidden">
              <div
                className="flex items-center gap-2.5 border-b px-5 py-3.5"
                style={{ borderColor: "var(--line)" }}
              >
                <p className="flex-1 text-[13px] font-semibold">Your schedule</p>
                <span className="tnum text-[11.5px] text-ink-faint">
                  {SCHEDULE.filter((s) => s.status === "PAID").length} of {SCHEDULE.length} paid
                </span>
                <Link to="/repay" className="text-[12px] font-semibold" style={{ color: "var(--green-ink)" }}>
                  See all
                </Link>
              </div>

              <ul>
                {SCHEDULE.slice(0, 5).map((s) => {
                  const paid = s.status === "PAID";
                  const next = s.status === "NEXT";
                  return (
                    <li
                      key={s.n}
                      className="flex items-center gap-3 border-b px-5 py-3 last:border-b-0"
                      style={{
                        borderColor: "var(--line)",
                        background: next ? "color-mix(in oklab, var(--lime) 9%, transparent)" : undefined,
                      }}
                    >
                      <span
                        className="tnum grid h-8 w-8 shrink-0 place-items-center rounded-lg text-[12px] font-bold"
                        style={{
                          background: paid
                            ? "color-mix(in oklab, var(--green) 18%, transparent)"
                            : "var(--surface-sunk)",
                          color: paid ? "var(--green-ink)" : "var(--ink-faint)",
                        }}
                      >
                        {paid ? "✓" : s.n}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block text-[13px] font-medium leading-tight">{s.due}</span>
                        <span className="mt-0.5 block text-[11.5px] text-ink-faint">
                          {paid ? "Paid" : next ? "Next — Ratiba will collect this" : "Scheduled"}
                        </span>
                      </span>
                      <span
                        className="tnum shrink-0 text-[13.5px] font-semibold"
                        style={{ color: paid ? "var(--ink-faint)" : "var(--ink)" }}
                      >
                        {kes(s.amount)}
                      </span>
                    </li>
                  );
                })}
              </ul>
            </section>
          </div>

          {/* ── RIGHT: what is true whether or not you act. ──────────────── */}
          <aside className="mt-3 space-y-3 xl:mt-0">
            {/* What is next. The single most asked question in any collections
                call centre, answered before anybody has to ring. */}
            <section className="card p-5">
              <div className="flex items-center gap-2.5">
                <span
                  className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
                  style={{ background: "color-mix(in oklab, #5b8cff 16%, transparent)", color: "#3f6fd8" }}
                >
                  <CalendarClock className="h-[18px] w-[18px]" strokeWidth={2.2} />
                </span>
                <p className="text-[13px] font-semibold">Your next payment</p>
              </div>

              <p className="tnum mt-3 text-[26px] font-bold leading-none tracking-[-0.02em]">
                {kes(customer.nextDueAmount)}
              </p>
              <p className="mt-1 text-[12px] text-ink-soft">due {customer.nextDueDate}</p>

              {customer.ratibaOn ? (
                <p
                  className="mt-3 flex items-start gap-2 rounded-lg p-2.5 text-[11.5px] leading-snug"
                  style={{ background: "color-mix(in oklab, var(--lime) 16%, transparent)", color: "var(--green-ink)" }}
                >
                  <Radio className="mt-px h-3.5 w-3.5 shrink-0" strokeWidth={2.2} />
                  <span>
                    <strong className="font-semibold">Ratiba is on.</strong> We collect this automatically — you do not
                    need to do anything.
                  </span>
                </p>
              ) : (
                <LiquidButton size="sm" block className="mt-3" onClick={() => go("/repay")}>
                  Turn on auto-repay
                </LiquidButton>
              )}
            </section>

            {/* From the lender. Not marketing — a channel used for offers stops
                being read, and then the message that mattered goes unread too. */}
            <section className="card overflow-hidden">
              <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
                <MessageSquareText className="h-[18px] w-[18px] shrink-0 text-ink-faint" strokeWidth={2.1} />
                <p className="flex-1 text-[13px] font-semibold">From your lender</p>
                {MESSAGES.some((m) => m.unread) && (
                  <span
                    className="rounded-full px-2 py-0.5 text-[10.5px] font-bold"
                    style={{ background: "color-mix(in oklab, var(--lime) 24%, transparent)", color: "var(--green-ink)" }}
                  >
                    {MESSAGES.filter((m) => m.unread).length} new
                  </span>
                )}
              </div>
              <ul>
                {MESSAGES.map((m, i) => (
                  <li
                    key={i}
                    className="flex gap-2.5 border-b px-5 py-3.5 last:border-b-0"
                    style={{ borderColor: "var(--line)" }}
                  >
                    <span
                      aria-hidden
                      className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full"
                      style={{ background: m.unread ? "var(--green-ink)" : "transparent" }}
                    />
                    <span className="min-w-0">
                      <span className="flex items-baseline gap-2">
                        <span className="text-[12px] font-semibold">{m.from}</span>
                        <span className="text-[11px] text-ink-faint">{m.when}</span>
                      </span>
                      <span className="mt-0.5 block text-[12px] leading-snug text-ink-soft">{m.body}</span>
                    </span>
                  </li>
                ))}
              </ul>
            </section>

            {/* Advice and tips. A lending app that only ever asks for things is
                a lending app people close. */}
            <section>
              <div className="mb-2.5 flex items-baseline justify-between gap-3 px-1">
                <h2 className="text-[15px] font-bold tracking-[-0.015em]">Advice and tips</h2>
                <button className="text-[12.5px] font-semibold" style={{ color: "var(--green-ink)" }}>
                  View all
                </button>
              </div>

              {/* A scrolling row on a phone — bleeding to the edge, so a clipped
                  card is the affordance. A plain stack on a desktop, where the
                  column has the height and horizontal scrolling is a nuisance. */}
              <div className="-mx-4 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-1 [scrollbar-width:none] xl:mx-0 xl:flex-col xl:overflow-visible xl:px-0 [&::-webkit-scrollbar]:hidden">
                {TIPS.map((t) => (
                  <article
                    key={t.slot}
                    className="card w-[228px] shrink-0 snap-start overflow-hidden xl:flex xl:w-auto xl:shrink"
                  >
                    <Artwork
                      slot={t.slot}
                      motif={t.motif}
                      rounded="rounded-none"
                      className="xl:h-full xl:w-[104px] xl:shrink-0"
                    />
                    <div className="p-3.5">
                      <h3 className="text-[13.5px] font-semibold leading-tight">{t.title}</h3>
                      <p className="mt-1 text-[11.5px] leading-snug text-ink-faint">{t.body}</p>
                    </div>
                  </article>
                ))}
              </div>
            </section>
          </aside>
        </div>

        <p className="px-5 pb-2 pt-4 text-center text-[11px] leading-relaxed text-ink-faint">
          Micro Eazy is a technology platform. Your loan is funded by a licensed lender, and every decision on this
          screen can be explained to you on request.
        </p>
      </div>
    </>
  );
}
