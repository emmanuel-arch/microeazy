// ─────────────────────────────────────────────────────────────────────────────
// THE JOURNEY — one declarative list, and the two promises it has to keep at
// the same time.
//
//   MORRIS'S PROMISE (governance): every customer goes through the same process,
//   the same scrutiny, the same consent. Not "usually". Not "unless the officer
//   is in a hurry". The same.
//
//   GEOFFREY'S PROMISE (configurability): Micromart's workflow must not become
//   everyone's workflow. A lender turns stages on, off, or hands them to the
//   machine, and the product accommodates them.
//
// Those two look contradictory and are not, because they are about DIFFERENT
// THINGS. What is configurable is WHO DOES THE WORK and HOW MUCH CEREMONY it
// carries. What is not configurable is whether the check happened.
//
// So every step declares which kind it is:
//
//   required: true   The check itself. It cannot be switched off by anybody,
//                    and `requiredWhy` says who would be harmed if it were.
//                    Identity, consent, and the affordability read are here.
//                    A lender may change how these are PRESENTED; they cannot
//                    remove them and still be on this platform.
//
//   required: false  Ceremony and routing. Whether the customer picks the
//                    product or the system does. Whether Ratiba is asked for
//                    now or at disbursement. Whether risk sees it before or
//                    after. Real choices with real consequences, and none of
//                    them change what was verified.
//
// ── THE THIRD MODE ───────────────────────────────────────────────────────────
// "auto" is not "off". An automatic step still runs, is still recorded, and is
// still explainable to the customer afterwards — the customer just is not asked
// to do anything. Limit allocation is the clearest case: the arithmetic happens
// either way, and the only question is whether a human is shown a slider. A
// system that conflated auto with off would let a lender quietly stop scoring
// people while the screen still said they had been scored.
// ─────────────────────────────────────────────────────────────────────────────

/** on = the customer is asked · auto = the system does it · off = skipped. */
export type StepMode = "on" | "auto" | "off";

export type StepId =
  | "account"
  | "kyc-id"
  | "kyc-registry"
  | "kyc-face"
  | "statement"
  | "limit"
  | "product"
  | "schedule"
  | "consent"
  | "ratiba"
  | "risk";

export interface StepDef {
  id: StepId;
  /** What the customer sees at the top of the screen. */
  title: string;
  /** One line, in the customer's language, about what is about to happen. */
  blurb: string;
  /**
   * How much canvas this step wants on a large screen.
   *
   * "narrow" is the default and is right for anything that is a FORM: a 980px
   * text field is not more usable than a 560px one, it is just harder to read
   * across. "wide" is for steps that are genuinely a workspace — the schedule
   * editor has ten rows to reshape and a running total to watch, and squeezing
   * that into a phone column on a laptop wastes the one advantage the laptop
   * has.
   */
  canvas?: "narrow" | "wide";
  /** Who is holding the phone when this runs. */
  actor: "customer" | "system" | "staff";
  /** The modes a lender may actually choose between for this step. */
  allowed: StepMode[];
  /** What Micromart gets on day one. */
  defaultMode: StepMode;
  /** True when switching it off is not on the table, at any price. */
  required: boolean;
  /** Who is harmed if this were removed. Shown in the lender's own config screen,
   *  because a disabled toggle with no explanation reads as a bug. */
  requiredWhy?: string;
}

