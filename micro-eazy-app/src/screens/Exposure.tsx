// ─────────────────────────────────────────────────────────────────────────────
// WHAT THE CREDIT SYSTEM CAN SEE — the subject-access screen.
//
// Three separate things get asked about here and they are NOT the same thing,
// which is why they are three sections and not one number:
//
//   1. WITH THIS LENDER. What you owe the people whose app this is. Certain.
//   2. YOUR BUREAU FILE. What Metropol holds. Read from the last stored pull —
//      never a fresh one, see below.
//   3. THE NETWORK. What the other members of the Interchange are reporting.
//      Ranges and buckets, never names and never amounts.
//
// ── THE RULE THIS SCREEN IS BUILT AROUND ────────────────────────────────────
// "WE DID NOT FIND ANYTHING" AND "WE COULD NOT ASK" ARE DIFFERENT SENTENCES.
//
// The route returns five distinct interchange states and only ONE of them means
// the customer owes nothing elsewhere. Collapsing the other four into a clean
// bill of health would tell somebody their record is clear when it is merely
// unknown — and they would go and borrow against that belief. Every state below
// therefore gets its own words, its own icon and its own tone, and `partial` in
// particular is never allowed to read as `ok`.
//
// ── WHY THIS SCREEN NEVER SPENDS THE LENDER'S MONEY ─────────────────────────
// A live bureau pull is billed per pull and the tariff scales with the tier. An
// endpoint a customer can trigger, that pulls on every open, is a way to hand a
// lender a surprise invoice — and at scale, a denial-of-wallet. So the route
// reads the last STORED report and this screen says how old it is rather than
// offering a refresh button. When nothing is on file, "your lender has not
// checked you yet" is both true and useful: it tells the customer something
// real about how they are being assessed.
//
// ── AND CONSENT IS THE GATE, NOT A FOOTNOTE ─────────────────────────────────
// Both the bureau file and the network query are consent-gated, and where the
// consent is absent the section says so with the way to grant it — because a
// blank panel reads as "we have nothing on you", which is the opposite of what
// a withheld permission means.
// ─────────────────────────────────────────────────────────────────────────────
import {
  AlertTriangle, Building2, CircleSlash, Clock, Info, Landmark, Lock, Network, ShieldCheck, WifiOff,
} from "lucide-react";
import { Sky } from "../components/shell/Sky";
import { Artwork } from "../components/media/Artwork";
import type { ExposureResponse, Interchange, InterchangeState } from "../lib/api/portal";
import { SAMPLE_EXPOSURE } from "../lib/api/samples";
import { dateWithYear, sinceNow } from "../lib/format";

/**
 * One row per state. The `settled` flag is the important column: it marks the
 * ONE state whose answer can be relied on. Everything else is an answer about
 * our ability to ask, and the screen has to keep those apart.
 */
const STATES: Record<
  InterchangeState,
  { icon: typeof Network; tint: string; wash: string; title: string; settled: boolean }
> = {
  ok: {
    icon: Network, tint: "var(--green-ink)", wash: "color-mix(in oklab, var(--lime) 20%, transparent)",
    title: "Every lender answered", settled: true,
  },
  partial: {
    icon: AlertTriangle, tint: "#b45309", wash: "color-mix(in oklab, #f0a92b 20%, transparent)",
    title: "Some lenders could not be reached", settled: false,
  },
  refused: {
    icon: WifiOff, tint: "#b45309", wash: "color-mix(in oklab, #f0a92b 20%, transparent)",
    title: "The check could not be run", settled: false,
  },
  "not-consented": {
    icon: Lock, tint: "var(--ink-soft)", wash: "var(--surface-sunk)",
    title: "You have not permitted this check", settled: false,
  },
  "not-configured": {
    icon: CircleSlash, tint: "var(--ink-soft)", wash: "var(--surface-sunk)",
    title: "Not switched on for this lender", settled: false,
  },
};

