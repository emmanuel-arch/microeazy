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
| 12 | `12-rollback-wrong-dormancy.sql` | Returns the 175 customers the 11 Sep run moved on maturity instead of settlement | ~35,000 | n/a — it *is* the reversal |
| 13 | `13-fix-dormancy-clock.sql` | Replaces the procedure so the 60-day clock runs from settlement, not maturity | — | yes |
| 16 | `16-fintech-into-collectbox.sql` | Feeds 3005 into `CollectBox.dbo.CollectionTracker` inside Micromart's own run, so Fintech cases show in CallBox | ~165 cases | yes (`16-17-ROLLBACK-collectbox-feed.sql`) |
| 17 | `17-fintech-in-callbox-lists.sql` | **Optional.** CallBox's *Not reachable* list and overall dashboard count 3005 for Micromart logins | — | yes (same file) |
| 18 | `18-disbursement-sms-paybill.sql` | **Urgent.** The Fintech disbursement SMS names 3002's paybill (4038021); one literal becomes 4329635. 18.0b lists payments to reconcile | — | yes (`18-19-ROLLBACK-comms-centre.sql`, R1b) |
| 19 | `19-comms-centre-sms-templates.sql` | Reminders and the disbursement SMS become editable from the Lending Console (Comms › Reminders / Templates); Geoffrey's 1-4-8-10-13 arrears ladder seeded | — | yes (same rollback, R1–R4) |

### The dormancy clock was wrong, and 12 + 13 fix it

Script 10 measured the 60 days from `Loans.ExpectedClearDate` — when a loan was
*due* to finish. Micromart's rule is that it runs from when the customer actually
finished: the day `LoanCleared` became 1, the day their OLB reached 0. For a
customer who paid on time those dates are days apart. For an NPL customer who ran
two years late and then settled, they are years apart — so the job read the
delinquency itself as evidence of dormancy.

The 11 Sep 02:34 run moved 500 customers. **175 of them had settled within the
last 60 days**; one cleared a 2022 loan the previous afternoon and was moved that
night. Run 12 to put those 175 back, then 13 to stop it recurring. The 02:30 job
calls the procedure by name, so installing 13 is all the next run needs.

`Loans.DateCleared` is not the fix — it is NULL on all 344,332 rows in the book.
The corrected procedure derives the settlement date from `CustomerStatement`:
per loan, the last `TransactedDate` at which `LoanBalance` read 0.

Both scripts default to a dry run and both compile clean against the live server.
Full analysis: [`reports/Dormancy-And-Penalties-2026-09-11.pdf`](../reports/Dormancy-And-Penalties-2026-09-11.pdf).

### Fintech on the collection tracker (16, 17)

Micromart's CallBox shows a case only when its `CollectionTracker` row carries an
amount (`Amounttopay > 100`), and that amount is written by one procedure,
`sp_GeneralCollectionTrackerbooks`, which feeds **3002 only**. It runs every few
minutes, and each of its six generators opens with a reset that is not scoped to an
entity. So any Fintech amount written from outside, including the ConnectDesk bridge's
188 rows of 4 Oct, is zeroed by the next run. On 6 Oct all 1,690 Fintech rows on the
tracker read `Amounttopay = 0`.

**Never call the generators a second time with 3005.** The second call's reset
zeroes the main book's floor.

`16` adds `sp_MicroEazy_FeedFintechToCollectBox`, which runs the same six windows for
3005, and inserts four lines into Micromart's master. The feed then runs inside their
run: after their 3002 generators and before their post-steps. Micromart's own 01:30
run (`CollectBox.dbo.CollectionTrackerBoooksMigration`) then sorts the Fintech rows
into categories and their assigner gives them agents from `LoanCategories.Agents`,
exactly as it does for main-book rows. Branch needs nothing: CallBox only displays it,
and every 3005 borrower is in unit 129, Main Office.

Run order: 16.0 (preflight, keep it) → 16.1 → 16.2 → 16.3 (dry run, read it) →
16.4 with `@Install = 0`, then `1` → 16.6 a few minutes later. 16.5 is optional and
puts today's cases on the screens before 01:30.

Know before switching it on:

- **Commission.** `RepaymentTrigger` calls `CollectBox.dbo.PtpKnocker` on every
  payment. Once a Fintech case carries an amount, its payments credit the assigned
  agent in `PayedAmount` at the band's rate. Today they credit nobody.
- **Same agents.** Fintech cases go to the agents already listed per category. A
  dedicated Fintech team would need a change to Micromart's assigner, which runs
  inside their job and is not readable from our login.
- **One more scan.** The feed reads `loanSchedule` (a 2M-row heap) once per run.
  Their generators already read it six times.

`17` is Micromart's call. Every CollectBox login is stamped 3002, and two procedures
filter on that stamp. In `sp_NotReachable_CallsList`, a Fintech case marked
*Not reachable* would vanish from CallBox. In `OverallDashboard`, the figures would
exclude Fintech.

### The SMS centre: paybill fix and editable reminders (18, 19)

**18 first, today.** `sp_DisbursmentNotifications` sends every book's "your loan has
been disbursed" SMS. Its Fintech block (added 13 Aug) says *Repay via Paybill
4038021* — Micromart Africa's paybill. Fintech's is 4329635 (the only 3005 row in
`Transactions.dbo.PAYBILLS`). On 6 Oct, 139 Fintech disbursement messages in 30 days
carried it, the latest on 5 Oct. A customer who follows it pays into the 3002
account, where `RepaymentTrigger` allocates by phone inside 3002, and the Fintech
loan ages into arrears. 18 changes that one literal by surgery on the live text (the
text is saved first), and 18.0b lists the 3002 payments made since by phones that
received the wrong SMS — reconcile those by hand.

**19 moves the wording, not the sending.** The reminders keep their job, the
procedure name and its parameters; the disbursement SMS keeps its caller. What
changes is where the words come from: `dbo.MicroEazySmsTemplate`, edited on the
Lending Console. Run order: 19.0 (keep it) → 19.1 → 19.2 → 19.3 → 19.4 with
`@Install = 0` (compiles only), then `1` → 19.5 with `@Install = 0` (prints the
procedure), then `1` → 19.6. Best after the day's 08:00 run; 19.4 records the phones
the old procedure already reminded that day so nobody is texted twice.

What a customer will notice:

- **One reminder per loan per day.** An overdue loan gets the step for its *oldest*
  unpaid due date and {Amount} is everything overdue on the loan (the old procedure
  worked per instalment and quoted one instalment's balance).
- **Geoffrey's ladder replaces day+1 and day+3:** day 1, 4, 8, 10 and 13 overdue. His
  second message was headed "4 days" twice; its text says 8 days, so it is seeded at 8.
- **Three of his five texts are over 160 characters for every customer** (day 8, 10,
  13: 166–192 with typical values) and bill as two SMS each. The console shows the
  cost on every step; the wording is his to trim.
- The penalty his day-10 and day-13 texts promise ("after 14 days") is not what the
  penalty engine does: it charges once per loan, after the product's grace period
  from **maturity** (sp_GeneralRolloverService). Worth aligning before go-live.
- "Already texted today" now counts reminders only. It counted any SMS, so the 01:01
  penalty notice or a receipt silenced that day's reminder.

The console reads and writes these tables through the relay; nothing on it sends a
reminder. Its preview calls the installed procedure with `@DryRun = 1` hard-coded.

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
