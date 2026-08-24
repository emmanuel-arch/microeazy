# Adding a system

The ecosystem is designed so a seventh system costs one registry entry and one
`git submodule add`. Everything else — `dev`, `build`, `doctor`, the README map, the port
reservation — falls out of that.

If you find yourself editing a script to accommodate a new system, the registry is
missing a field. Add the field; do not special-case the system.

---

## 1. Claim a port

Open `ecosystem/registry.json` and add your port to `portMap` **first**, before you write
anything else. Two systems defaulting to `:3000` is the single most common way a local
ecosystem stops booting, and the collision is invisible until both are running.

```json
"portMap": {
  "3000": "connected-suite",
  "3341": "interchange console",
  "5173": "pwa",
  "3400": "your-new-system"        ← claim it here
}
```

## 2. Add the registry entry

```json
{
  "id": "your-system",
  "name": "Human Readable Name",
  "purpose": "One sentence a non-engineer would recognise.",
  "path": "your-system",
  "workdir": "apps/console",        // omit unless the repo root is not the app root
  "repo": "https://github.com/emmanuel-arch/your-system",
  "branch": "main",
  "stack": "next",                  // next · vite · dotnet-worker
  "port": 3400,
  "install": "npm install",
  "dev": "npm run dev",
  "build": "npm run build",
  "start": "npm run start",
  "readyPath": "/",
  "signIn": [{ "label": "Staff", "path": "/login" }],
  "env": { "file": ".env", "example": ".env.example" },
  "database": "what it connects to, in words",
  "deploy": { "platform": "vercel", "live": false, "note": "" }
}
```

**`upstream: true`** marks a repo owned by someone else. It is pinned read-only; never
push to it. Fork it first if you need to change it.

## 3. Add the submodule

```bash
git submodule add -b main https://github.com/emmanuel-arch/your-system your-system
git commit -m "Add your-system to the ecosystem"
```

If the checkout already exists on disk with the right remote, git will adopt it in place
rather than re-cloning.

## 4. Prove it

```bash
npm run doctor your-system
npm run bootstrap your-system
npm run dev your-system
```

`doctor` is the acceptance test. If it is green on a fresh clone, the system is properly
in the ecosystem.

---

## The contract a system signs

These are the things the orchestration assumes. A system that breaks one of them will
appear to work for whoever wrote it and fail for everyone else.

**1. Its port comes from the registry, not from a hard-coded default.**
`dev.mjs` passes `PORT`; Next and Vite both honour it. If a system's own dev script pins
a port, that port and the registry must agree — the Interchange's `next dev -p 3341`
matches its registry entry and its own `INTERCHANGE_SELF_URL`, and all three are checked
by `doctor`.

**2. It boots from `.env.example` plus real secrets, and its example file is committed.**
`doctor` reports which required keys are missing by name. It never prints a value, and
neither should anything else — a setup script that echoes `DATABASE_URL` is one
screen-share away from being an incident.

**3. Secrets live in the system, never in the meta-repo.**
The meta-repo's `.gitignore` refuses `.env` outright. Per-system secrets belong in that
system's own ignored env file, or in its deployment platform.

**4. `npm run build` is honest.**
It exits non-zero on failure. `run.mjs` propagates that, so a broken tree cannot go green.

**5. It owns its own database lifecycle.**
If it needs a local database, that is a `preDev` step in its registry entry — the way the
Interchange starts PGlite via `npx prisma dev` before the console comes up. Do not expect
a human to have run something first.

**6. It does not import across submodule boundaries.**
Two systems share code by publishing a package, not by reaching into
`../other-system/src`. A relative import across a submodule boundary compiles on a
developer's machine and fails in every deployment, because no deployment checks out the
sibling.

---

## Keeping the pins honest

The meta-repo records *which commit of each system constitutes a working ecosystem*. That
is its whole job, and it only works if the pointers are committed.

```bash
npm run sync                     # pull every submodule to its remote tip
git add -A && git commit -m "Bump ecosystem pointers"
```

`doctor` flags a submodule sitting off its pinned commit with `!`. That state is fine
while you are working and wrong once you push — it is exactly the condition under which
"works on my machine" is literally true and useless to anyone else.
