// ─────────────────────────────────────────────────────────────────────────────
// THE ART MANIFEST — every image and film this app wants, in one list.
//
// The rule this file exists to serve: a screen missing its artwork must still
// look finished. Not "grey box with a mountain icon" finished — actually
// finished, the way the Safaricom mini-apps are finished, so that somebody being
// asked for KSh 850 in upfront charges never once wonders whether this is a
// scam.
//
// So `<Artwork>` never renders an empty state. When `src` is null it draws a
// composition instead — generated deterministically from the slot name, tinted
// by the accent below — which is a real graphic, not a stand-in for one. The
// screen ships. The art lands later and the composition is replaced by one line
// changing here.
//
// WHY A MANIFEST AND NOT JUST NULLS AT THE CALL SITE: because a placeholder that
// looks finished is a placeholder nobody remembers to replace. This file is the
// list of what is still owed, and it is the brief for the person drawing it —
// each slot carries what it is FOR, which is the part an illustrator actually
// needs and the part that gets lost in a Slack thread.
// ─────────────────────────────────────────────────────────────────────────────

export type Ratio = "square" | "wide" | "card" | "tall";

export interface ArtSlot {
  /** Stable id. Also the seed for the generated composition, so a slot's look
   *  does not change between reloads or between one device and another. */
  id: string;
  /** What the picture has to communicate. This is the illustrator's brief. */
  brief: string;
  ratio: Ratio;
  /** Accent the composition is tinted with. Named tokens only. */
  accent: "navy" | "lime" | "violet" | "amber" | "sky";
  /** The real asset, once it exists. Until then the composition stands in. */
  src: string | null;
  /** Alt text. Required now, not later — it is the same sentence either way. */
  alt: string;
}

export const ART: Record<string, ArtSlot> = {
  "kyc-id-front": {
    id: "kyc-id-front",
    brief:
      "A Kenyan national ID lying flat inside a capture frame, shot from above, corners aligned to the guides. Reassuring and procedural — this is the moment somebody hands over their identity.",
    ratio: "wide",
    accent: "navy",
    src: null,
    alt: "An ID card positioned inside the capture frame",
  },
  "kyc-face": {
    id: "kyc-face",
    brief:
      "A person holding a phone at arm's length taking a selfie in ordinary daylight. Ordinary clothes, ordinary room — not a studio portrait. It has to look like something you can do standing in a shop.",
    ratio: "wide",
    accent: "violet",
    src: null,
    alt: "Taking a selfie for the face match",
  },
  "statement-howto": {
    id: "statement-howto",
    brief:
      "A handset showing the *334# menu mid-flow, thumb on the keypad. Pairs with the walkthrough film.",
    ratio: "wide",
    accent: "lime",
    src: null,
    alt: "Requesting an M-PESA statement on a handset",
  },
  "tip-credit-score": {
    id: "tip-credit-score",
    brief:
      "A market trader with a tablet or phone, mid-transaction, smiling. Warm, real, Kenyan — the Safaricom 'Advice and tips' register exactly.",
    ratio: "card",
    accent: "lime",
    src: null,
    alt: "A trader checking their phone",
  },
  "tip-what-moves-limit": {
    id: "tip-what-moves-limit",
    brief:
      "Someone walking past a shopfront looking at their phone, soft daylight. Same register as the tile beside it so the row reads as a set.",
    ratio: "card",
    accent: "sky",
    src: null,
    alt: "Checking a loan limit on the move",
  },
  "tip-charges": {
    id: "tip-charges",
    brief: "A hand counting notes beside a phone showing a repayment schedule. About money being understood, not owed.",
    ratio: "card",
    accent: "amber",
    src: null,
    alt: "Understanding the charges on a loan",
  },

  // ── Screens still to build. Listed now so the whole set can be commissioned
  //    in one brief rather than six, and so the shoot has one consistent cast,
  //    wardrobe and light. A photo library assembled a tile at a time is how an
  //    app ends up looking like three apps.
  "ladder-climb": {
    id: "ladder-climb",
    brief:
      "A small shop that has visibly grown — fuller shelves than it started with, owner standing in it. This illustrates a limit that climbs with repayment, so it must read as EARNED rather than granted.",
    ratio: "wide",
    accent: "lime",
    src: null,
    alt: "A business that has grown with its credit limit",
  },
  "score-explained": {
    id: "score-explained",
    brief:
      "Someone at a table with a phone and a notebook, working something out — concentration, not worry. Pairs with the 'why this decision' screen, whose whole job is to make a score feel legible instead of imposed.",
    ratio: "wide",
    accent: "navy",
    src: null,
    alt: "Working out what moved a credit score",
  },
  "exposure-interchange": {
    id: "exposure-interchange",
    brief:
      "Deliberately abstract, NOT a person: this screen is about what other lenders can see. A photograph of somebody here would imply we are showing their data to strangers, which is the opposite of what the screen says. Prefer a structural image — a ledger, a lock, a network.",
    ratio: "wide",
    accent: "violet",
    src: null,
    alt: "What the credit system can see",
  },
  "repay-done": {
    id: "repay-done",
    brief:
      "Relief. Somebody looking at their phone having just paid — the small unclenching that is the actual emotional payload of a repayment confirmation.",
    ratio: "wide",
    accent: "lime",
    src: null,
    alt: "A repayment confirmed",
  },
  "ratiba-setup": {
    id: "ratiba-setup",
    brief:
      "A phone showing an M-PESA confirmation on a market stall counter, owner working in the background — not watching the phone. The point of auto-repay is that you stop thinking about it.",
    ratio: "wide",
    accent: "sky",
    src: null,
    alt: "Setting up automatic repayment",
  },
  "empty-no-loans": {
    id: "empty-no-loans",
    brief:
      "Open and unhurried — a clean counter, morning light, nothing owed. Empty states are where an app either encourages or accuses, and this one has to be the former.",
    ratio: "card",
    accent: "sky",
    src: null,
    alt: "No active loans",
  },
};

/** The films. Same idea: a poster until somebody presses play, and a designed
 *  frame rather than a black rectangle when there is no poster yet. */
export interface FilmSlot {
  id: string;
  /** A YouTube id, or null while the film is still being cut. */
  youTubeId: string | null;
  title: string;
  blurb: string;
  accent: ArtSlot["accent"];
}

export const FILMS: Record<string, FilmSlot> = {
  "statement-walkthrough": {
    id: "statement-walkthrough",
    // The same film the lending console plays on /console/crunch. One asset,
    // both realms — if the USSD menu changes, it changes in one place.
    youTubeId: "Q2Dc03GKGnM",
    title: "Getting your M-PESA statement",
    blurb: "Ninety seconds, on *334#. It is free.",
    accent: "lime",
  },
  "how-repayment-works": {
    id: "how-repayment-works",
    youTubeId: null,
    title: "How repayment works",
    blurb: "Ratiba, due dates, and what happens if you are late.",
    accent: "sky",
  },
};

export const RATIO_CLASS: Record<Ratio, string> = {
  square: "aspect-square",
  wide: "aspect-video",
  card: "aspect-[4/3]",
  tall: "aspect-[3/4]",
};

/** Accent → the two stops its composition is built from. Tokens, so both themes
 *  are handled without a second table. */
export const ACCENT_STOPS: Record<ArtSlot["accent"], [string, string]> = {
  navy: ["var(--navy)", "#2f6bff"],
  lime: ["var(--green)", "var(--lime)"],
  violet: ["#6d43d8", "#a78bfa"],
  amber: ["#c2740a", "#f0a92b"],
  sky: ["#0e6ba8", "#5b8cff"],
};
