# Relay host bundle

Everything needed to run the **SQL relay** and the **CRB relay** on a server,
extracted from `connected-suite` so the host needs no checkout of the main repo.

Zip this folder, copy it to the box, unzip, and follow the steps below in order.

---

## 0 · Why there are two relays, and why they are not interchangeable

They solve opposite problems and have **different host requirements**. A machine
that can run one very often cannot run the other.

| | SQL relay (`8787`) | CRB relay (`8788`) |
|---|---|---|
| **Problem** | Micromart's SQL Server at `100.72.35.56,4230` is in Tailscale CGNAT space and has **no internet route at all** | Metropol is reachable by anyone, but **answers only registered source IPs** |
| **Host must have** | a tailnet route to `100.72.35.56` | a public egress IP on Metropol's whitelist |
| **Failure if wrong host** | loud — connection refused | **silent** — dropped at Metropol's edge, no response, no `api_code`, looks exactly like the bureau being down |
| **Dependencies** | Node + npm + `npm install` | Node only — one file, zero dependencies |

> **The asymmetry that catches people:** Tailscale Funnel changes where a relay
> can be **reached**. It does not change where the relay **calls from**.
> Funnelling the CRB relay on an unwhitelisted box does not whitelist it.

---

## 1 · Decide what this box can run

Run this **first**, on the box. It is not a formality — it decides the rest.

```powershell
powershell -ExecutionPolicy Bypass -File check-host.ps1
```

It ends with a verdict for each relay. Install only what it approves.

If it says *"do NOT run the SQL relay here"* and the interface it names is not a
Tailscale adapter, the box has no tailnet route. That is not fixable in config —
either repair Tailscale on it, or host the SQL relay on a node that has the route.

---

## 2 · Layout on the server

Unzip anywhere the service account can read — `C:\relay` is fine. **Keep the
structure exactly as-is.** The imports are relative, and both relays resolve
`.env` from the bundle root:

```
C:\relay\
├── package.json
├── .env                       ← you create this from .env.example
├── README.md
├── check-host.ps1
├── install-services.ps1
├── scripts\
│   ├── sql-relay.ts           ← needs the src\ tree + node_modules
│   └── crb-relay.mjs          ← standalone; runs on its own
└── src\lib\enterprise\
    ├── connections.ts
    ├── mssql.ts
    └── relay.ts
```

**`.env` goes beside `package.json`, never inside `scripts\`.** `sql-relay.ts`
loads it via dotenv relative to the working directory; `crb-relay.mjs` reads
`../.env` relative to itself. Both land on the bundle root — but only if you keep
the folders as they are.

If you are running **only the CRB relay**, you can delete `src\`, `package.json`
and `scripts\sql-relay.ts`. `crb-relay.mjs` imports nothing but `node:http`,
`node:crypto` and `node:fs`, which is deliberate — it is meant to run on boxes
that have no business growing a JavaScript toolchain.

---

## 3 · Install

**CRB relay only:** nothing to install. Node is enough — you do not even need
this whole bundle, just `scripts\crb-relay.mjs` and a `.env` one level above it.

**SQL relay:** in the bundle root,

```powershell
npm install

powershell -ExecutionPolicy Bypass -File check-host.ps1

```

`package-lock.json` is included, so this installs the exact versions that were
smoke-tested (78 packages).

**If the box has no route to the npm registry** — likely on a locked-down
production server — use `relay-host-offline.zip` instead, which ships
`node_modules` prebuilt and needs no install at all.

> **The offline bundle is Windows x64 only.** It contains
> `node_modules\@esbuild\win32-x64\esbuild.exe` (11 MB of the 17 MB), pulled in
> by `tsx`. On any other platform or architecture, run `npm install` normally
> instead. Nothing else in the tree is platform-specific — `mssql` talks TDS
> through `tedious`, which is pure JavaScript.

---

## 4 · `.env`

```powershell
copy .env.example .env
notepad .env
```

Fill in only what this box runs. The two secrets must match Vercel **byte for
byte** — generate once, use the same value on both sides:

```powershell
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

`SERVICESUITE_RELAY_SECRET` under 32 characters makes the SQL relay refuse to
start. That is on purpose: an unauthenticated relay is an open SQL proxy on the
public internet.

**`SERVICESUITE_CONN_MICROMART` is the database password and it stays on this
box.** It is not set on Vercel and does not need to be — with a relay configured,
`isOrgConfigured()` is satisfied by the relay itself.

---

## 5 · Publish — the port trap

Funnel offers **only 443, 8443 and 10000**. Two relays on one node both default
to 443, and the second command **silently displaces the first**.

**Two relays on different nodes** — no conflict, both use 443:

```powershell
tailscale funnel --bg 8787      # on the SQL host  ->  https://<host>.tail10c441.ts.net
tailscale funnel --bg 8788      # on the CRB host  ->  https://<host>.tail10c441.ts.net
```

**Both relays on the same node** — split them:

