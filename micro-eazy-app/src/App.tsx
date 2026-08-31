// ─────────────────────────────────────────────────────────────────────────────
// THE SHELL.
//
// One column, thumb-first, chrome at the edges. The rail appears at `lg` because
// the app is also opened on a laptop by staff walking a customer through it —
// but the phone is the design target and the desktop is the adaptation, not the
// other way round. That order is the whole difference between this and the app
// it replaces.
//
// Onboarding renders WITHOUT the tab bar. Somebody halfway through proving who
// they are should not be offered four other places to go: a nav bar during a
// verification flow is an invitation to abandon it, and an abandoned KYC session
// is a customer who has handed over a photograph of their ID for nothing.
// ─────────────────────────────────────────────────────────────────────────────
import { BrowserRouter, Route, Routes, useLocation } from "react-router-dom";
import { GlowRail, GlowTabs } from "./components/nav/GlowNav";
import { ThemeProvider } from "./lib/theme";
import Home from "./screens/Home";
import Placeholder from "./screens/Placeholder";
import Onboarding from "./screens/onboarding/Onboarding";
import Welcome from "./screens/Welcome";
import Repay from "./screens/Repay";
import WhyThisDecision from "./screens/WhyThisDecision";
import Ladder from "./screens/Ladder";
import Exposure from "./screens/Exposure";

function Wordmark() {
  return (
    <div className="flex items-center gap-2.5 px-2 py-1">
      <span
        className="grid h-9 w-9 place-items-center rounded-xl text-[15px] font-black text-white"
        style={{ background: "var(--sky)", boxShadow: "0 6px 18px -8px var(--navy)" }}
      >
        M
      </span>
      <span className="leading-none">
        <span className="block text-[15px] font-bold tracking-[-0.02em]">Micro Eazy</span>
        <span className="block text-[11px] text-ink-faint">Quick loans. Better living.</span>
      </span>
    </div>
  );
}

/** Routes that own the whole screen — no nav, no way out but forward or back.
 *
 *  The front door is here for the same reason onboarding is: a person who has
 *  not signed in yet has nothing to navigate TO, and four tabs under a sign-in
 *  form are four ways to leave before starting. */
const FOCUSED = ["/join", "/welcome"];

function Shell() {
  const { pathname } = useLocation();
  const focused = FOCUSED.some((p) => pathname === p || pathname.startsWith(`${p}/`));

  return (
    <div className="min-h-full">
      {!focused && (
        <GlowRail>
          <Wordmark />
        </GlowRail>
      )}

      <div className={focused ? "" : "lg:pl-[248px]"}>
        {/* ── WIDTH IS A DESIGN DECISION, NOT A BREAKPOINT ─────────────────
            The phone is the design target, so the column is 560px — the width
            at which a line of body text is comfortable and a card is a card.

            But this app is also opened on a laptop: by a customer who prefers a
            keyboard, and by staff walking somebody through it. Holding a 560px
            column in the middle of a 1440px screen is not "mobile-first", it is
            a phone in a window with two feet of empty page around it, and it
            reads as an app that was never finished.

            So above `xl` the column opens to a real canvas and the SCREENS
            decide what to do with it — Home splits into a primary and a
            secondary column; onboarding deliberately does not, because a
            verification flow with a sidebar of distractions is a verification
            flow people abandon. */}
        <main
          className={`mx-auto w-full ${
            focused ? "max-w-[1040px] pb-12" : "max-w-[560px] pb-32 lg:max-w-[720px] xl:max-w-[1180px] lg:pb-12"
          }`}
        >
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/welcome" element={<Welcome />} />
            <Route path="/join" element={<Onboarding />} />
            <Route path="/repay" element={<Repay />} />
            {/* The Score tab opens on the DECISION, not on a dial. A number
                without its reasons is the thing customers ring up about, and
                the ladder and the credit file hang off it as the two questions
                that follow: how did it get here, and who else can see it. */}
            <Route path="/score" element={<WhyThisDecision />} />
            <Route path="/ladder" element={<Ladder />} />
            <Route path="/exposure" element={<Exposure />} />
            <Route path="/loans" element={<Placeholder title="Your loans" />} />
            <Route path="/you" element={<Placeholder title="You" />} />
            <Route path="*" element={<Placeholder title="Not found" />} />
          </Routes>
        </main>
      </div>

      {!focused && <GlowTabs />}
    </div>
  );
}

export default function App() {
  return (
    <ThemeProvider>
      <BrowserRouter>
        <Shell />
      </BrowserRouter>
    </ThemeProvider>
  );
}
