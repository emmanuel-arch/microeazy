# Build log — Fri 29 Aug 2026 · 4 days to the Micromart demo

## Today's build: the Realm Switch (SME ⇄ Fintech)

One organisation, two books. Micromart Africa is EntityId 3002 (the SME book —
140k borrowers, officer-led) and Micromart Fintech is EntityId 3005 (Micro Eazy —
17,016 borrowers, fully digital). Axe is the same shape. The console has to let a
manager stand in either book and know, at a glance and without reading a word,
which one they are standing in.

The branding answer is in the logo: the Micromart mark is exactly two colours,
gold `#E6B617` and espresso `#4E4442`. Two colours, two realms.

- [ ] 1. Read the terrain — how ServiceSuite switches entity, how the console paints brand
- [x] 2. Derive the two palettes from the logo's two colours (contrast-checked)
- [x] 3. `src/lib/suite/realms.ts` — the realm registry (org -> realms, entity ids, palettes, copy)
- [x] 4. Server: read the realm cookie, resolve it, feed `--brand` from the console layout
- [x] 5. The setter — server action that writes the realm cookie
- [x] 6. `RealmSwitch.tsx` — segmented control, sliding thumb, spinner, veil transition
- [x] 7. Mount it at the top of the console; hidden for single-realm orgs
- [x] 8. Typecheck + build, then LOOK at it — screenshot both realms

## Parked (not today)

- The business-value narrative for Morris — the "what this is worth to the firm"
  half of the demo. Needs its own session.
- Problems 1-4. Only problem 5 arrived in writing.

## Done — what shipped

| File | What it is |
| --- | --- |
| `src/lib/suite/realms.ts` | The registry. Entity ids, palettes, copy. Client-safe. |
| `src/lib/suite/realm-server.ts` | Cookie read/write. Suite-scoped, like the session. |
| `src/app/api/console/realm/route.ts` | GET the books, POST to change one. |
| `src/components/shell/RealmSwitch.tsx` | The control, the slide and the veil. |
| `src/app/console/layout.tsx` | Resolves the realm; `--brand` now comes from it. |
| `scripts/verify-realms.ts` | `npm run test:realms` — 38 assertions, all passing. |

Verified: `tsc --noEmit` clean, `eslint` clean, `npm run test:realms` 38/38, and
both realms plus the veil rendered and looked at.

## What the switch does NOT do yet — say this out loud, don't let it be found

It changes the console's COLOUR, its tab title and the stored context. It does
not yet re-scope what the console READS: the native console reads Postgres,
where the Org is the tenant and entities do not exist as a concept.

The next step is real and the plumbing is already there: `lib/suite/journal.ts`
and `lib/suite/ledger.ts` both take `entityIds` and both currently hardcode
`[3002, 3005]` — the `/books`, `/desk` and `/people` surfaces would become
realm-scoped by passing `realm.entityId` instead of that default.

## Next

- [ ] Wire `realm.entityId` into the ServiceSuite-backed reads (journal, ledger, desk)
- [ ] Axe's second EntityId — needed before Axe's switch can be turned on
- [ ] The business-value narrative for Morris
