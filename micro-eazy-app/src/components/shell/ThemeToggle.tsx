// The appearance control, in the sky. One button that cycles light → dark →
// match-my-phone, because a header on a 360px screen has room for one control
// and three segments would cost the title its space.
//
// The lender console gets the three-segment version instead: it has the width,
// and staff switch deliberately rather than idly.
import { Moon, Sun, MonitorSmartphone } from "lucide-react";
import { useTheme } from "../../lib/theme";

export function ThemeToggle() {
  const { choice, cycle } = useTheme();
  const Icon = choice === "light" ? Sun : choice === "dark" ? Moon : MonitorSmartphone;
  const label = choice === "light" ? "Light" : choice === "dark" ? "Dark" : "Match my phone";
  return (
    <button
      onClick={cycle}
      aria-label={`Appearance: ${label}. Tap to change.`}
      title={label}
      className="grid h-10 w-10 place-items-center rounded-full border border-white/20 text-sky-ink transition-colors hover:bg-white/10"
    >
      <Icon className="h-[18px] w-[18px]" strokeWidth={2} />
    </button>
  );
}

export default ThemeToggle;
