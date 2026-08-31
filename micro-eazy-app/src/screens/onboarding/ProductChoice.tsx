// ─────────────────────────────────────────────────────────────────────────────
// CHOOSE YOUR PRODUCT — the screen where a lender usually stops explaining.
//
// The convention in this market is to quote a RATE. "8.25% a week" is a true
// statement and a useless one: nobody multiplies it by ten in their head while
// standing in a shop, and the number that actually decides whether a loan is a
// good idea — what you hand back in total — is the one number the screen does
// not show. That is not an accident of design, it is how the product is sold.
//
// So this screen leads with the total. KSh 5,000 costs you KSh 4,125. The rate
// is still there, in small type, because it is what a customer will be quoted
// by anybody else and they should be able to match the two up — but it is a
// footnote to the cost, not a substitute for it.
//
// ── WHY BOTH PRODUCTS ARE ALWAYS ON SCREEN ──────────────────────────────────
// A product the customer does not qualify for is shown LOCKED, with the reason,
// rather than filtered out of the list. A shelf that quietly hides what you
// cannot have teaches you that there was nothing else on it — and the customer
// who would have qualified next month never finds out that the monthly product
// exists. The reason is the useful part: "from KSh 10,000" and "needs a score
// of 620" are both things somebody can act on.
//
// ── THE NUMBERS ARE A QUOTE, AND SAY SO ─────────────────────────────────────
// Everything here comes from lib/quote.ts, which is a port of the server's own
// schedule builder — same rounding, same remainder convention. It is still a
// quote: the binding figures arrive on the agreement, from the offer, and that
// is the only place a signature is possible. The line at the foot of the card
// says exactly that rather than burying it in a tooltip.
// ─────────────────────────────────────────────────────────────────────────────
import { useEffect, useMemo, useState } from "react";
import { ArrowRight, CalendarDays, Check, Info, Lock, TrendingDown } from "lucide-react";
import { LiquidButton } from "../../components/ui/LiquidButton";
import { listProducts } from "../../lib/api/portal";
import { SAMPLE_PRODUCTS } from "../../lib/api/samples";
import { money, periodCount, shortDate } from "../../lib/format";
import { affordableRange, quote, type Product, type Quote } from "../../lib/quote";

/** Amounts move in 500s. Fine enough to land on what somebody actually needs,
 *  coarse enough that a slider on a 360px screen can hit it with a thumb. */
const STEP = 500;

const clampToStep = (n: number, min: number, max: number) =>
  Math.min(Math.max(Math.round(n / STEP) * STEP, min), max);

