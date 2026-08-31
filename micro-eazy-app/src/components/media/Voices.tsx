// ─────────────────────────────────────────────────────────────────────────────
// THE VOICES PANEL — four photographs, stacked, shuffling.
//
// The mechanic is the reference library's testimonial stack, kept because it is
// the right one for four pictures that have to share a slot: they sit as a
// scattered deck rather than a slideshow, so you can SEE that there are more
// than one, and the top card lifts and drops as it changes rather than sliding.
// A slide reads as a carousel and a carousel reads as an advertisement; a deck
// reads as a stack of photographs somebody put down on the table.
//
// ── WHAT IS DIFFERENT FROM THE REFERENCE, AND WHY ────────────────────────────
//   · THE ROTATION IS SEEDED, NOT RANDOM. `Math.random()` in a render body gives
//     a different angle every time React re-renders — the deck visibly reshuffles
//     when a parent updates for an unrelated reason. Seeded off the index, the
//     scatter is stable for the life of the app.
//   · AUTOPLAY STOPS WHEN TOUCHED. Somebody who has pressed an arrow is reading
//     that one, and a panel that advances out from under them is worse than one
//     that never moved. It also stops while the tab is hidden, which is what
//     keeps a backgrounded phone from running a timer for an hour.
//   · IT DEGRADES TO ONE STILL FRAME. Under prefers-reduced-motion nothing
//     animates and nothing auto-advances; the arrows still work. That is a real
//     setting on a real proportion of handsets, not a checkbox.
//
// The copy arrives word by word out of focus — the one effect on this screen —
// and it is a CSS animation keyed on the active index rather than a per-word
// spring, so a mid-range Android is animating opacity and filter and nothing
// else.
// ─────────────────────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { ArrowLeft, ArrowRight } from "lucide-react";
import { VOICES } from "../../lib/media/voices";

/**
 * A stable scatter. The same card is at the same angle tomorrow as today.
 *
 * ── WHY THE ANGLE IS SMALL, AND WHY THAT IS GEOMETRY RATHER THAN TASTE ──────
 * A rotated rectangle is WIDER than the box it came from: w·cos θ + h·sin θ. At
 * ±8° a 358×447 card measures 416px across, which on a 390px handset is 26px of
 * horizontal page scroll — and the deck is inside a column that is itself inside
 * the page, so the whole screen shifts and the theme toggle walks off the right
 * edge. It is invisible on a laptop and it is the first thing you see on a
 * phone, which is the design target.
 *
 * So the deck sits in a padded box, the cards are inset inside it, and the angle
 * and the scale together are chosen so the widest rotated card still fits its
 * own container. Change either number and check a 390px viewport.
 */
function angleFor(i: number): number {
  const n = Math.sin(i + 1) * 10000;
  return Math.floor((n - Math.floor(n)) * 13) - 6;
}

function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => setReduced(mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);
  return reduced;
}

