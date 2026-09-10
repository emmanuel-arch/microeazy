# Fintech migration — runbook

Cleaning up the 2 August 2026 migration of Micromart Africa (**3002**) customers to
Micromart Fintech (**3005**), locking the door behind it, and starting the service
that keeps it that way.

Findings and reasoning: [`../reports/The-Fintech-Split-2026-09-08.pdf`](../reports/The-Fintech-Split-2026-09-08.pdf)

Every figure in these scripts was read live from `Serviceconnect` on
100.72.35.56,4230 on **8 September 2026** through the read-only SQL relay.

> **STATUS as of 10 September 2026 — these scripts HAVE been run.** Verified live:
> scripts 01–07 were applied on 8 Sep (backup tables 16:13–16:25, identity-lock
> trigger 16:55, 0 truncated PINs remaining), and 10.1/10.2 installed at 17:08.
> **Do not re-run 02 or 03** — a second restamp would move rows that are already
> on 3005. The dormancy job itself has moved nobody yet; see the note below.

> **The nightly job was failing (fixed in this repo, not yet redeployed).** The
> 02:30 run aborted on 9 and 10 Sep with error 2628: `Mails.Subject` is
> `varchar(50)` and the subject line was 53 characters. `XACT_ABORT` rolled the
> whole transaction back each time, so nothing moved and nothing is half-done.
> Section 10.2 now carries a 43-character subject — **re-run 10.2 alone** (it is
> `CREATE OR ALTER`) to pick up the fix.

---

## Before you start

1. **Take a full backup of `Serviceconnect`.** Scripts 01–07 are reversible
   through `ROLLBACK.sql`, but only while the `FintechRestamp_*` and
   `FintechRemediationBackup_*` tables still exist. The backup is the floor
   under that.
2. Run `00-preflight.sql` and **keep the output**. Every later script asserts
   against those numbers. If one has moved a long way from the value in the
   comment beside it, stop and re-read rather than pressing on.
3. Run everything in SSMS against `Serviceconnect`, one script at a time,
   reading the messages pane between each.

---

## Run order

| # | Script | Does | Rows | Reversible |
|---|---|---|---|---|
| 00 | `00-preflight.sql` | Read-only assertions | — | n/a |
| 01 | `01-fix-destination.sql` | Enables Geoffrey (9098), moves him and 9096 to Main Office (129) | 2 | yes |
| 02 | `02-restamp-children.sql` | Restamps the orphaned ledger rows onto 3005 | ~3,518,382 | yes |
| 03 | `03-reparent-borrowers.sql` | All 3005 borrowers to unit 129, off their ROs | ~17,022 | yes |
| 04 | `04-merge-duplicates.sql` | Merges 143 duplicate records; **reports 58 for a human** | ~143 | yes |
| 05 | `05-hard-lock.sql` | The identity lock on `Borrowers` | — | yes |
| 06 | `06-fix-sp-restBorrowerPin.sql` | Removes the hard-coded `3002` from the PIN-reset SMS | — | yes |
| 07 | `07-repair-broken-pins.sql` | Clears 40 truncated BCrypt hashes | 40 | yes |
| 10 | `10-dormancy-service.sql` | Installs the log, the procedure and the daily job | — | yes |
| 11 | `11-move-one-customer.sql` | Installs the **manual** one-customer move. Not part of the sequence — run it whenever you need to move somebody by hand | — | n/a |

### Moving one customer by hand

`11-move-one-customer.sql` installs `sp_MicroEazy_MoveCustomerToFintech` — the
same move as the nightly job, for one customer you name, without the 60-day
clock. Dry run is the default:

```sql
EXEC dbo.sp_MicroEazy_MoveCustomerToFintech @PhoneNumber = '254719112304';
EXEC dbo.sp_MicroEazy_MoveCustomerToFintech @PhoneNumber = '254719112304', @DryRun = 0;
```

Accepts `@BorrowerId`, `@PhoneNumber` or `@NationalID` — exactly one, and it
refuses an identifier that matches more than one active borrower. It checks the
destination the same way the nightly job does, refuses an identity that already
exists on the other book (with the message script 05 would have thrown, but
before doing any work), and **refuses a customer with an open loan** unless you
pass `@AllowOpenLoans = 1` — the same reasoning that keeps the 58 out of script
04. Both paths log to `MicroEazyDormancyLog`, so it stays the whole story.

### Gates that actually matter

- **03 requires 01.** It refuses to run if Geoffrey is still disabled or still in
  unit 1 — otherwise you would park 17,022 customers on a dead account.
