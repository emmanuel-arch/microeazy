// ─────────────────────────────────────────────────────────────────────────────
// THE LIQUID-METAL CONTROL, MADE FIT FOR A PHONE.
//
// The reference component this is derived from is genuinely beautiful and could
// not have shipped as-is, for two reasons worth writing down because they will
// come up again with every component we lift:
//
//   1. IT WAS DRIVEN BY `onMouseMove`. The specular highlight — the thing that
//      makes the bezel look machined — tracked the cursor. Every borrower in
//      this app is on a phone. There is no cursor, `mousemove` never fires, and
//      the control degrades to a flat dark circle: all of the weight, none of
//      the effect. This uses POINTER events, which fire for touch, pen and mouse
//      alike, and on a touch device the highlight tracks the finger while it is
//      down. Press it on a handset and the metal lights under your thumb.
//
//   2. IT WAS ICON-ONLY AND ALWAYS DARK. A borrower's primary action is a
//      sentence — "Request for KSh 350" — and half of them will be reading it
//      outdoors in light mode. So the metal became a variant rather than the
//      whole button, and the default action is `primary`: lime fill, navy type,
//      6.65:1. See the note on the two greens in styles/theme.css.
//
// What is kept, because it is what makes it feel expensive: the three-layer
// bezel, the specular that follows the pointer, the top hairline, the inset
// shadow that deepens on press, and the 4px physical travel.
// ─────────────────────────────────────────────────────────────────────────────
import { useCallback, useRef, useState, type ButtonHTMLAttributes, type ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { Loader2 } from "lucide-react";

type Variant = "primary" | "metal" | "ghost";
type Size = "sm" | "md" | "lg";

interface LiquidButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "children"> {
  children?: ReactNode;
  icon?: LucideIcon;
  /** Icon after the label instead of before — for "continue" actions. */
  trailingIcon?: LucideIcon;
  variant?: Variant;
  size?: Size;
  /** Stretch to the container. The bottom-of-screen commit button always does. */
  block?: boolean;
  loading?: boolean;
}

const SIZE: Record<Size, { pad: string; text: string; icon: string; glow: number }> = {
  sm: { pad: "px-4 py-2.5", text: "text-[13px]", icon: "h-4 w-4", glow: 90 },
  md: { pad: "px-6 py-3.5", text: "text-[15px]", icon: "h-[18px] w-[18px]", glow: 140 },
  lg: { pad: "px-7 py-[18px]", text: "text-[16px]", icon: "h-5 w-5", glow: 190 },
};

export function LiquidButton({
  children,
  icon: Icon,
  trailingIcon: TrailingIcon,
  variant = "primary",
  size = "md",
  block = false,
  loading = false,
  disabled,
  className = "",
  onPointerDown,
  onPointerUp,
  ...rest
}: LiquidButtonProps) {
  const ref = useRef<HTMLButtonElement>(null);
  const [spec, setSpec] = useState<{ x: number; y: number } | null>(null);
  const [pressed, setPressed] = useState(false);
  const cfg = SIZE[size];
  const inert = disabled || loading;

  // One handler for mouse, pen and finger. `pressure`-independent: we only need
  // where it is, and for touch we only track it while it is down (there is no
  // hover state to preview on a screen you have to touch to point at).
  const track = useCallback((e: React.PointerEvent<HTMLButtonElement>) => {
    const el = ref.current;
    if (!el) return;
    if (e.pointerType !== "mouse" && !pressed) return;
    const r = el.getBoundingClientRect();
    setSpec({ x: e.clientX - r.left, y: e.clientY - r.top });
  }, [pressed]);

  const base =
    `group relative isolate inline-flex select-none items-center justify-center gap-2 rounded-full ` +
    `font-semibold tracking-[-0.01em] touch-manipulation outline-none ` +
    `focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-bg focus-visible:ring-[var(--lime)] ` +
    `disabled:cursor-not-allowed ` +
    `${cfg.pad} ${cfg.text} ${block ? "w-full" : ""} ${className}`;

  return (
    <button
      ref={ref}
      disabled={inert}
      onPointerMove={track}
      onPointerDown={(e) => {
        setPressed(true);
        track(e);
        onPointerDown?.(e);
      }}
      onPointerUp={(e) => {
        setPressed(false);
        onPointerUp?.(e);
      }}
      onPointerLeave={() => {
        setPressed(false);
        setSpec(null);
      }}
      onPointerCancel={() => {
        setPressed(false);
        setSpec(null);
      }}
      className={base}
      style={{
        // The physical travel. 4px is what separates "a coloured rectangle
        // changed state" from "I pressed something".
        transform: pressed && !inert ? "translateY(3px)" : "translateY(0)",
        transition: "transform 110ms ease-out",
        // A DISABLED BUTTON MUST NOT LOOK PRESSABLE. Dimming the lime to 55%
        // leaves a green, glossy, arrow-bearing control that still reads as the
        // way forward — so somebody taps it, nothing happens, and they conclude
        // the app is broken rather than that they missed a field. Inert drops
        // the fill entirely and takes the ink down with it; the label says why
        // ("Tick the box to continue"), so the control never has to.
        background: inert
          ? "var(--surface-sunk)"
          : variant === "primary"
            ? "linear-gradient(180deg, #8fdd18 0%, var(--lime) 52%, #66ab08 100%)"
            : variant === "metal"
              ? "var(--metal-rim)"
              : "transparent",
        color: inert
          ? "var(--ink-faint)"
          : variant === "primary"
            ? "var(--navy-deep)"
            : variant === "metal"
              ? "var(--metal-ink)"
              : "var(--ink)",
        padding: variant === "ghost" ? undefined : "2px",
        boxShadow:
          variant === "ghost" || inert
            ? "none"
            : pressed
              ? "0 2px 6px rgb(0 0 0 / 0.28)"
              : "0 10px 26px -12px rgb(0 0 0 / 0.45)",
        // An inert control sits ON the page rather than above it — no lift, and
        // a hairline instead of a shadow, so it reads as a placeholder for a
        // button rather than a button that is ignoring you.
        border: variant === "ghost" || inert ? "1px solid var(--line-strong)" : "none",
      }}
      {...rest}
    >
      {/* The face. A second, inset element is what gives the rim its thickness —
          a single div with a border reads as a sticker, not as a machined part. */}
      <span
        className={`relative flex w-full items-center justify-center gap-2 overflow-hidden rounded-full ${cfg.pad}`}
        style={{
          background: inert
            ? "transparent"
            : variant === "primary"
              ? "linear-gradient(180deg, rgb(255 255 255 / 0.28) 0%, rgb(255 255 255 / 0) 46%)"
              : variant === "metal"
                ? "var(--metal-face)"
                : "transparent",
          boxShadow:
            variant === "ghost" || inert
              ? "none"
              : pressed
                ? "inset 0 6px 14px rgb(0 0 0 / 0.30)"
                : "inset 0 -2px 6px rgb(0 0 0 / 0.14), inset 0 1px 0 rgb(255 255 255 / 0.35)",
        }}
      >
        {/* The specular. Follows the pointer; absent until there is one, so the
            resting state is a clean surface rather than a permanent hotspot. */}
        {spec && !inert && variant !== "ghost" && (
          <span
            aria-hidden
            className="pointer-events-none absolute inset-0 rounded-full transition-opacity duration-150"
            style={{
              background: `radial-gradient(${cfg.glow}px circle at ${spec.x}px ${spec.y}px, var(--spec) 0%, rgb(255 255 255 / 0.35) 30%, transparent 65%)`,
              opacity: pressed ? 0.55 : 0.34,
              mixBlendMode: "soft-light",
            }}
          />
        )}

        {/* The hairline along the top edge. One pixel, and the single cheapest
            thing on this button — it is what reads as "polished". */}
        {variant !== "ghost" && !inert && (
          <span
            aria-hidden
            className="pointer-events-none absolute inset-x-5 top-0 h-px rounded-full"
            style={{
              background: "linear-gradient(90deg, transparent, rgb(255 255 255 / 0.75), transparent)",
              opacity: pressed ? 0 : 1,
              transition: "opacity 110ms ease-out",
            }}
          />
        )}

        {loading ? (
          <Loader2 className={`${cfg.icon} animate-spin`} />
        ) : (
          Icon && <Icon className={cfg.icon} strokeWidth={2.2} />
        )}
        {children && <span className="relative">{children}</span>}
        {TrailingIcon && !loading && (
          <TrailingIcon
            className={`${cfg.icon} transition-transform duration-200 group-hover:translate-x-0.5`}
            strokeWidth={2.2}
          />
        )}
      </span>
    </button>
  );
}

export default LiquidButton;