export default function ProductChoice({
  /** Set by the limit step. Until that screen exists this is the sample
   *  customer's, and it is the ONE number here the client must never compute. */
  limit = 45_000,
  /** What the score step landed on — gates products with a minimum. */
  creditScore = 712,
  onDone,
}: {
  limit?: number;
  creditScore?: number;
  onDone?: (q: Quote) => void;
}) {
  const [products, setProducts] = useState<Product[]>(SAMPLE_PRODUCTS);
  const [chosen, setChosen] = useState<string>(SAMPLE_PRODUCTS[0].id);
  const [amount, setAmount] = useState<number>(5_000);

  // The one call on this screen that needs no session — a lender's catalogue is
  // public. It is also the only place the app can prove the transport works
  // before anybody has signed in. A failure is not an error state: the shelf
  // falls back and the customer never learns that anything went wrong, which is
  // right, because nothing they can do would fix it.
  useEffect(() => {
    let live = true;
    listProducts()
      .then((r) => {
        if (!live || !r.products?.length) return;
        setProducts(r.products);
        setChosen((c) => (r.products.some((p) => p.id === c) ? c : r.products[0].id));
      })
      .catch(() => {});
    return () => {
      live = false;
    };
  }, []);

  const product = products.find((p) => p.id === chosen) ?? products[0];
  const range = affordableRange(product, limit);

  // Keep the amount inside whatever the CHOSEN product will actually book.
  // Switching from the weekly product to one with a 10,000 minimum silently
  // leaving 5,000 in the field would quote a loan that cannot exist.
  useEffect(() => {
    if (!range) return;
    setAmount((a) => clampToStep(a, range.min, range.max));
  }, [range?.min, range?.max]); // eslint-disable-line react-hooks/exhaustive-deps

  const q = useMemo(
    () => (range ? quote(product, clampToStep(amount, range.min, range.max)) : null),
    [product, amount, range?.min, range?.max], // eslint-disable-line react-hooks/exhaustive-deps
  );

  /** Round numbers a person actually asks for, inside what they can have. */
  const chips = useMemo(() => {
    if (!range) return [];
    return [2_500, 5_000, 10_000, 20_000, range.max]
      .filter((n, i, all) => n >= range.min && n <= range.max && all.indexOf(n) === i)
      .slice(0, 5);
  }, [range?.min, range?.max]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="space-y-3">
      {/* ── How much. ─────────────────────────────────────────────────────── */}
      <section className="card p-5">
        <div className="flex items-baseline justify-between gap-3">
          <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-faint">You want to borrow</p>
          <p className="text-[11.5px] text-ink-faint">
            up to <span className="tnum font-semibold text-ink-soft">{money(limit)}</span>
          </p>
        </div>

        <p className="tnum mt-1 text-[36px] font-bold leading-none tracking-[-0.03em]">{money(amount)}</p>

        {range ? (
          <>
            <input
              type="range"
              min={range.min}
              max={range.max}
              step={STEP}
              value={Math.min(Math.max(amount, range.min), range.max)}
              onChange={(e) => setAmount(Number(e.target.value))}
              aria-label="How much to borrow"
              className="mt-4 w-full"
              style={{ accentColor: "var(--lime)" }}
            />
            <div className="tnum flex justify-between text-[11px] text-ink-faint">
              <span>{money(range.min)}</span>
              <span>{money(range.max)}</span>
            </div>

            <div className="mt-3 flex flex-wrap gap-2">
              {chips.map((n) => {
                const on = amount === n;
                return (
                  <button
                    key={n}
                    onClick={() => setAmount(n)}
                    className="tnum rounded-full border px-3.5 py-2 text-[12.5px] font-semibold transition-colors"
                    style={{
                      borderColor: on ? "transparent" : "var(--line-strong)",
                      background: on ? "color-mix(in oklab, var(--lime) 26%, transparent)" : "transparent",
                      color: on ? "var(--green-ink)" : "var(--ink-soft)",
                    }}
                  >
                    {money(n)}
                  </button>
                );
              })}
            </div>
          </>
        ) : (
          <p className="mt-3 text-[12.5px] leading-snug text-ink-soft">
            Your limit is below the smallest loan this product writes. Choose another below.
          </p>
        )}
      </section>

      {/* ── Which product. ────────────────────────────────────────────────── */}
      <div className="space-y-3">
        {products.map((p) => (
          <ProductCard
            key={p.id}
            product={p}
            limit={limit}
            creditScore={creditScore}
            amount={amount}
            selected={p.id === chosen}
            onSelect={() => setChosen(p.id)}
          />
        ))}
      </div>

      <p className="flex items-start gap-2 px-1 text-[11.5px] leading-snug text-ink-faint">
        <Info className="mt-px h-3.5 w-3.5 shrink-0" />
        These figures are a quote. Your agreement shows the exact amounts and dates, and every charge, before you
        agree to anything.
      </p>

      <LiquidButton size="lg" block trailingIcon={ArrowRight} disabled={!q} onClick={() => q && onDone?.(q)}>
        {q ? `Continue with ${money(q.principal)}` : "Choose a product you qualify for"}
      </LiquidButton>
    </div>
  );
}

/**
 * One product, priced at the amount on the slider.
 *
 * Three states, and the two that are not "available" are the ones that carry
 * the information: `tooSmall` names the entry price, `needsScore` names the
 * number to reach. Neither is a dead end the customer has to guess at.
 */
