# Micro Eazy

A two-sided credit ecosystem. Licensed lenders run their whole business on one side,
Kenyan borrowers install one app on the other, and a consent-gated exchange sits
between them.

This repository is the **meta-repo**. It contains no product code. It pins each system
at a commit, holds the one registry every orchestration script reads, and lets the whole
estate be cloned, checked and run with three commands.

```
git clone --recurse-submodules https://github.com/emmanuel-arch/microeazy
cd microeazy
npm run doctor        # is this machine ready?
npm run bootstrap     # install everything
npm run dev           # run everything, one prefixed log
```

---

## The systems

| System | What it is | Local | Repo |
|---|---|---|---|
| **The Connected Suite** | The lender realm. Lending console, customer portal, analytics studio, PeopleHub, Ledgerly and ConnectDesk — six front doors, one BirgenAI ID. | `:3000` | `BirgenAI_LMS` |
| **The Interchange** | A federated data exchange. Members query each other in real time through a consent-gated broker; nothing is pooled, and identity is destroyed at the edge. | `:3341` | `Interchange` |
| **Micro Eazy** | The borrower realm. One installable PWA: verify once, apply, track, repay. | `:5173` | `micro-eazy-pwa` |
| **PBX Authentication** | Call-centre telephony worker behind ConnectDesk's softphone. A .NET Worker Service — no port, no browser surface. | — | `skegode/PBXAuthentication` *(upstream)* |

---

## Why submodules and not one big repository

Every system here already had a life before this repo existed: its own history, its own
remote, and — for the Connected Suite — **a live Vercel project with its environment
already mapped**.

Vendoring them into a monorepo would mean re-pointing that Vercel project at a new
repository and a new root directory, and re-mapping every environment variable by hand.
Nothing about the product would improve. The deployment would simply be at risk for a
weekend.

So the meta-repo pins rather than absorbs:

```
microeazy/                       ← this repo: pointers, registry, scripts, docs
├── .gitmodules                  ← four lines that say where each system lives
├── ecosystem/
│   ├── registry.json            ← THE source of truth: paths, ports, commands, doors
│   └── scripts/                 ← dev · doctor · bootstrap · build
├── connected-suite/  ──────────→ emmanuel-arch/BirgenAI_LMS      (Vercel, live)
├── interchange/      ──────────→ emmanuel-arch/Interchange
├── pwa/              ──────────→ emmanuel-arch/micro-eazy-pwa
└── pbx-auth/         ──────────→ skegode/PBXAuthentication       (upstream, read-only)
```

Each system keeps its own CI, its own deploy, its own release cadence. The meta-repo
records **which commit of each one constitutes a working ecosystem** — which is the thing
that was previously written down nowhere, and the reason a fresh machine could not
reproduce a working estate.

### The renamed folder

`BirgenAI_LMS` is checked out as **`connected-suite`**, because that is what the system
calls itself in its own code — `src/lib/suite/apps.ts` opens with *"THE CONNECTED SUITE —
BirgenAI ID"*, and the Interchange's sign-in screen already footers with *"Single Sign-On
· The Connected Suite"*.

**The remote is unchanged and Vercel is unaffected.** Vercel builds from the GitHub
repository and has never seen a local folder name. Renaming a directory on a laptop
cannot reach it.

---

## Adding a system

One registry entry, one `git submodule add`. It then appears in `dev`, `build`, `doctor`
and this table without another edit. See [`ecosystem/ADDING-A-SYSTEM.md`](ecosystem/ADDING-A-SYSTEM.md).

---

## Commands

| Command | What it does |
|---|---|
| `npm run doctor` | Checks toolchain, checkouts, dependencies, env files and ports. Never prints a secret. |
| `npm run bootstrap` | Installs dependencies for every system, sequentially. |
| `npm run dev` | Runs every system with prefixed, interleaved output. Ctrl-C stops the tree. |
| `npm run build` | Production build of every system. Exits non-zero if any fails. |
| `npm run serve` | Runs every system from its **built output** instead of a dev server. No hot reload. |
| `npm run sync` | Pulls each submodule to its remote tip. |
| `npm run pull` | Pulls the meta-repo and re-points every submodule at its pinned commit. |

All of these accept system ids: `npm run dev interchange pwa`.

### On a machine with 8 GB

`npm run dev` does not fit. A Turbopack dev server settles near 1.9 GB and there are
two of them, so the full set wants about 5.6 GB on top of an editor — and Windows does
not report that as a shortage, it pages until the desktop stops repainting. Both `dev`
and `doctor` now price the run against free memory before anything is spawned, and
refuse rather than let you find out.

`npm run serve` is the way through: the same systems, served from `npm run build`
output, at about 0.3 GB each. Demo from `serve`; develop with `npm run dev interchange`,
one system at a time. The per-stack numbers live in `ecosystem/registry.json` under
`memory`, so `dev` and `doctor` cannot disagree about what a system costs.

---

## Signing in

| System | Door | Credential |
|---|---|---|
| Connected Suite | `/platform/login` | Platform admin — email + password |
| Connected Suite | `/login` | Lender staff — email + password + daily code |
| Interchange | `/` → Access Code | Four-digit operator code |
| Interchange | `/` → Member Certificate | Ed25519, signed by the member's node |

Interchange operators are managed from `interchange/apps/interchange-console`:

```bash
npm run operator -- list
npm run operator -- create --name "…" --role SUPER_ADMIN --code 5564
npm run operator -- recode  --name "…" --code 7788
npm run operator -- unlock  --name "…"
```

Roles are `SUPER_ADMIN` (platform, every right), `MEMBER_ADMIN`, `ANALYST`, `AUDITOR`.
Rights live in one catalogue at `lib/rights.ts`, and the console nav, the proxy and each
route all read it — so a menu item cannot exist without the check behind it.

---

## Further reading

- [`ecosystem/ARCHITECTURE.md`](ecosystem/ARCHITECTURE.md) — how the systems fit together, and the boundaries that matter
- [`ecosystem/ADDING-A-SYSTEM.md`](ecosystem/ADDING-A-SYSTEM.md) — the contract a new system signs
- `connected-suite/docs/MICRO-EAZY-ECOSYSTEM.md` — the product blueprint
- `interchange/docs/` — the Interchange blueprint v2
