// ─────────────────────────────────────────────────────────────────────────────
// THE SKY — the saturated band every screen is hung from.
//
// It lives in its own file rather than in App.tsx, where it started. Screens
// were importing it from App while App imported the screens, and that circle
// works right up until the day module evaluation order changes and one of them
// is `undefined` at first render. Cheap to break now, expensive to diagnose at
// 2am before a demo.
//
// Each screen paints its own: the title and whatever sits under it differ per
// screen, and a shared header taking six props is worse than a component each
// screen composes.
// ─────────────────────────────────────────────────────────────────────────────
import type { ReactNode } from "react";
import { Bell, ArrowLeft } from "lucide-react";
import { ThemeToggle } from "./ThemeToggle";

export function Sky({
  title,
  onBack,
  children,
}: {
  title: string;
  /** Shows a back affordance in place of nothing. Onboarding uses it; Home does not. */
  onBack?: () => void;
  children?: ReactNode;
}) {
  return (
    <header className="sky aurora relative overflow-hidden rounded-b-[28px] px-5 pb-16 pt-[max(env(safe-area-inset-top),1rem)] lg:rounded-b-[32px]">
      <div className="relative z-10 flex items-center gap-3 py-3">
        {onBack && (
          <button
            onClick={onBack}
            aria-label="Back"
            className="-ml-2 grid h-9 w-9 shrink-0 place-items-center rounded-full text-sky-ink transition-colors hover:bg-white/10"
          >
            <ArrowLeft className="h-[18px] w-[18px]" strokeWidth={2.2} />
          </button>
        )}
        <h1 className="min-w-0 flex-1 truncate text-[17px] font-bold tracking-[-0.02em] text-sky-ink">{title}</h1>
        <div className="flex shrink-0 items-center gap-2">
          <button
            aria-label="Updates"
            className="grid h-10 w-10 place-items-center rounded-full border border-white/20 text-sky-ink transition-colors hover:bg-white/10"
          >
            <Bell className="h-[18px] w-[18px]" strokeWidth={2} />
          </button>
          <ThemeToggle />
        </div>
      </div>
      <div className="relative z-10">{children}</div>
    </header>
  );
}

export default Sky;
