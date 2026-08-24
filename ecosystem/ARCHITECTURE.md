# The Micro Eazy ecosystem — architecture

Four systems, three of them products and one of them a worker. This document is about
what sits between them: the boundaries that are load-bearing, and the two or three places
where getting it wrong is expensive rather than merely annoying.

---

## The shape

```
                        ┌───────────────────────────────┐
   Kenyan borrower ───→ │  Micro Eazy  (PWA)      :5173 │
                        │  verify once · apply · repay  │
                        └───────────────┬───────────────┘
                                        │  consent captured here
                                        ▼
                        ┌───────────────────────────────┐
                        │  The Connected Suite    :3000 │
   Lender staff  ─────→ │  Lending · Portal · Analytics │
                        │  PeopleHub · Ledgerly · Desk  │
                        └───────┬───────────────┬───────┘
                                │               │
                 softphone auth │               │ exposure / bureau queries
                                ▼               ▼
              ┌──────────────────────┐  ┌───────────────────────────┐
              │ PBX Authentication   │  │  The Interchange    :3341 │
              │ .NET worker, no port │  │  consent-gated broker     │
              └──────────────────────┘  └─────────────┬─────────────┘
                                                      │ fan-out, signed
                                          ┌───────────┴───────────┐
                                          ▼                       ▼
                                   member node              member node
                                   (their own book)         (their own book)
```

---

## Two realms and a spine

**Realm A — the lender.** The Connected Suite is one deployment presenting six systems
behind one identity. A user signs in once and every system knows them, their org and
their branch. Identity, org and the branch tree cross between systems; **rights do not**.
An HR manager with full PeopleHub access must not inherit disbursement authority in the
lending console because they share an ID, so each app declares the right that admits it.

**Realm B — the borrower.** The PWA is a separate origin with a separate lifecycle. It
holds no lender data and no bureau data. It captures consent and it shows the borrower
what was done with it.

**The spine.** Session identity is one cookie scoped to the parent domain in production.
That is what makes the suite a suite rather than five sign-in pages — and it is also the
first thing that breaks when a system is split onto its own subdomain, because a cookie
set without an explicit `domain` is host-only and simply will not be sent next door.

---

## The boundaries that are load-bearing

### 1. Identity never crosses the Interchange boundary

Real identifiers — national ID, MSISDN — are converted to a `subject_token` by an OPRF
**inside the member's own node**. Nothing downstream ever sees a raw identifier: not the
broker, not the logs, not the message chain, not the models.

The consequence for anyone adding to this system: if you find yourself with a national ID
in a function that runs in the Registry, something upstream has already failed. Do not
add a redaction step. Find the leak.

### 2. `sourceEntityId` is a security boundary, not a query filter

Ten separate companies share one ServiceSuite database, partitioned only by `EntityID`.
They are competitors. A read that forgets to scope by it is not a bug that returns too
many rows — it is one lender reading another lender's book.

The node scopes every read. The caller is never trusted to supply the value.

### 3. No `consent_ref`, no answer

Every call that touches borrower data validates a consent reference against the Registry
before anything is returned. It is enforced in the handler, never in a comment and never
in a prompt.

### 4. Rights are one catalogue, read by every gate

`interchange/apps/interchange-console/lib/rights.ts` is the only list. The console nav,
`proxy.ts` and the route handlers all derive from it. This is what stops a menu item
existing without the check behind it — the failure mode that produces either a door onto
a 403, or a door onto data.

`*` is a real, storable right meaning *every right including ones added later*. It is
valid on `SUPER_ADMIN` and refused everywhere else, so a platform operator's powers do
not silently fail to include next sprint's surface.

---

## Sessions: two doors, one token

The Interchange has two ways in, and they mint the *same* signed session, so everything
downstream is identical whichever way you came:

| Door | Route | Credential | Where it is for |
|---|---|---|---|
| Machine | `POST /api/session` | Ed25519 signature from the member's node | Production |
| Human | `POST /api/session/code` | Four-digit operator code | Laptop, demos |

The session itself is a compact HMAC-signed token — payload plus signature, verified in
`proxy.ts` without touching Postgres on every navigation.

**Why this is signed at all.** The first version stored a bare member code and checked
only that the cookie existed. Anyone could open a console and type

```js
document.cookie = "interchange_session=KE/LENDER/3005"
```

to be inside as the largest lender in the cohort. `httpOnly` does not help: it stops a
script *reading* a cookie, not a person *writing* one. `scripts/verify-operator.ts`
asserts that exact forgery is now refused.

**On four-digit codes.** Ten thousand combinations means the hash is not the control that
matters — lockout is. Five wrong codes locks the operator for fifteen minutes, counted in
Postgres rather than memory, and refused attempts are also throttled per IP. Code sign-in
is refused outright when `NODE_ENV=production` unless `INTERCHANGE_ALLOW_CODE_LOGIN=1` is
explicitly set. A four-digit PIN is appropriate for a console on a laptop and for the
demo; the member certificate is the production door.

---

## The registry is the source of truth

`ecosystem/registry.json` declares every system: path, working directory, repo, port,
commands, env file, sign-in doors, deployment. Every orchestration script reads it and
nothing hard-codes a path or a port anywhere else.

This is deliberate and it is the property that makes the ecosystem extensible: adding a
system is one entry plus one `git submodule add`, and it appears in `dev`, `build`,
`doctor` and the README without another edit. When a new system does not fit, the registry
is missing a field — add the field rather than special-casing the system.

---

## Why the meta-repo pins instead of absorbing

Each system already had its own history, its own remote, and — for the Connected Suite —
a live Vercel project with its environment mapped. A monorepo would mean re-pointing that
project at a new repository and root directory and re-mapping every variable by hand, for
no product benefit.

So the meta-repo records **which commit of each system constitutes a working ecosystem**.
That was previously written down nowhere, which is precisely why a fresh machine could
not reproduce a working estate.

The cost of this choice is real and worth naming: a change spanning two systems is two
pull requests and a pointer bump, not one commit. That is the trade — independent
deployability in exchange for cross-cutting changes being deliberate.

---

## Local ports

| Port | System |
|---|---|
| 3000 | Connected Suite |
| 3341 | Interchange console |
| 5173 | Micro Eazy PWA |
| 51214 | Interchange PGlite (`prisma dev`) |

Claim the next one in `registry.json` → `portMap` **before** writing a new entry.
