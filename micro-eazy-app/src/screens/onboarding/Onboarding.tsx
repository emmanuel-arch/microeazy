// ─────────────────────────────────────────────────────────────────────────────
// THE ONBOARDING HOST.
//
// It holds no opinion about what the steps are. It reads them from
// lib/journey/steps.ts, which is the lender's configuration, and renders
// whichever ones this lender asks the customer to do. Adding a step to the
// journey does not touch this file; turning one off does not either.
//
// That indirection is the point rather than an abstraction for its own sake:
// the moment the sequence is hard-coded here, "configurable onboarding" becomes
// a slide rather than a property of the software, and the first lender who wants
// a different order gets a fork.
//
// The screens themselves are dumb: each one takes what it needs and calls
// onDone. None of them knows its own position, so none of them breaks when the
// order changes.
// ─────────────────────────────────────────────────────────────────────────────
import { useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { Construction } from "lucide-react";
import { Sky } from "../../components/shell/Sky";
import { Stepper } from "../../components/onboarding/Stepper";
import { customerSteps, type JourneyConfig, type StepId } from "../../lib/journey/steps";
import type { Quote } from "../../lib/quote";
import type { Row } from "../../lib/schedule/reshape";
import CreateAccount from "./CreateAccount";
import Statement from "./Statement";
import ProductChoice from "./ProductChoice";
import ScheduleEditor from "./ScheduleEditor";
import LoanAgreement from "./LoanAgreement";
import Ratiba from "./Ratiba";

/** Micromart's day-one configuration. This will come from the lender's own
 *  settings once the console screen lands; the shape is already correct. */
const MICROMART: JourneyConfig = {};

export default function Onboarding() {
  const steps = useMemo(() => customerSteps(MICROMART), []);
  const [search] = useSearchParams();

  // ?step=<id> opens the journey at one screen. It is here for support ("open
  // the statement step and read it to me") and for reviewing a screen without
  // walking six others to reach it.
  //
  // It grants nothing. The wizard is a PRESENTER: every gate that matters is
  // enforced on the server against the persisted session, and finalize reads
  // that row rather than anything the client says. Skipping to the last screen
  // gets you a screen, not a verification.
  const start = useMemo(() => {
    const wanted = search.get("step");
    const i = wanted ? steps.findIndex((s) => s.id === wanted) : -1;
    return i >= 0 ? i : 0;
  }, [search, steps]);

  const [index, setIndex] = useState(start);

  // ── THE DRAFT ────────────────────────────────────────────────────────────
  // What the customer has built so far, held by the host rather than by any one
  // screen. It exists because the later steps are not independent of the
  // earlier ones: the schedule editor reshapes the chosen product's own rows,
  // and the agreement has to know whether what it is showing is the plan the
  // customer asked for. Keeping it here leaves every screen dumb — none of them
  // knows its own position, so none of them breaks when the order changes.
  //
  // It holds a PROPOSAL and never an entitlement. Nothing in it grants
  // anything: every gate that matters is enforced on the server against the
  // persisted session, so a draft assembled by hand is a draft, not a loan.
  const [nationalId, setNationalId] = useState<string | null>(null);
  const [quote, setQuote] = useState<Quote | null>(null);
  const [rows, setRows] = useState<Row[] | null>(null);

  const step = steps[index];
  const done = index >= steps.length;

  const next = () => setIndex((i) => Math.min(i + 1, steps.length));
  const back = () => setIndex((i) => Math.max(i - 1, 0));

  if (done || !step) {
    return (
      <>
        <Sky title="You are all set" />
        <div className="relative z-10 -mt-12 px-4">
          <section className="card px-5 py-10 text-center">
            <p className="text-[15px] font-semibold">Onboarding complete</p>
            <p className="mx-auto mt-2 max-w-[38ch] text-[12.5px] leading-relaxed text-ink-faint">
              {nationalId ? `ID ${nationalId} verified. ` : ""}
              Your agreement is signed and your lender is reviewing it before the money moves. You will get a message
              either way — there is nothing else for you to do.
            </p>
          </section>
        </div>
      </>
    );
  }

  return (
    <>
      <Sky title={step.title} onBack={index > 0 ? back : undefined}>
        <p className="max-w-[36ch] text-[13px] leading-relaxed text-sky-ink-soft">{step.blurb}</p>
        <div className="mt-4">
          <Stepper total={steps.length} index={index} />
        </div>
      </Sky>

      {/* The step says how much room it wants and the host gives it exactly
          that. A National ID field does not get better at 1040px — it gets
          harder to read across — but the schedule editor is a workspace with
          ten rows and a running total, and squeezing that into a phone column
          on a laptop throws away the only thing the laptop is better at.

          This is a CONTAINER decision, not a viewport one. The editor's own
          two-column grid keys off `xl`, which is the WINDOW being 1280px wide —
          it fired happily inside a 620px container and produced two cramped
          columns instead of one good one. Width has to be granted from above. */}
      <div
        className={`relative z-10 -mt-12 px-4 ${
          step.canvas === "wide" ? "mx-auto max-w-[1040px]" : "mx-auto max-w-[620px]"
        }`}
      >
        {step.id === "account" ? (
          <CreateAccount
            onDone={(id) => {
              setNationalId(id);
              next();
            }}
          />
        ) : step.id === "product" ? (
          <ProductChoice
            onDone={(q) => {
              setQuote(q);
              // A new product invalidates a schedule shaped against the old
              // one — ten weekly rows do not survive a move to four monthly
              // ones, and carrying them forward would hand the agreement a
              // plan for a loan nobody chose.
              setRows(null);
              next();
            }}
          />
        ) : step.id === "schedule" ? (
          <ScheduleEditor
            quote={quote}
            onDone={(r) => {
              setRows(r);
              next();
            }}
          />
        ) : step.id === "consent" ? (
          <LoanAgreement proposed={rows} onDone={() => next()} />
        ) : step.id === "ratiba" ? (
          <Ratiba onDone={next} />
        ) : step.id === "statement" ? (
          <Statement onDone={next} />
        ) : (
          <NotBuiltYet id={step.id} onSkip={next} />
        )}
      </div>
    </>
  );
}

/** A named empty room, not a dead end. Keeping unbuilt steps routable means the
 *  journey is walkable end to end today, which is how the ORDER gets reviewed
 *  before any of the screens exist to argue about. */
function NotBuiltYet({ id, onSkip }: { id: StepId; onSkip: () => void }) {
  return (
    <section className="card flex flex-col items-center gap-3 px-5 py-12 text-center">
      <span
        className="grid h-12 w-12 place-items-center rounded-2xl"
        style={{ background: "color-mix(in oklab, var(--navy) 10%, transparent)", color: "var(--navy-ink)" }}
      >
        <Construction className="h-5 w-5" strokeWidth={2} />
      </span>
      <p className="text-[13px] font-semibold">
        <code className="font-mono">{id}</code> is next to build
      </p>
      <button onClick={onSkip} className="text-[12.5px] font-semibold underline" style={{ color: "var(--green-ink)" }}>
        Walk past it for now
      </button>
    </section>
  );
}