export const JOURNEY: StepDef[] = [
  {
    id: "account",
    title: "Create your account",
    blurb: "Your National ID, and your permission for us to check it.",
    actor: "customer",
    allowed: ["on"],
    defaultMode: "on",
    required: true,
    requiredWhy:
      "Lending to an unidentified person is not a product decision, it is a licensing one. There is no configuration in which this is skipped.",
  },
  {
    id: "kyc-id",
    title: "Scan your ID",
    blurb: "Lay it flat and fill the frame. We will tell you when it looks right.",
    actor: "customer",
    allowed: ["on"],
    defaultMode: "on",
    required: true,
    requiredWhy: "The document is what the registry check and the face match are both compared against.",
  },
  {
    id: "kyc-registry",
    title: "Checking the registry",
    blurb: "We are confirming that the number on the card belongs to the name on the card.",
    actor: "system",
    allowed: ["auto"],
    defaultMode: "auto",
    required: true,
    requiredWhy:
      "This is the fraud gate. A borrowed or altered ID dies here, and it is the one check a lender can never be talked out of.",
  },
  {
    id: "kyc-face",
    title: "Take a selfie",
    blurb: "One photo, front on, eyes open — matched against the portrait on your ID.",
    actor: "customer",
    allowed: ["on"],
    defaultMode: "on",
    required: true,
    requiredWhy: "Without it, the ID proves a document exists, not that you are holding your own.",
  },
  {
    id: "statement",
    title: "Your M-PESA statement",
    blurb: "Six months, read in about a minute, and turned into an affordability score out of 900.",
    actor: "customer",
    allowed: ["on"],
    defaultMode: "on",
    required: true,
    requiredWhy:
      "The limit has to come from evidence. Removing this leaves the number resting on nothing, which is the thing regulators ask about first.",
  },
  {
    id: "limit",
    title: "Your starting limit",
    blurb: "Set from your score. It moves every time you repay.",
    actor: "system",
    allowed: ["auto", "on"],
    defaultMode: "auto",
    required: false,
  },
  {
    id: "product",
    title: "Choose your product",
    blurb: "Micro Eazy or Micro Eazy Monthly — compare the rate and the cycle.",
    actor: "customer",
    allowed: ["on", "auto"],
    defaultMode: "on",
    required: false,
  },
  {
    id: "schedule",
    title: "Shape your repayments",
    canvas: "wide",
    blurb: "Move the amounts between weeks until the plan fits how you actually earn.",
    actor: "customer",
    allowed: ["on", "auto"],
    defaultMode: "on",
    required: false,
  },
  {
    id: "consent",
    title: "Your loan agreement",
    blurb: "The amount, the schedule, and every charge — before you agree to any of it.",
    actor: "customer",
    allowed: ["on"],
    defaultMode: "on",
    required: true,
    requiredWhy:
      "A customer who has not seen the charges has not agreed to them. This is the step that makes every other one defensible.",
  },
  {
    id: "ratiba",
    title: "Set up auto-repay",
    blurb: "M-PESA Ratiba pays each installment on its due date, so you do not have to remember.",
    actor: "customer",
    allowed: ["on", "off"],
    defaultMode: "on",
    required: false,
  },
  {
    id: "risk",
    title: "Final review",
    blurb: "A last look before the money moves.",
    actor: "staff",
    allowed: ["on", "auto", "off"],
    defaultMode: "on",
    required: false,
  },
];

/** A lender's overrides. Absent ids take the step's own default. */
export type JourneyConfig = Partial<Record<StepId, StepMode>>;

export function modeFor(step: StepDef, config: JourneyConfig): StepMode {
  const wanted = config[step.id];
  if (!wanted) return step.defaultMode;
  // A configuration that asks for something the step does not offer is a bug in
  // whoever wrote the config, and the safe reading of a bad config is always the
  // step's own default — never the most permissive option in it.
  if (!step.allowed.includes(wanted)) return step.defaultMode;
  if (step.required && wanted === "off") return step.defaultMode;
  return wanted;
}

/** The steps this borrower will actually be shown, in order. */
export function customerSteps(config: JourneyConfig = {}): StepDef[] {
  return JOURNEY.filter((s) => {
    const m = modeFor(s, config);
    return m === "on" && s.actor === "customer";
  });
}

/** Everything that runs, including the parts nobody is asked about. Used by the
 *  lender's configuration screen and by the "what happened to me" explainer the
 *  customer can open afterwards. */
export function activeSteps(config: JourneyConfig = {}): { step: StepDef; mode: StepMode }[] {
  return JOURNEY.map((step) => ({ step, mode: modeFor(step, config) })).filter((x) => x.mode !== "off");
}