export default function Exposure({
  /** Swap for `await exposure(nationalId)`. */
  data = SAMPLE_EXPOSURE,
}: {
  data?: ExposureResponse;
}) {
  const { crb, withThisLender, interchange } = data;

  return (
    <>
      <Sky title="Your credit file">
        <p className="max-w-[38ch] text-[13px] leading-relaxed text-sky-ink-soft">
          What we hold, what the bureau holds, and what other lenders can see about you.
        </p>
      </Sky>

      <div className="relative z-10 -mt-12 px-4 xl:grid xl:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)] xl:items-start xl:gap-4">
        <div className="space-y-3">
          {/* ── 1. This lender. The only completely certain section. ────── */}
          <section className="card p-5">
            <div className="flex items-center gap-2.5">
              <span
                className="grid h-9 w-9 shrink-0 place-items-center rounded-xl"
                style={{ background: "color-mix(in oklab, var(--navy) 12%, transparent)", color: "var(--navy-ink)" }}
              >
                <Landmark className="h-[18px] w-[18px]" strokeWidth={2.2} />
              </span>
              <p className="text-[13px] font-semibold">With {withThisLender.lender}</p>
            </div>

            <p className="tnum mt-3 text-[28px] font-bold leading-none tracking-[-0.03em]">
              {withThisLender.openLoans}
            </p>
            <p className="mt-1 text-[12.5px] text-ink-soft">
              open loan{withThisLender.openLoans === 1 ? "" : "s"} on this book
            </p>
            <p className="mt-2.5 text-[11.5px] leading-snug text-ink-faint">
              This is the one figure on the page we can be certain of — it is our own ledger, not a report about you
              from somewhere else.
            </p>
          </section>

          {/* ── 2. The bureau file. ─────────────────────────────────────── */}
          <section className="card overflow-hidden">
            <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
              <Building2 className="h-[18px] w-[18px] shrink-0 text-ink-faint" strokeWidth={2.1} />
              <p className="flex-1 text-[13px] font-semibold">Your credit reference file</p>
              {crb.report?.stale && (
                <span
                  className="rounded-full px-2 py-0.5 text-[10.5px] font-bold"
                  style={{ background: "color-mix(in oklab, #f0a92b 20%, transparent)", color: "#b45309" }}
                >
                  May be out of date
                </span>
              )}
            </div>

            {crb.available && crb.report ? (
              <>
                <div className="grid grid-cols-3">
                  {[
                    { k: "Score", v: crb.report.score != null ? String(crb.report.score) : "—" },
                    { k: "Grade", v: crb.report.grade ?? "—" },
                    { k: "Open accounts", v: crb.report.openAccounts != null ? String(crb.report.openAccounts) : "—" },
                  ].map((c, i) => (
                    <div key={c.k} className="px-4 py-4" style={{ borderLeft: i > 0 ? "1px solid var(--line)" : undefined }}>
                      <p className="text-[10.5px] font-semibold uppercase tracking-[0.06em] text-ink-faint">{c.k}</p>
                      <p className="tnum mt-1 text-[20px] font-bold leading-none tracking-[-0.02em]">{c.v}</p>
                    </div>
                  ))}
                </div>

                {crb.report.npaAccounts != null && (
                  <p
                    className="flex items-start gap-2 border-t px-5 py-3 text-[12px] leading-snug"
                    style={{ borderColor: "var(--line)", color: "var(--ink-soft)" }}
                  >
                    <ShieldCheck
                      className="mt-px h-3.5 w-3.5 shrink-0"
                      style={{ color: crb.report.npaAccounts === 0 ? "var(--green-ink)" : "#b45309" }}
                    />
                    {crb.report.npaAccounts === 0
                      ? "No account on your file is in default."
                      : `${crb.report.npaAccounts} account${crb.report.npaAccounts === 1 ? " is" : "s are"} recorded as non-performing.`}
                  </p>
                )}

                {crb.checkedAt && (
                  <p
                    className="flex items-start gap-2 border-t px-5 py-3 text-[11.5px] leading-snug text-ink-faint"
                    style={{ borderColor: "var(--line)", background: "var(--surface-sunk)" }}
                  >
                    <Clock className="mt-px h-3.5 w-3.5 shrink-0" />
                    <span>
                      Pulled {sinceNow(crb.checkedAt)} — {dateWithYear(crb.checkedAt)}. We show you the stored copy
                      rather than running a new check, because each pull is charged to your lender.
                    </span>
                  </p>
                )}
              </>
            ) : (
              <Absent
                icon={crb.consented ? Info : Lock}
                title={crb.consented ? "Nothing on file yet" : "You have not permitted this check"}
                body={crb.message ?? ""}
                action={crb.consented ? null : "Open Permissions"}
              />
            )}
          </section>

          {/* ── 3. The network. Five states, five sentences. ────────────── */}
          <NetworkSection interchange={interchange} />
        </div>

        {/* ── Right: what the network is, in the customer's words. ─────── */}
        <aside className="mt-3 space-y-3 xl:mt-0">
          <section className="card overflow-hidden">
            {/* Motif 1 is the BARS composition, chosen rather than hashed. The
                slot's brief asks for something structural — a ledger, a lock, a
                network — because a flowing organic form on this particular
                screen reads as a person, and the whole point of the screen is
                that no person's data is being handed to strangers. */}
            <Artwork slot="exposure-interchange" motif={1} rounded="rounded-none" />
            <div className="space-y-2 px-5 py-4 text-[11.5px] leading-relaxed text-ink-soft">
              <p className="text-[13.5px] font-semibold leading-tight text-ink">What is actually shared</p>
              <p>
                Lenders on the network are told <strong className="font-semibold text-ink">ranges</strong> — a band
                your borrowing falls in — and whether your repayments are current. That is all.
              </p>
              <p>
                They are never told your name, your ID number or your phone number, and they are never given an exact
                amount. That is enforced where the query runs, not promised here.
              </p>
              <p className="flex items-start gap-2 rounded-lg p-2.5" style={{ background: "var(--surface-sunk)" }}>
                <Info className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
                <span>
                  It works both ways. We ask about you, and they may ask the same about you through us. You agreed to
                  both halves or to neither — there was never a version where only we could ask.
                </span>
              </p>
            </div>
          </section>

          <section className="card p-5">
            <p className="text-[13px] font-semibold">This is your file</p>
            <p className="mt-1.5 text-[12px] leading-relaxed text-ink-soft">
              You can withdraw any permission on this page at any time. Withdrawing stops the next check — it cannot
              un-make a decision already taken, and we would rather say that than let you find it out.
            </p>
            <button
              className="mt-3.5 w-full rounded-full border py-3 text-[13px] font-semibold"
              style={{ borderColor: "var(--line-strong)", color: "var(--ink)" }}
            >
              Manage your permissions
            </button>
          </section>
        </aside>
      </div>
    </>
  );
}

