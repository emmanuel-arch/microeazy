// ─────────────────────────────────────────────────────────────────────────────
// FILM — the same poster-facade the lending console uses, in the borrower app.
//
// Two things it will not do:
//
//   1. MOUNT AN IFRAME NOBODY ASKED FOR. A YouTube embed is ~1.2 MB of
//      third-party JavaScript and a cookie write. On a Kenyan prepaid bundle
//      that is real money, spent on a video most people will not play. It stays
//      a poster until pressed. youtube-nocookie.com, so nothing is written
//      until playback actually begins.
//
//   2. SEND ANYBODY TO YOUTUBE. No target="_blank". A customer halfway through
//      verifying their identity who lands in the YouTube app has left, and the
//      KYC session they abandoned already holds a photograph of their ID.
//
// When the film has not been cut yet, the frame is still a designed object —
// the slot's own composition with a play control and an honest "coming" chip —
// rather than a black rectangle. Same rule as Artwork: ship finished screens.
// ─────────────────────────────────────────────────────────────────────────────
import { useState } from "react";
import { Play, Clapperboard } from "lucide-react";
import { ACCENT_STOPS, FILMS } from "../../lib/media/assets";

export function Film({ slot, className = "" }: { slot: string; className?: string }) {
  const [playing, setPlaying] = useState(false);
  const film = FILMS[slot];

  if (!film) {
    if (import.meta.env.DEV) console.warn(`[Film] unknown slot "${slot}"`);
    return null;
  }

  const [from, to] = ACCENT_STOPS[film.accent];
  const ready = Boolean(film.youTubeId);

  if (playing && film.youTubeId) {
    return (
      <div className={`relative aspect-video w-full overflow-hidden rounded-2xl bg-black ${className}`}>
        <iframe
          className="absolute inset-0 h-full w-full"
          src={`https://www.youtube-nocookie.com/embed/${film.youTubeId}?autoplay=1&rel=0&modestbranding=1&playsinline=1`}
          title={film.title}
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
          referrerPolicy="strict-origin-when-cross-origin"
          allowFullScreen
        />
      </div>
    );
  }

  return (
    <button
      type="button"
      disabled={!ready}
      onClick={() => setPlaying(true)}
      aria-label={ready ? `Play: ${film.title}` : `${film.title} — not available yet`}
      className={`group relative aspect-video w-full overflow-hidden rounded-2xl text-left disabled:cursor-default ${className}`}
      style={{ background: `linear-gradient(148deg, ${from} 0%, ${to} 100%)` }}
    >
      {/* THE POSTER IS OURS, ALWAYS.
          This used to pull YouTube's own thumbnail from i.ytimg.com, and the
          screenshot said everything: the auto-generated frame was a stock photo
          of a handset with ANOTHER CHANNEL'S WATERMARK burned across it —
          "albastuz3d.net" — sitting inside a card that is asking a customer to
          trust us with KSh 850 and a photograph of their ID. One foreign
          watermark undoes a whole screen of careful work.

          So the frame is drawn here, from the brand. It is also faster (no
          third-party image request, nothing to leak a referrer to) and it does
          not change when somebody re-uploads the video. */}
      <svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid slice" aria-hidden className="absolute inset-0 h-full w-full">
        <defs>
          <radialGradient id={`fhl-${film.id}`} cx="74%" cy="16%" r="64%">
            <stop offset="0%" stopColor="rgb(255 255 255 / 0.4)" />
            <stop offset="100%" stopColor="rgb(255 255 255 / 0)" />
          </radialGradient>
        </defs>
        <g stroke="rgb(255 255 255 / 0.13)" strokeWidth="0.4">
          {[20, 40, 60, 80].map((y) => (
            <line key={y} x1="0" y1={y} x2="100" y2={y} />
          ))}
        </g>
        <g fill="none" stroke="rgb(255 255 255 / 0.5)" strokeWidth="1">
          <circle cx="14" cy="86" r="22" />
          <circle cx="14" cy="86" r="38" strokeOpacity="0.6" />
          <circle cx="14" cy="86" r="56" strokeOpacity="0.38" />
          <circle cx="14" cy="86" r="76" strokeOpacity="0.2" />
        </g>
        <rect width="100" height="100" fill={`url(#fhl-${film.id})`} />
      </svg>

      <span
        aria-hidden
        className="absolute inset-0"
        style={{ background: "linear-gradient(to top, rgb(4 6 14 / 0.72), rgb(4 6 14 / 0.06) 55%, transparent)" }}
      />

      <span className="absolute inset-0 grid place-items-center">
        <span
          className={`grid h-14 w-14 place-items-center rounded-full shadow-lg transition ${ready ? "group-hover:scale-110" : ""}`}
          style={{ background: ready ? "rgb(255 255 255 / 0.95)" : "rgb(255 255 255 / 0.22)" }}
        >
          {ready ? (
            <Play className="h-6 w-6 translate-x-[2px] fill-current" style={{ color: "var(--navy)" }} />
          ) : (
            <Clapperboard className="h-6 w-6 text-white" strokeWidth={1.8} />
          )}
        </span>
      </span>

      <span className="absolute inset-x-0 bottom-0 p-3.5">
        <span className="block text-[13.5px] font-semibold leading-tight text-white">{film.title}</span>
        <span className="mt-0.5 block text-[11.5px] leading-snug text-white/70">
          {ready ? film.blurb : "Being filmed — the steps are written out below."}
        </span>
      </span>
    </button>
  );
}

export default Film;
