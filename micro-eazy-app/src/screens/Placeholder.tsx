// A named empty room, not a 404. Each of these is replaced by a real screen as
// the flow is ported; keeping them routable means the nav is honest from day one
// and nothing in the shell has to be rewritten when the screen arrives.
import { Construction } from "lucide-react";
import { Sky } from "../components/shell/Sky";

export default function Placeholder({ title }: { title: string }) {
  return (
    <>
      <Sky title={title} />
      <div className="relative z-10 -mt-12 px-4">
        <section className="card flex flex-col items-center gap-3 px-5 py-12 text-center">
          <span
            className="grid h-12 w-12 place-items-center rounded-2xl"
            style={{ background: "color-mix(in oklab, var(--navy) 10%, transparent)", color: "var(--navy)" }}
          >
            <Construction className="h-5 w-5" strokeWidth={2} />
          </span>
          <p className="text-[15px] font-semibold">{title}</p>
          <p className="max-w-[32ch] text-[12.5px] leading-relaxed text-ink-faint">
            Being ported from the console flow. The shell, the theme and the nav are already final — only this room is
            empty.
          </p>
        </section>
      </div>
    </>
  );
}
