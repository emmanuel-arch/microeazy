// ─────────────────────────────────────────────────────────────────────────────
// THEME — three states, not two.
//
// "Dark mode" is usually built as a boolean and that is the bug: a person who
// has never touched the toggle has not chosen light, they have chosen WHATEVER
// THEIR PHONE IS DOING, and at 7pm that changes underneath them. So the stored
// value is "light" | "dark" | "system", and only an explicit choice is written.
//
// The applied value is stamped on <html data-theme> because CSS custom
// properties cascade from there and every token in styles/theme.css keys off it.
//
// FOUC: the first paint must already be correct or the app flashes white in a
// dark room. index.html carries a tiny inline script that stamps the attribute
// before the bundle loads; this module then takes over. Keep the two in step.
// ─────────────────────────────────────────────────────────────────────────────
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

export type ThemeChoice = "light" | "dark" | "system";
export type Resolved = "light" | "dark";

const KEY = "me.theme";

interface Ctx {
  choice: ThemeChoice;
  resolved: Resolved;
  setChoice: (c: ThemeChoice) => void;
  /** Cycles light → dark → system. What the toggle in the header calls. */
  cycle: () => void;
}

const ThemeContext = createContext<Ctx | null>(null);

function readStored(): ThemeChoice {
  try {
    const v = localStorage.getItem(KEY);
    return v === "light" || v === "dark" || v === "system" ? v : "system";
  } catch {
    // Private windows and locked-down browsers throw on ACCESS, not just on
    // write. A theme preference is never worth a blank screen.
    return "system";
  }
}

function systemIsDark(): boolean {
  return typeof window !== "undefined" && window.matchMedia?.("(prefers-color-scheme: dark)").matches;
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [choice, setChoiceState] = useState<ThemeChoice>(readStored);
  const [sysDark, setSysDark] = useState(systemIsDark);

  // Follow the OS while the choice is "system" — and keep listening even when it
  // is not, so switching back to "system" is instantly right.
  useEffect(() => {
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = (e: MediaQueryListEvent) => setSysDark(e.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);

  const resolved: Resolved = choice === "system" ? (sysDark ? "dark" : "light") : choice;

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", resolved);
    // The browser chrome — address bar, status bar — is part of the app's
    // surface on a phone. Leaving it white above a black screen is the tell
    // that something is a web page rather than an app.
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", resolved === "dark" ? "#04060e" : "#012863");
  }, [resolved]);

  const setChoice = useCallback((c: ThemeChoice) => {
    setChoiceState(c);
    try {
      localStorage.setItem(KEY, c);
    } catch {
      /* preference is a convenience, never a requirement */
    }
  }, []);

  const cycle = useCallback(() => {
    setChoice(choice === "light" ? "dark" : choice === "dark" ? "system" : "light");
  }, [choice, setChoice]);

  const value = useMemo(() => ({ choice, resolved, setChoice, cycle }), [choice, resolved, setChoice, cycle]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): Ctx {
  const c = useContext(ThemeContext);
  if (!c) throw new Error("useTheme must be used inside <ThemeProvider>");
  return c;
}