- **05 requires 04.** It refuses to install while active duplicate identities
  remain, and prints the ones still in the way. That includes the 58 below.
- **10 requires 01.** The procedure halts on the same check every run, not just
  at install, so the job cannot quietly start filing customers under a disabled
  user six months from now.

Scripts 02 and 03 can run in either order. 02 is the long one; start it first
if you want the rest of the evening back.

---

## The 58 that need a person, not a script

`04-merge-duplicates.sql` section 4.3 prints them. These are customers who exist
on both books **and have an open loan on the 3002 side** — 58 of the 201
duplicate records.

The script does not touch them, deliberately. Moving a live loan between books
is an accounting event: the balance leaves one portfolio and joins another, and
the customer changes collections queue. That is a decision for Geoffrey, not a
side effect of a cleanup.

The usual answer is to leave them alone. Let the loan run to term on 3002; once
it clears and 60 days pass, the dormancy service moves the customer for you.
That is the path it exists to provide, and it is why 04 and 10 are not the same
script.

Until they are resolved, `05-hard-lock.sql` will not install. That is the
intended pressure: the lock is a promise the data has to be able to keep.

---

## What the SQL cannot do

**BCrypt cannot be computed in T-SQL.** `Borrowers.UssdPin` and
`MobileAppPassword` are BCrypt hashes, so a SQL Agent job cannot mint a working
credential — and writing a plain number into those columns would reproduce
exactly the defect `07` exists to clear (`BCrypt.Verify` throws on a non-hash,
which becomes a 500, which the customer sees as "technical problems").

So `10-dormancy-service.sql` sets the PIN to `NULL` and the message tells the
customer to dial `*483*490#`, where the USSD service's existing set-your-PIN
screen takes over. No PIN travels by SMS, which is also the better answer.

**If you want the message to carry a pre-set PIN, the service has to be the .NET
worker rather than a SQL Agent job.** That is the one thing the SQL Agent option
cannot do, and it is worth knowing before the first run rather than after.

---

## The application work — now done, see [`APP-FIXES.md`](APP-FIXES.md)

The four app-side defects found in the same investigation are fixed on disk,
typechecked and built. They are **not deployed** — `git` refuses to run in those
repos on this machine (a pre-existing ownership problem), so shipping is yours.

| | Was | Now |
|---|---|---|
| **OTP 400** | The live bundle sends `lenderSlug: ""`; `??` does not catch an empty string, so twelve borrower routes answered 400 | Client default fixed, plus `PORTAL_DEFAULT_LENDER_SLUG` server-side so a stale handset bundle cannot take the portal down |
| **No SMS** | `hasSmsProvider` false → `delivered: false`, no code ever sent | New ServiceSuite outbox path writes to `Notifications.dbo.SMS` with `EntityId 3005`, so the code arrives under **Micromart's** sender ID. **Needs the relay armed for writes.** |
| **Wrong backend** | `pwa.servicesuitecloud.com` calls `live.testapps.co.ke` with `EntityId: 7` | Repointed to `micromartafrica.co.ke`, verified in the built bundle. Plus a storage realm guard, because this is a backend swap on installed devices |
| **One book only** | Four screens carried their own `const entityId = "3002"` and never read the env at all, so no Fintech customer could sign in | The PWA now serves **both** books: it looks a customer up across 3002 and 3005, scopes the session to the one they are on, refuses when they are on both, and offers registration when neither |
| **USSD 500s** | No exception handler; PIN read and written with no entity predicate; the log writer collided between concurrent sessions | Outermost catch, entity resolved once and threaded down, PIN writes refuse rather than guess, log writer locked. Builds clean |
| **Demo account** | Believed unwired | Sign-in was already wired and was blocked only by the OTP fault. Borrower **170497** is usable today; [`08-demo-account.sql`](08-demo-account.sql) makes a separate one |

One thing remains genuinely unverified: `ServiceSuite/Controllers/ReportsController.cs`
is ACL-locked to another account on this machine and could not be read. It should
not need changing — script 02 fixes the leak in the data — but nobody has looked.

And confirm before deploying the USSD service: the 2 September channel analysis
describes the dial string as `*384*NNNN#`, and you dial `*483*490#`. Those are
different service codes.

---

## Undoing it

`ROLLBACK.sql`. Read its header first — the sections are independent, they run
newest-change-first, and they must be run in the order given. It drops the
identity lock before anything else, because restoring the duplicates is the one
thing the lock is built to refuse.
