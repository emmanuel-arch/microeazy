// ─────────────────────────────────────────────────────────────────────────────
// TWO ROADS TO THE LENDER.
//
// A borrower standing in a shop with an approved loan does not care which
// hostname answered. They care that the button worked. So every call in this app
// goes through here, and here knows about two independent routes to the same
// Connected Suite:
//
//   PRIMARY   same-origin /api/*  →  Vercel rewrite  →  lms.servicesuitecloud.com
//   FALLBACK  the Tailscale Funnel host, direct      →  the same suite
//
// They share nothing. Different DNS, different edge, different certificate
// chain. A Vercel incident, a DNS propagation failure, or an expired cert on the
// primary takes out the first and not the second — which is the entire point.
//
// ── THE CONSTRAINT THAT SHAPES ALL OF THIS ──────────────────────────────────
// The borrower session is an httpOnly cookie with SameSite=Lax (see
// connected-suite/src/lib/portal/session.ts, and pwa/DEPLOY.md for the day this
// was learned the hard way). A Lax cookie IS NOT SENT on a cross-site XHR. The
// fallback is a different origin. So failing over does not carry the session
// with it, and an authenticated call that switches roads arrives anonymous.
//
// That is not something a client can paper over, and pretending otherwise would
// produce the worst kind of outage: one where the app looks up, every request
// 401s, and the logs say the customer signed out.
//
// So the honest split, which is what this file implements:
//
//   · PUBLIC calls (products, content, health, anything pre-sign-in) fail over
//     freely. They need no credential.
//   · AUTHENTICATED calls fail over ONLY when the app holds a bearer token —
//     a credential that is not bound to an origin. Until the suite issues one
//     from /api/portal/otp/verify, an authenticated call on the fallback road
//     is reported as degraded rather than attempted and silently failed.
//
// `authMode` below is where that is decided, and `TRANSPORT_TODO` names the one
// server change that turns full failover on.
//
// ── WHAT MUST NEVER BE RETRIED ──────────────────────────────────────────────
// Failover is a retry wearing a different hat, and a retried POST /api/portal/pay
// is a second STK push to a real person's phone for real money. A timeout is
// NOT evidence that the server did not act — the request may have been received,
// processed, and the response lost on the way back.
//
// So: GET and HEAD retry freely. Anything else retries only when the caller has
// said it is safe (`idempotent: true`) or has supplied an Idempotency-Key that
// the server can deduplicate against. Payments and disbursements pass neither.
// ─────────────────────────────────────────────────────────────────────────────

export type ChannelId = "primary" | "fallback";

export interface Channel {
  id: ChannelId;
  /** Shown to staff on the demo badge; never to a borrower mid-flow. */
  label: string;
  /** "" means same-origin — the primary, and the only one the cookie reaches. */
  baseUrl: string;
  /** Whether a session cookie travels on this road. */
  carriesCookie: boolean;
}

/**
 * The fallback host. A Tailscale Funnel URL — publicly reachable, so a customer
 * on a phone does not need to be on the tailnet; it is a second PUBLIC road that
 * happens to be served from inside it. Set VITE_API_FALLBACK to
 * https://<host>.tail10c441.ts.net to arm it.
 */
const FALLBACK_BASE = (import.meta.env.VITE_API_FALLBACK ?? "").replace(/\/+$/, "");

export const CHANNELS: Channel[] = [
  { id: "primary", label: "Direct", baseUrl: "", carriesCookie: true },
  ...(FALLBACK_BASE
    ? [{ id: "fallback" as const, label: "Relay", baseUrl: FALLBACK_BASE, carriesCookie: false }]
    : []),
];

/** The one server change that unlocks failover for signed-in customers. */
export const TRANSPORT_TODO =
  "Issue a bearer token from /api/portal/otp/verify so authenticated calls can " +
  "cross origins. Until then the fallback serves public calls only.";

export type ChannelState = {
  active: ChannelId;
  /** Channels that failed their last attempt, with when. */
  degraded: ChannelId[];
  /** True while an authenticated call cannot use the road that is currently up. */
  authDegraded: boolean;
  lastError: string | null;
};

let state: ChannelState = { active: "primary", degraded: [], authDegraded: false, lastError: null };
const listeners = new Set<(s: ChannelState) => void>();

function publish(next: Partial<ChannelState>) {
  state = { ...state, ...next };
  listeners.forEach((l) => l(state));
}

export function getChannelState(): ChannelState {
  return state;
}

