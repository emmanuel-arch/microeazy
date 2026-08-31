// ─────────────────────────────────────────────────────────────────────────────
// THE GLOW NAV — the same idea as the reference menu bar, moved to where a
// borrower's thumb actually is.
//
// The reference was a horizontal desktop bar whose glow and 3-D card flip were
// driven by `whileHover`. Two problems on a phone: there is no hover, so the
// entire effect never fires; and a top-of-screen horizontal nav is the one place
// a one-handed user cannot reach. The technique survives, the placement does not.
//
//   · Under `lg` it is a BOTTOM TAB BAR, inside the safe-area inset, five items
//     wide — the shape every Kenyan fintech app has, because it is the shape a
//     thumb can hit while holding a matatu rail.
//   · At `lg` and up it becomes a LEFT RAIL with labels, which is where the
//     reference's proportions actually belong.
//
// And the glow follows the ACTIVE ROUTE rather than the cursor, so a touch user
// gets the effect permanently on the tab they are on. Pointer devices still get
// the hover preview and the flip on top of that — `@media (hover: hover)`, so a
// phone is never asked to render an interaction it cannot express.
// ─────────────────────────────────────────────────────────────────────────────
import { motion } from "framer-motion";
import { NavLink } from "react-router-dom";
import { Home, Wallet, Gauge, FileText, User, type LucideIcon } from "lucide-react";

export interface NavItem {
  icon: LucideIcon;
  label: string;
  to: string;
  /** The radial wash behind an active item. Tinted per destination so the app
   *  has a sense of place — money is green, the score is amber, you are navy. */
  glow: string;
  tint: string;
}

export const NAV_ITEMS: NavItem[] = [
  { icon: Home, label: "Home", to: "/", glow: "rgba(47,107,255,0.42)", tint: "#5b8cff" },
  { icon: Wallet, label: "Repay", to: "/repay", glow: "rgba(37,149,12,0.42)", tint: "#5ec22a" },
  { icon: Gauge, label: "Score", to: "/score", glow: "rgba(245,158,11,0.42)", tint: "#f0a92b" },
  { icon: FileText, label: "Loans", to: "/loans", glow: "rgba(139,92,246,0.42)", tint: "#a78bfa" },
  { icon: User, label: "You", to: "/you", glow: "rgba(236,72,153,0.42)", tint: "#f472b6" },
];

const spring = { type: "spring" as const, stiffness: 380, damping: 32 };

function Item({ item, rail }: { item: NavItem; rail: boolean }) {
  const Icon = item.icon;
  return (
    <NavLink
      to={item.to}
      end={item.to === "/"}
      className={({ isActive }) =>
        `group relative flex ${rail ? "w-full flex-row items-center gap-3 rounded-2xl px-3.5 py-3" : "flex-1 flex-col items-center gap-1 rounded-2xl px-1 py-2"} ` +
        `outline-none transition-colors focus-visible:ring-2 focus-visible:ring-[var(--lime)] ` +
        (isActive ? "text-ink" : "text-ink-faint hover:text-ink-soft")
      }
    >
      {({ isActive }) => (
        <>
          {/* The wash. A layout-animated element shared across the whole list, so
              moving between tabs SLIDES the glow rather than cross-fading two of
              them — the detail that makes it feel like one object. */}
          {isActive && (
            <motion.span
              layoutId={rail ? "glow-rail" : "glow-tabs"}
              transition={spring}
              aria-hidden
              className="absolute inset-0 -z-10 rounded-2xl"
              style={{
                background: `radial-gradient(circle at 50% ${rail ? "50%" : "30%"}, ${item.glow} 0%, transparent 72%)`,
              }}
            />
          )}

          {/* On a pointer device only, the same wash previews on hover. A phone
              never renders this: `hover:` compiles to a media query that a touch
              screen does not match. */}
          <span
            aria-hidden
            className="pointer-events-none absolute inset-0 -z-10 rounded-2xl opacity-0 transition-opacity duration-300 group-hover:opacity-60"
            style={{ background: `radial-gradient(circle at 50% 50%, ${item.glow} 0%, transparent 72%)` }}
          />

          <Icon
            className={`${rail ? "h-[18px] w-[18px]" : "h-[22px] w-[22px]"} shrink-0 transition-transform duration-300 group-hover:-translate-y-px`}
            strokeWidth={isActive ? 2.4 : 1.9}
            style={{ color: isActive ? item.tint : undefined }}
          />
          <span className={rail ? "text-[13.5px] font-medium" : "text-[10.5px] font-semibold tracking-[0.01em]"}>
            {item.label}
          </span>

          {/* The active pip on the tab bar. A rail has room for weight and colour
              to say "here"; a 64px-wide tab does not, so it gets a mark. */}
          {!rail && isActive && (
            <motion.span
              layoutId="tab-pip"
              transition={spring}
              aria-hidden
              className="absolute -top-px h-[3px] w-7 rounded-full"
              style={{ background: item.tint, boxShadow: `0 0 12px ${item.glow}` }}
            />
          )}
        </>
      )}
    </NavLink>
  );
}

/** Bottom tabs. Rendered below `lg`; the rail takes over above it. */
export function GlowTabs() {
  return (
    <nav
      aria-label="Primary"
      className="fixed inset-x-0 bottom-0 z-40 lg:hidden"
      style={{ paddingBottom: "max(env(safe-area-inset-bottom), 0.5rem)" }}
    >
      <div
        // Capped and centred: on a tablet a 900px-wide tab bar spreads five
        // items so far apart they stop reading as one control.
        className="mx-3 mb-1 flex max-w-[520px] items-stretch gap-1 rounded-[26px] border border-line px-1.5 py-1 sm:mx-auto"
        style={{
          background: "color-mix(in oklab, var(--surface) 88%, var(--bg))",
          backdropFilter: "blur(28px) saturate(150%)",
          boxShadow: "var(--shadow-lift)",
        }}
      >
        {NAV_ITEMS.map((i) => (
          <Item key={i.to} item={i} rail={false} />
        ))}
      </div>
    </nav>
  );
}

/** The desktop rail. Same items, same glow, room for the wordmark. */
export function GlowRail({ children }: { children?: React.ReactNode }) {
  return (
    <aside className="fixed inset-y-0 left-0 z-40 hidden w-[248px] flex-col gap-1 border-r border-line px-3 py-5 lg:flex"
      style={{ background: "color-mix(in oklab, var(--surface) 92%, var(--bg))", backdropFilter: "blur(28px)" }}>
      {children}
      <div className="mt-2 flex flex-col gap-1">
        {NAV_ITEMS.map((i) => (
          <Item key={i.to} item={i} rail />
        ))}
      </div>
    </aside>
  );
}