function NetworkSection({ interchange }: { interchange: Interchange }) {
  const s = STATES[interchange.state] ?? STATES.refused;
  const Icon = s.icon;
  const found = (interchange.lenders ?? 0) > 0;

  return (
    <section className="card overflow-hidden">
      <div className="flex items-center gap-2.5 border-b px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
        <Network className="h-[18px] w-[18px] shrink-0 text-ink-faint" strokeWidth={2.1} />
        <p className="flex-1 text-[13px] font-semibold">Across other lenders</p>
      </div>

      <div className="flex items-start gap-3 px-5 py-4">
        <span
          className="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-xl"
          style={{ background: s.wash, color: s.tint }}
        >
          <Icon className="h-[18px] w-[18px]" strokeWidth={2.3} />
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-[13.5px] font-semibold leading-tight">{s.title}</p>
          {interchange.message && (
            <p className="mt-1.5 text-[12px] leading-relaxed text-ink-soft">{interchange.message}</p>
          )}
        </div>
      </div>

      {/* Figures are only shown where there is something to show. On a state
          that could not complete they still appear — a floor is more useful
          than nothing — but the banner below never lets them read as a total. */}
      {(interchange.state === "ok" || interchange.state === "partial") && found && (
        <>
          <div className="grid grid-cols-2 border-t" style={{ borderColor: "var(--line)" }}>
            <div className="px-5 py-3.5">
              <p className="text-[10.5px] font-semibold uppercase tracking-[0.06em] text-ink-faint">Owed elsewhere</p>
              <p className="tnum mt-1 text-[15px] font-bold leading-tight tracking-[-0.01em]">
                {interchange.outstandingBand}
              </p>
              <p className="mt-1 text-[10.5px] text-ink-faint">a range, never an exact figure</p>
            </div>
            <div className="px-5 py-3.5" style={{ borderLeft: "1px solid var(--line)" }}>
              <p className="text-[10.5px] font-semibold uppercase tracking-[0.06em] text-ink-faint">Other lenders</p>
              <p className="tnum mt-1 text-[15px] font-bold leading-tight tracking-[-0.01em]">
                {interchange.lenders} · {interchange.activeLoans} loan
                {interchange.activeLoans === 1 ? "" : "s"}
              </p>
              <p className="mt-1 text-[10.5px] text-ink-faint">names are never disclosed</p>
            </div>
          </div>

          {(interchange.velocity14d ?? 0) > 0 && (
            <p
              className="flex items-start gap-2 border-t px-5 py-3 text-[11.5px] leading-snug text-ink-soft"
              style={{ borderColor: "var(--line)" }}
            >
              <Clock className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" />
              <span>
                {interchange.velocity14d} new loan{interchange.velocity14d === 1 ? "" : "s"} taken across the network
                in the last two weeks. Borrowing quickly in several places is the pattern lenders watch for most
                closely — including for your sake.
              </span>
            </p>
          )}
        </>
      )}

      {/* The line that stops a floor being read as a total. */}
      {!s.settled && (interchange.state === "partial" || interchange.state === "ok") && (
        <p
          className="flex items-start gap-2 border-t px-5 py-3.5 text-[11.5px] leading-snug"
          style={{ borderColor: "var(--line)", background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
        >
          <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" style={{ color: "#b45309" }} />
          <span>
            {interchange.responded} of {interchange.queried} lenders answered.{" "}
            <strong className="font-semibold text-ink">Treat this as a floor, not a total</strong> — there may be more
            that the ones who did not answer would have reported.
          </span>
        </p>
      )}

      {(interchange.state === "not-consented" || interchange.state === "not-configured") && (
        <div className="border-t px-5 py-3.5" style={{ borderColor: "var(--line)" }}>
          {interchange.state === "not-consented" ? (
            <button
              className="w-full rounded-full border py-2.5 text-[12.5px] font-semibold"
              style={{ borderColor: "var(--line-strong)", color: "var(--ink)" }}
            >
              Open Permissions
            </button>
          ) : (
            <p className="text-[11.5px] leading-snug text-ink-faint">
              Nothing is missing from your file — this lender simply has not joined the network yet.
            </p>
          )}
        </div>
      )}

      {interchange.asOf && (interchange.state === "ok" || interchange.state === "partial") && (
        <p className="border-t px-5 py-2.5 text-[11px] text-ink-faint" style={{ borderColor: "var(--line)" }}>
          As at {dateWithYear(interchange.asOf)}.
        </p>
      )}
    </section>
  );
}

/** A section with nothing in it, said in words rather than left blank. An empty
 *  panel reads as "we have nothing on you", which is the opposite of what a
 *  withheld permission means. */
function Absent({
  icon: Icon, title, body, action,
}: {
  icon: typeof Info;
  title: string;
  body: string;
  action: string | null;
}) {
  return (
    <div className="flex items-start gap-3 px-5 py-5">
      <span
        className="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-xl"
        style={{ background: "var(--surface-sunk)", color: "var(--ink-soft)" }}
      >
        <Icon className="h-[18px] w-[18px]" strokeWidth={2.2} />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-[13.5px] font-semibold leading-tight">{title}</p>
        {body && <p className="mt-1.5 text-[12px] leading-relaxed text-ink-soft">{body}</p>}
        {action && (
          <button
            className="mt-3 rounded-full border px-4 py-2 text-[12.5px] font-semibold"
            style={{ borderColor: "var(--line-strong)", color: "var(--ink)" }}
          >
            {action}
          </button>
        )}
      </div>
    </div>
  );
}
