// ─────────────────────────────────────────────────────────────────────────────
// WHICH ROAD IS CARRYING YOU.
//
// Almost always: nothing. A borrower does not need to know that the primary edge
// answered — telling them would be noise, and a green "connected" pill on every
// screen is the tell of an app that is anxious about itself.
//
// It appears when something has actually changed:
//   · running on the fallback road          → quiet amber, "Backup route"
//   · signed in but the road cannot carry   → the one case they must act on
//
// The wording avoids "relay", "tailnet" and "channel". Those are our words. The
// customer's question is only ever "is this working", and the answer they need
// is either nothing at all or one sentence about what to do.
// ─────────────────────────────────────────────────────────────────────────────
import { useEffect, useState } from "react";
import { CloudOff, Route } from "lucide-react";
import { getChannelState, startChannelProbe, subscribeChannel, type ChannelState } from "../../lib/net/transport";

export function useChannel(): ChannelState {
  const [s, setS] = useState<ChannelState>(getChannelState);
  useEffect(() => {
    const stop = subscribeChannel(setS);
    const stopProbe = startChannelProbe();
    return () => {
      stop();
      stopProbe();
    };
  }, []);
  return s;
}

export function ChannelBadge() {
  const { active, authDegraded } = useChannel();
  if (active === "primary" && !authDegraded) return null;

  const critical = authDegraded;
  return (
    <div
      role="status"
      className="mx-4 mb-3 flex items-start gap-2.5 rounded-xl border px-3.5 py-2.5"
      style={{
        borderColor: critical ? "#e11d48" : "color-mix(in oklab, #f0a92b 50%, transparent)",
        background: critical
          ? "color-mix(in oklab, #e11d48 10%, transparent)"
          : "color-mix(in oklab, #f0a92b 12%, transparent)",
      }}
    >
      {critical ? (
        <CloudOff className="mt-px h-4 w-4 shrink-0" style={{ color: "#e11d48" }} strokeWidth={2.2} />
      ) : (
        <Route className="mt-px h-4 w-4 shrink-0" style={{ color: "#a16207" }} strokeWidth={2.2} />
      )}
      <p className="text-[12px] font-medium leading-snug">
        {critical ? (
          <>Sign in again to continue — your session cannot travel the route that is currently available.</>
        ) : (
          <>
            <span className="font-semibold">Backup route.</span> Everything works normally; this may be a little
            slower than usual.
          </>
        )}
      </p>
    </div>
  );
}

export default ChannelBadge;