export function subscribeChannel(fn: (s: ChannelState) => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** A bearer token, when the app has one. Held in memory only: a token in
 *  localStorage is a token any XSS can read, and this one is the whole session. */
let bearer: string | null = null;
export function setBearer(token: string | null) {
  bearer = token;
}

export interface ApiOptions {
  /** Does this call need a signed-in borrower? Decides failover eligibility. */
  auth?: boolean;
  /**
   * Safe to send twice. GET and HEAD are assumed safe; everything else must say
   * so explicitly, because the default has to be the one that cannot double-pay
   * somebody.
   */
  idempotent?: boolean;
  /** Deduplicated server-side, which makes a non-idempotent call retryable. */
  idempotencyKey?: string;
  timeoutMs?: number;
  signal?: AbortSignal;
}

const DEFAULT_TIMEOUT = 12_000;

/** Gateway-level failures — the road is broken. An application 500 is NOT here:
 *  that is the far end answering, and asking a second host the same question
 *  will produce the same answer while doubling the load. */
const ROAD_FAILURE = new Set([502, 503, 504, 522, 523, 524]);

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

function usableChannels(opts: ApiOptions): Channel[] {
  const ordered = [...CHANNELS].sort((a, b) => (a.id === state.active ? -1 : b.id === state.active ? 1 : 0));
  if (!opts.auth) return ordered;
  // An authenticated call may only travel a road that can carry the credential.
  return ordered.filter((c) => c.carriesCookie || bearer !== null);
}

function mayRetry(method: string, opts: ApiOptions): boolean {
  const m = method.toUpperCase();
  if (m === "GET" || m === "HEAD") return true;
  return opts.idempotent === true || Boolean(opts.idempotencyKey);
}

export async function apiFetch<T = unknown>(
  path: string,
  init: RequestInit = {},
  opts: ApiOptions = {},
): Promise<T> {
  const method = init.method ?? "GET";
  const channels = usableChannels(opts);

  if (channels.length === 0) {
    publish({ authDegraded: true, lastError: "No road can carry this session." });
    throw new ApiError(
      "You are signed in on a connection that is currently unavailable. Sign in again to continue.",
      0,
      null,
    );
  }

  const canRetry = mayRetry(method, opts);
  let lastErr: unknown = null;

  for (let i = 0; i < channels.length; i++) {
    const ch = channels[i];
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? DEFAULT_TIMEOUT);
    // Honour a caller's own cancellation without losing our timeout.
    opts.signal?.addEventListener("abort", () => controller.abort(), { once: true });

    try {
      const headers = new Headers(init.headers);
      if (!headers.has("Content-Type") && init.body) headers.set("Content-Type", "application/json");
      if (bearer && !ch.carriesCookie) headers.set("Authorization", `Bearer ${bearer}`);
      if (opts.idempotencyKey) headers.set("Idempotency-Key", opts.idempotencyKey);

      const res = await fetch(`${ch.baseUrl}${path}`, {
        ...init,
        headers,
        credentials: ch.carriesCookie ? "include" : "omit",
        signal: controller.signal,
      });

      if (ROAD_FAILURE.has(res.status) && canRetry && i < channels.length - 1) {
        lastErr = new ApiError(`Gateway ${res.status} on ${ch.id}`, res.status, null);
        continue;
      }

      // Anything else is the far end ANSWERING — including a 404 and a 401.
      // Those are facts, not outages, and switching roads would only hide them.
      if (state.active !== ch.id) {
        publish({ active: ch.id, degraded: state.degraded.filter((d) => d !== ch.id) });
      }

      const text = await res.text();
      const body = text ? safeJson(text) : null;
      if (!res.ok) {
        throw new ApiError(messageFrom(body) ?? `Request failed (${res.status})`, res.status, body);
      }
      if (state.lastError) publish({ lastError: null, authDegraded: false });
      return body as T;
    } catch (err) {
      // An ApiError from the block above is a real answer; do not treat it as a
      // broken road and do not try the other one.
      if (err instanceof ApiError && !ROAD_FAILURE.has(err.status)) throw err;

      lastErr = err;
      publish({
        degraded: state.degraded.includes(ch.id) ? state.degraded : [...state.degraded, ch.id],
        lastError: err instanceof Error ? err.message : "Network error",
      });

      // The request may have been received and acted on. For anything that is
      // not provably safe to repeat, stop here and tell the caller, rather than
      // sending a second payment instruction down another road.
      if (!canRetry) break;
    } finally {
      clearTimeout(timer);
    }
  }

  throw lastErr instanceof Error
    ? lastErr
    : new ApiError("Could not reach the lender. Check your connection and try again.", 0, null);
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    // An HTML error page from an edge, most likely. Returning it as a string is
    // more useful than throwing a parse error that names a line number.
    return text;
  }
}

function messageFrom(body: unknown): string | null {
  if (body && typeof body === "object" && "message" in body) {
    const m = (body as { message?: unknown }).message;
    if (typeof m === "string" && m.trim()) return m;
  }
  return null;
}

/**
 * Bring the primary back when it recovers. Without this the app stays on the
 * fallback for the rest of the session — correct, but it means one blip moves
 * every customer onto the spare road until they reload.
 *
 * Cheap and unauthenticated, so it costs nothing and cannot 401.
 */
export function startChannelProbe(intervalMs = 60_000): () => void {
  if (CHANNELS.length < 2) return () => {};
  const tick = async () => {
    if (state.active === "primary") return;
    try {
      const res = await fetch("/api/portal/session", { method: "GET", credentials: "include" });
      if (res.ok || res.status === 401) {
        // 401 means the primary is UP and simply says we are not signed in —
        // which is a healthy road, not a failure.
        publish({ active: "primary", degraded: state.degraded.filter((d) => d !== "primary") });
      }
    } catch {
      /* still down; stay where we are */
    }
  };
  const id = setInterval(tick, intervalMs);
  return () => clearInterval(id);
}
