// ─────────────────────────────────────────────────────────────────────────────
// ARTWORK — a picture, or a composition that is not pretending to be one.
//
// There is no empty state in this component, on purpose. A slot with no asset
// draws a generated composition: a brand gradient, ripple arcs, a soft highlight
// and a fine rule grid, all derived deterministically from the slot's id so the
// same slot looks the same on every device and every reload.
//
// The point is not to hide that the photograph is missing. It is that a screen
// with a considered abstract tile is a FINISHED screen, and a screen with a grey
// rectangle and a mountain glyph is a broken one — and the person being asked
// for KSh 850 up front can tell the difference in about a second. Ship finished
// screens; land the photography into them later without touching a layout.
//
// Everything is drawn from tokens, so a composition is correct in both themes
// without a second palette and without a single hex at the call site.
// ─────────────────────────────────────────────────────────────────────────────
import { ACCENT_STOPS, ART, RATIO_CLASS, type Ratio } from "../../lib/media/assets";

/** A tiny, stable string hash. Not cryptographic — it only has to be the same
 *  number tomorrow as it is today, so a tile does not reshuffle on reload. */
function seed(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

export function Artwork({
  slot,
  className = "",
  ratio: ratioOverride,
  rounded = "rounded-2xl",
  motif: motifOverride,
}: {
  slot: string;
  className?: string;
  ratio?: Ratio;
  rounded?: string;
  /**
   * Force which composition is drawn (0 rings · 1 bars · 2 flows).
   *
   * The hash is fine for a tile seen alone and NOT fine for a row: two of the
   * three "Advice and tips" slots hashed to the same motif and the row read as
   * one graphic repeated. Where tiles are seen together, the caller assigns —
   * determinism is only useful if it also looks deliberate.
   */
  motif?: 0 | 1 | 2;
}) {
  const art = ART[slot];
  if (!art) {
    // A typo'd slot should be loud in development and invisible to a customer,
    // never a crash mid-onboarding.
    if (import.meta.env.DEV) console.warn(`[Artwork] unknown slot "${slot}"`);
    return null;
  }

  const ratio = ratioOverride ?? art.ratio;
  const [from, to] = ACCENT_STOPS[art.accent];

  if (art.src) {
    return (
      <img
        src={art.src}
        alt={art.alt}
        loading="lazy"
        decoding="async"
        className={`${RATIO_CLASS[ratio]} ${rounded} w-full object-cover ${className}`}
      />
    );
  }

  const n = seed(art.id);
  const angle = 130 + (n % 60);
  // Where the ripples originate. Kept inside the lower-left quadrant so a row of
  // tiles has a common light direction rather than looking randomly assembled.
  const ox = 6 + (n % 22);
  const oy = 78 + ((n >> 3) % 18);
  const tilt = -18 + ((n >> 5) % 36);
  /** Which composition this slot draws. Three, so a row of tiles varies without
   *  any of them looking like it came from a different product. */
  const motif = motifOverride ?? (n % 3);

  return (
    <div
      role="img"
      aria-label={art.alt}
      className={`${RATIO_CLASS[ratio]} ${rounded} relative w-full overflow-hidden ${className}`}
      style={{ background: `linear-gradient(${angle}deg, ${from} 0%, ${to} 100%)` }}
    >
      {/* `slice`, never `none`. Stretching the viewBox to the frame turns every
          circle into an ellipse and the whole thing reads as a wallpaper glitch;
          slicing crops instead, so the geometry stays true at any aspect. */}
      <svg
        viewBox="0 0 100 100"
        preserveAspectRatio="xMidYMid slice"
        aria-hidden
        className="absolute inset-0 h-full w-full"
      >
        <defs>
          <radialGradient id={`hl-${art.id}`} cx="76%" cy="14%" r="66%">
            <stop offset="0%" stopColor="rgb(255 255 255 / 0.42)" />
            <stop offset="100%" stopColor="rgb(255 255 255 / 0)" />
          </radialGradient>
        </defs>

        {/* The ledger grid. Sparse and faint — it is what makes the tile read as
            financial rather than merely decorative. */}
        <g stroke="rgb(255 255 255 / 0.13)" strokeWidth="0.4">
          {[20, 40, 60, 80].map((y) => (
            <line key={`h${y}`} x1="0" y1={y} x2="100" y2={y} />
          ))}
        </g>

        {/* One of three motifs, chosen by the slot's own hash. Variety across a
            row, determinism within a slot — and each one is a real composition
            with a subject, not a texture. A flat gradient with a hint of
            something behind it is precisely what "placeholder" looks like, and
            the whole point of this component is that it never looks like one. */}
        {motif === 0 && (
          <g transform={`rotate(${tilt / 3} ${ox} ${oy})`}>
            <circle cx={ox} cy={oy} r="46" fill="rgb(255 255 255 / 0.10)" />
            <g fill="none" stroke="rgb(255 255 255 / 0.55)" strokeWidth="1">
              <circle cx={ox} cy={oy} r="20" />
              <circle cx={ox} cy={oy} r="34" strokeOpacity="0.62" />
              <circle cx={ox} cy={oy} r="50" strokeOpacity="0.4" />
              <circle cx={ox} cy={oy} r="68" strokeOpacity="0.22" />
            </g>
            <circle cx={ox} cy={oy} r="6.5" fill="rgb(255 255 255 / 0.85)" />
          </g>
        )}

        {motif === 1 && (
          <g>
            {/* A rising series. Five bars, last one brightest — the shape of a
                limit that grows as you repay, which is the product's whole
                promise stated without a word. */}
            {[0, 1, 2, 3, 4].map((i) => {
              const h = 16 + i * 12 + ((n >> (i + 2)) % 7);
              return (
                <rect
                  key={i}
                  x={14 + i * 15}
                  y={88 - h}
                  width="9"
                  height={h}
                  rx="4.5"
                  fill={`rgb(255 255 255 / ${0.2 + i * 0.13})`}
                />
              );
            })}
            <path
              d="M14 60 Q34 46 48 40 T92 16"
              fill="none"
              stroke="rgb(255 255 255 / 0.75)"
              strokeWidth="1.4"
              strokeLinecap="round"
            />
            <circle cx="92" cy="16" r="3.6" fill="rgb(255 255 255 / 0.95)" />
          </g>
        )}

        {motif === 2 && (
          <g>
            {/* Two stacked flows — money out against money in. */}
            <path
              d="M0 62 C18 48 30 72 48 58 S78 40 100 52 L100 100 L0 100 Z"
              fill="rgb(255 255 255 / 0.13)"
            />
            <path
              d="M0 74 C22 62 34 86 54 72 S82 58 100 66 L100 100 L0 100 Z"
              fill="rgb(255 255 255 / 0.2)"
            />
            <path
              d="M0 62 C18 48 30 72 48 58 S78 40 100 52"
              fill="none"
              stroke="rgb(255 255 255 / 0.72)"
              strokeWidth="1.3"
              strokeLinecap="round"
            />
            <g fill="rgb(255 255 255 / 0.9)">
              <circle cx="48" cy="58" r="3.2" />
              <circle cx="100" cy="52" r="3.2" />
            </g>
          </g>
        )}

        <rect width="100" height="100" fill={`url(#hl-${art.id})`} />
      </svg>

      {/* A weighted floor, so a caption or a play button laid over the bottom of
          this tile is legible without the tile having to know about it. */}
      <span
        aria-hidden
        className="absolute inset-x-0 bottom-0 h-1/2"
        style={{ background: "linear-gradient(to top, rgb(4 6 14 / 0.42), transparent)" }}
      />
    </div>
  );
}

export default Artwork;