function ProductCard({
  product, limit, creditScore, amount, selected, onSelect,
}: {
  product: Product;
  limit: number;
  creditScore: number;
  amount: number;
  selected: boolean;
  onSelect: () => void;
}) {
  const range = affordableRange(product, limit);
  const needsScore = product.minCreditScore != null && creditScore < product.minCreditScore;
  const locked = !range || needsScore;

  // Priced at what this product would actually book, not at the slider value —
  // quoting 5,000 on a product with a 10,000 floor would be a price for a loan
  // that does not exist.
  const priced = range ? Math.min(Math.max(amount, range.min), range.max) : product.minPrincipal;
  const q = quote(product, priced);

  return (
    <button
      type="button"
      onClick={locked ? undefined : onSelect}
      aria-pressed={selected}
      aria-disabled={locked}
      className="card w-full overflow-hidden text-left transition-transform duration-200 active:scale-[0.995]"
      style={{
        borderColor: selected ? "var(--green-ink)" : undefined,
        boxShadow: selected ? "0 0 0 1px var(--green-ink), var(--shadow-lift)" : undefined,
        cursor: locked ? "default" : "pointer",
        opacity: locked ? 0.72 : 1,
      }}
    >
      <div className="flex items-start gap-3 p-5 pb-4">
        <span
          aria-hidden
          className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full border transition-colors"
          style={{
            borderColor: selected ? "transparent" : "var(--line-strong)",
            background: selected ? "var(--lime)" : "transparent",
          }}
        >
          {selected && <Check className="h-3 w-3" strokeWidth={3} style={{ color: "var(--navy-deep)" }} />}
        </span>

        <span className="min-w-0 flex-1">
          <span className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
            <span className="text-[15px] font-bold tracking-[-0.015em]">{product.name}</span>
            <span className="text-[11.5px] text-ink-faint">
              {periodCount(product.repaymentPeriod, product.repaymentUnit)}
              {product.interestMethod === "reducing" && " · reducing balance"}
            </span>
          </span>
          {product.description && (
            <span className="mt-1 block text-[12px] leading-snug text-ink-soft">{product.description}</span>
          )}
        </span>
      </div>

      {locked ? (
        <div
          className="flex items-start gap-2.5 border-t px-5 py-3.5 text-[12px] leading-snug"
          style={{ borderColor: "var(--line)", background: "var(--surface-sunk)" }}
        >
          <Lock className="mt-px h-3.5 w-3.5 shrink-0 text-ink-faint" strokeWidth={2.1} />
          <span className="text-ink-soft">
            {!range ? (
              <>
                This product starts at <strong className="font-semibold text-ink">{money(product.minPrincipal)}</strong>,
                which is above your limit of {money(limit)} today. Clearing a loan raises the limit.
              </>
            ) : (
              <>
                Needs a credit score of{" "}
                <strong className="font-semibold text-ink">{product.minCreditScore}</strong>. Yours is {creditScore} —
                it moves every time you repay on time.
              </>
            )}
          </span>
        </div>
      ) : (
        <>
          {/* ── THE COST, FIRST. ──────────────────────────────────────────
              What you get, what you hand back, and the difference between
              them named as a cost rather than left as arithmetic homework. */}
          <div className="grid grid-cols-3 border-t" style={{ borderColor: "var(--line)" }}>
            {[
              { k: "You get", v: money(q.principal), sub: null },
              { k: "You repay", v: money(q.totalRepayable), sub: null },
              {
                k: "Cost of credit",
                v: money(q.totalInterest),
                sub: `${product.interestRate}% a ${product.interestUnit}`,
              },
            ].map((c, i) => (
              <div
                key={c.k}
                className="px-4 py-3.5"
                style={{ borderLeft: i > 0 ? "1px solid var(--line)" : undefined }}
              >
                <p className="text-[10.5px] font-semibold uppercase tracking-[0.06em] text-ink-faint">{c.k}</p>
                <p className="tnum mt-1 text-[16px] font-bold leading-none tracking-[-0.02em]">{c.v}</p>
                {c.sub && <p className="mt-1 text-[10.5px] leading-snug text-ink-faint">{c.sub}</p>}
              </div>
            ))}
          </div>

          <div
            className="space-y-1.5 border-t px-5 py-3.5 text-[12px] text-ink-soft"
            style={{ borderColor: "var(--line)" }}
          >
            <p className="flex items-center gap-2">
              <CalendarDays className="h-3.5 w-3.5 shrink-0 text-ink-faint" strokeWidth={2.1} />
              <span>
                About <strong className="tnum font-semibold text-ink">{money(q.perPeriod)}</strong> a{" "}
                {product.repaymentUnit}, clear by {shortDate(q.clearDate)}
              </span>
            </p>
            {q.upfrontCharges > 0 && (
              <p className="flex items-center gap-2">
                <TrendingDown className="h-3.5 w-3.5 shrink-0 text-ink-faint" strokeWidth={2.1} />
                <span>
                  <strong className="tnum font-semibold text-ink">{money(q.upfrontCharges)}</strong> in charges before
                  the money is sent
                </span>
              </p>
            )}
            {q.earlySettlementApplies && (
              <p className="flex items-center gap-2">
                <TrendingDown className="h-3.5 w-3.5 shrink-0" style={{ color: "var(--green-ink)" }} strokeWidth={2.1} />
                <span>Pay it off early and you pay less interest.</span>
              </p>
            )}
          </div>
        </>
      )}
    </button>
  );
}