```powershell
tailscale funnel --bg 8788                 # ->  https://<host>.tail10c441.ts.net
tailscale funnel --bg --https=8443 8787    # ->  https://<host>.tail10c441.ts.net:8443
```

Then **always** confirm both survived:

```powershell
tailscale funnel status
```

If only one mapping is listed, the second overwrote the first.

> **If this box has no Tailscale** and is an IIS server with working inbound 443,
> reverse-proxying `127.0.0.1:8787` / `:8788` from IIS (ARR + URL Rewrite) works
> just as well and gives you a real domain. Only inbound matters here — it does
> not affect the CRB relay's egress address either way.

> **Never set an exit node on the CRB relay host.** Tailscale does not change
> your egress by default, but an exit node would — and the egress IP is the
> entire reason that relay exists. It would break the whitelist silently.

---

## 6 · Make it survive a reboot

```powershell
# as Administrator, with only what check-host.ps1 approved
powershell -ExecutionPolicy Bypass -File install-services.ps1 -Crb
powershell -ExecutionPolicy Bypass -File install-services.ps1 -Sql -Crb
```

Logs land in `logs\`. Read the CRB relay's boot line — it prints the public IP it
actually egresses from and says whether that address is whitelisted.

Funnel config persists in tailscaled state across reboots, so you do not re-run
section 5. Do check that the **Tailscale service itself** is set to automatic.

**Then reboot the box and confirm both come back.** That is the only real test.

---

## 7 · Vercel

Set these on the Vercel project (Production scope), then **redeploy once** — env
vars are snapshotted into a deployment. After that, restarting a relay never
needs a redeploy.

```
SERVICESUITE_RELAY_URL     = https://<sql-host>.tail10c441.ts.net
SERVICESUITE_RELAY_SECRET  = <matches this box>
CRB_RELAY_URL              = https://<crb-host>.tail10c441.ts.net
CRB_RELAY_SECRET           = <matches this box>
```

Include the `:8443` in the URL if you used the split in section 5.

**Do not paste a `100.x.x.x` address into Vercel.** It works from any machine on
the tailnet, so it tests green from a laptop, and is unroutable from Vercel. That
is the quietest failure in this whole path.

---

## 8 · Verify, from the main repo

```bash
npm run test:relay        # SQL: liveness, then a real signed read
npm run test:crb:prod     # CRB: a real bureau call through the relay
```

Both are outside-in tests using the same client code Vercel uses, so a pass means
**the deployment** works — not just your workstation.

Expect the SQL relay's first start to sit for 8–20 seconds warming the pool. That
is deliberate: it absorbs the cold TDS handshake at boot rather than on the first
screen someone opens.

---

## 9 · Troubleshooting

| Symptom | Meaning |
|---|---|
| `502`, empty body, `Unexpected end of JSON input` | Funnel is up and correct; **nothing is listening** on that port on that box. Note `127.0.0.1` is per-machine — running the relay on your laptop does nothing for a funnel on the server. |
| `401 Unauthorised` at the signed-read step | Reachable and published; the two halves disagree on the secret. Compare byte for byte. |
| Relay exits immediately on start | `SERVICESUITE_RELAY_SECRET` missing or under 32 chars, or `.env` is not where the process is looking — check NSSM's `AppDirectory`. |
| `test:relay` passes, live site still amber | Vercel was not redeployed after the env var change. |
| Bureau calls fail with no error and no `api_code` | The CRB relay is on a box whose egress is not whitelisted, or an exit node changed its egress. Read the relay's boot line. |
| `tailscale funnel status` shows one mapping, you set two | The second displaced the first. Use `--https=8443` for one of them. |

---

## Known state — 28 Aug 2026

Recorded because the which-box question has already been guessed wrong once.

| Node | Verified | Verdict |
|---|---|---|
| `salesmaster` — the IIS box | `check-host.ps1`: Metropol `22225` **open**; public egress **`102.214.69.233`**, on the form; `100.72.35.56,4230` **reachable via Tailscale**; Funnel on | **Runs BOTH.** Needs the 443/8443 split |
| `lms` — `100.92.236.116` | tailnet member; Funnel was configured 443 → `8787` | Superseded — turn that funnel off |
| `services` — `100.72.35.56` | Micromart's SQL Server itself | destination, not a relay host |
| `arch-bishop` — workstation | stale Funnel 443 → `8787`, nothing behind it | run `tailscale funnel --https=443 off` |

`salesmaster` egresses `102.214.69.233` over the OpenVPN TAP adapter
(`tap720e4659-e4`) and reaches SQL over Tailscale — two different paths on one
box, which is exactly why it can host both relays. Tailscale was installed here
on 28 Aug 2026; before that it had no tailnet route and the SQL test failed.

`crb-relay.mjs` also records that `services` egresses `102.210.148.124`, which is
**not** on the whitelist form — same site, same /24, wrong host. Do not infer
entitlement from the subnet.