export function Voices({ className = "" }: { className?: string }) {
  const [active, setActive] = useState(0);
  const [touched, setTouched] = useState(false);
  // Which files failed to load. A missing plate falls back to the brand
  // gradient on its own rather than leaving a broken-image glyph in a card that
  // is asking somebody to trust us with their national ID.
  const [broken, setBroken] = useState<Set<string>>(() => new Set());
  const reduced = usePrefersReducedMotion();

  const go = useCallback((dir: 1 | -1) => {
    setTouched(true);
    setActive((i) => (i + dir + VOICES.length) % VOICES.length);
  }, []);

  useEffect(() => {
    if (touched || reduced || VOICES.length < 2) return;
    const t = setInterval(() => {
      // Not while nobody is looking. A phone in a pocket should not be running
      // a five-second timer and repainting four layers for an hour.
      if (document.visibilityState !== "visible") return;
      setActive((i) => (i + 1) % VOICES.length);
    }, 5200);
    return () => clearInterval(t);
  }, [touched, reduced]);

  const voice = VOICES[active];

  return (
    <section className={`relative ${className}`} aria-roledescription="carousel" aria-label="What Micro Eazy is for">
      {/* ── The deck ─────────────────────────────────────────────────────── */}
      <div className="relative aspect-[4/5] w-full sm:aspect-[5/4] lg:aspect-[4/5]">
        {VOICES.map((v, i) => {
          const on = i === active;
          const angle = angleFor(i);
          return (
            <figure
              key={v.id}
              aria-hidden={!on}
              className="absolute inset-3 m-0 origin-bottom overflow-hidden rounded-[26px] transition-all duration-500 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none"
              style={{
                background: "linear-gradient(150deg, var(--navy) 0%, var(--navy-deep) 46%, var(--green) 190%)",
                boxShadow: "var(--shadow-lift)",
                // Not zero. The cards underneath were invisible at rest, which
                // made this a slideshow that happened to rotate on the way out —
                // the whole reason to stack photographs is that you can see
                // there are more than one before anything moves.
                opacity: on ? 1 : 0.45,
                transform: on ? "rotate(0deg) scale(1)" : `rotate(${angle}deg) scale(0.9)`,
                zIndex: on ? 20 : VOICES.length - i,
              }}
            >
              {!broken.has(v.id) && (
                <img
                  src={v.file}
                  alt={v.alt}
                  draggable={false}
                  // EAGER FOR THE ONE ON TOP AND THE ONE BEHIND IT. All four
                  // plates occupy the same box in the viewport, so lazy-loading
                  // buys nothing here — the browser fetches them regardless —
                  // and it costs the one thing that matters: on a slow bundle a
                  // deferred plate can still be in flight when the deck advances
                  // onto it, and the card shows its fallback gradient for a beat
                  // instead of a photograph. Preloading the NEXT one is what
                  // makes the shuffle look like a shuffle.
                  loading={i === active || i === (active + 1) % VOICES.length ? "eager" : "lazy"}
                  decoding="async"
                  onError={() =>
                    setBroken((prev) => {
                      const next = new Set(prev);
                      next.add(v.id);
                      return next;
                    })
                  }
                  className="h-full w-full select-none object-cover object-center"
                />
              )}
              {/* The scrim goes down whether or not the photograph did, so the
                  caption sits at the same contrast either way and the card does
                  not visibly change weight when a plate is added. */}
              <span
                aria-hidden
                className="absolute inset-0"
                style={{ background: "linear-gradient(to top, rgb(0 4 58 / 0.78) 0%, rgb(0 4 58 / 0.12) 46%, transparent 70%)" }}
              />
              <figcaption className="absolute inset-x-0 bottom-0 p-4">
                <span className="inline-flex items-center gap-1.5 rounded-full bg-white/12 px-2.5 py-1 text-[11px] font-medium text-white/85 backdrop-blur">
                  <span aria-hidden className="h-1.5 w-1.5 rounded-full" style={{ background: "var(--lime)" }} />
                  {v.caption}
                </span>
              </figcaption>
            </figure>
          );
        })}
      </div>

      {/* ── The copy ─────────────────────────────────────────────────────────
          Keyed on the active index so React remounts the block and the CSS
          animation restarts. Without the key it plays once and every later
          plate's copy simply appears. */}
      <div key={active} className="mt-5">
        <h2 className="text-[19px] font-bold leading-[1.25] tracking-[-0.02em] text-ink">
          {voice.title.split(" ").map((word, i) => (
            <span
              key={`${word}-${i}`}
              className="voice-word inline-block"
              style={{ animationDelay: `${i * 0.045}s` }}
            >
              {word}&nbsp;
            </span>
          ))}
        </h2>
        <p className="voice-word mt-2 text-[13.5px] leading-relaxed text-ink-soft" style={{ animationDelay: "0.28s" }}>
          {voice.body}
        </p>
      </div>

      {/* ── The controls ─────────────────────────────────────────────────── */}
      <div className="mt-4 flex items-center gap-3">
        <button
          type="button"
          onClick={() => go(-1)}
          aria-label="Previous"
          className="grid h-8 w-8 place-items-center rounded-full border border-line text-ink-soft transition-colors hover:bg-surface-sunk hover:text-ink"
        >
          <ArrowLeft className="h-4 w-4" strokeWidth={2.2} />
        </button>
        <button
          type="button"
          onClick={() => go(1)}
          aria-label="Next"
          className="grid h-8 w-8 place-items-center rounded-full border border-line text-ink-soft transition-colors hover:bg-surface-sunk hover:text-ink"
        >
          <ArrowRight className="h-4 w-4" strokeWidth={2.2} />
        </button>

        {/* Dots as BUTTONS, not decoration: four plates is few enough that
            jumping straight to one is faster than pressing next three times. */}
        <span className="ml-1 flex items-center gap-1.5">
          {VOICES.map((v, i) => (
            <button
              key={v.id}
              type="button"
              onClick={() => {
                setTouched(true);
                setActive(i);
              }}
              aria-label={v.caption}
              aria-current={i === active}
              className="h-1.5 rounded-full transition-all duration-300"
              style={{
                width: i === active ? "1.35rem" : "0.375rem",
                background: i === active ? "var(--green-ink)" : "var(--line-strong)",
              }}
            />
          ))}
        </span>
      </div>
    </section>
  );
}

export default Voices;
