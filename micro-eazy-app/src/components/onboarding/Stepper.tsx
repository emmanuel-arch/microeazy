// ─────────────────────────────────────────────────────────────────────────────
// THE STEPPER — how far in, and how much is left.
//
// It shows only the steps the CUSTOMER is asked to do, because a progress bar
// that counts work being done by a machine is a progress bar that lies: the
// registry lookup takes 900ms and the selfie takes a minute, and numbering them
// alike tells somebody they are halfway when they are not.
//
// Automatic steps are not hidden — they appear in the "what happened" explainer
// afterwards — they are just not counted here.
//
// Dots, not labels. Five words of Kiswahili or English under each of six steps
// is a wall on a 360px screen; the current step's title is already the page
// heading, and the dots answer the only other question, which is "how much
// more of this is there".
// ─────────────────────────────────────────────────────────────────────────────
import { Check } from "lucide-react";

export function Stepper({ total, index }: { total: number; index: number }) {
  return (
    <div className="flex items-center gap-2" role="group" aria-label={`Step ${index + 1} of ${total}`}>
      {Array.from({ length: total }, (_, i) => {
        const done = i < index;
        const now = i === index;
        return (
          <span
            key={i}
            className="relative flex h-1.5 flex-1 items-center overflow-hidden rounded-full"
            style={{ background: "rgb(255 255 255 / 0.22)" }}
          >
            <span
              className="h-full rounded-full transition-[width] duration-500 ease-out"
              style={{
                width: done ? "100%" : now ? "45%" : "0%",
                background: "linear-gradient(90deg, var(--lime), #a7e635)",
              }}
            />
          </span>
        );
      })}
      <span className="ml-1 flex items-center gap-1 text-[11px] font-semibold tabular-nums text-sky-ink-soft">
        {index >= total ? <Check className="h-3.5 w-3.5" /> : `${index + 1}/${total}`}
      </span>
    </div>
  );
}

export default Stepper;
