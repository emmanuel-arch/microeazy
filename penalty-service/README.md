# Penalty service: runbook

Micromart asked for the penalty service back: **3002 penalises loans more than 60 days
past due, 3005 (fintech) more than 7 days**. On 17 Sep 2026 the founder ran
`update products set RollOverApplication=1` (no `WHERE`), which queued a one-off charge
on the next nightly run. These scripts let the CEO decide what that run actually does.

Findings: [`../reports/Dormancy-And-Penalties-2026-09-11.pdf`](../reports/Dormancy-And-Penalties-2026-09-11.pdf),
corrected on 17 Sep: the job never stopped; product edits switched products off.

> **STATUS, 17 Sep 2026 ~03:00 EAT: prepared, NOT applied.** Every script was dry-run
> against the live `Serviceconnect` and passed. Afterwards the procedure hashes, product
> config and backfill count were re-read and are unchanged. The *live* code paths (the log
> writes, the product updates, the rollback's restore) have **not** been rehearsed, so
> watch the messages pane on the first real run.

## The clock

The engine is `sp_GeneralRolloverService`, run by a SQL Agent job **every night at 01:01
server time (EAT)**. Next run: **Friday 18 Sep 01:01**. Whatever is configured at 01:00 is
what happens, and the SMS go out within minutes. **They cannot be recalled.**

## What each CEO decision runs

| # | Decision | Script | Set |
|---|---|---|---|
| — | See what the next run will do | `00-preview.sql` | nothing, read-only |
| 2 | Make charges show on the arrears/NPL reports | `01-fix-rollover-procs.sql` | `@value = 0` on the DRY RUN line |
| 4 | A product save must not switch penalties off | `05-product-save-guard.sql`, then deploy the portal fix | `@value = 0` |
| 1 | How much of the 3002 backlog to charge | `02-backlog-3002.sql` | `@Option`, `@DryRun = 0` |
| 3 | Switch fintech (3005) on | `03-fintech-3005.sql` | `@PenaliseFrom`, `@RatePercent`, `@DryRun = 0` |
| 2b | Fill the column for past charges | `04-backfill-penalty-column.sql` | `@DryRun = 0` |
| — | Undo any of the above | `99-rollback.sql` | the three switches, `@DryRun = 0` |

**Run order: 00 → 01 → 05 → 02 → 03 → 04 → 00.** 02 and 03 refuse to apply without 01,
because without it a start date cannot limit the backlog.

Each script is dry run by default: open it in SSMS against `Serviceconnect`, press F5,
and read the result grids and the Messages tab. Then flip the one marked switch and run it again.

### Decision 1: the 3002 backlog (dry-run figures for Friday's run)

| `@Option` | Loans charged + SMS | Penalty (KES) | 61–89 days | 90+ days |
|---|---|---|---|---|
| as configured now (do nothing) | 3,045 | 3,562,779 | 1,182 | 1,863 |
| `ALL` (incl. the 7 undated products) | 3,082 | 3,606,072 | 1,200 | 1,882 |
| `ARREARS_ONLY` | 1,200 | 1,405,751 | 1,200 | 0 |
| `FORWARD_ONLY` | 24 | 22,411 | 24 | 0 |

Every option then charges each loan the night it passes day 61 (about 1,143 loans per 30
days). **If there is no decision by the evening, `FORWARD_ONLY` is the safe holding
position.** It can be widened later: re-running 02 with `ALL` charges the backlog on the
following night. Once `ALL` has run, it cannot be narrowed.

### Decision 3: fintech

| `@PenaliseFrom` | Loans | Penalty (KES) |
|---|---|---|
| today (default, forward only) | 5 | 7,233 |
| `'2026-07-13'` (whole backlog) | 18 | 24,539 |

The rate is 20% of the whole balance on day 8. Confirm that with Micromart; `@RatePercent`
changes it.

### Decision 2b: backfill

15,253 loans (KES 15.53M) have ledger penalties but an empty `Loans.Penalty`. **The NPL
report's penalty total rises by about KES 15M the morning after.** Tell the CEO first.

## What the scripts change, exactly

- **01** replaces `sp_GeneralRolloverService` and `_InstallmentWise`: start date limits the
  backlog, `ISNULL(Penalty,0)`, skips products with no value, one transaction (failure →
  rollback + job-step error, nobody charged), statement line without a savings row, schedule
  spread only onto instalments with an amount. Originals → `dbo.MicroEazyProcBackup`.
- **05** replaces `NewProduct` / `UpdateProduct`: accepts `@RolloverJlAccount`, and
  `UpdateProduct` keeps `RollOverApplication` / `RolloverJlAccount` when a save omits them.
  Originals → `dbo.MicroEazyProcBackup`.
- **02 / 03** update `Products` start date (and for 3005 the option, grace, rate). Every
  old value → `dbo.MicroEazyPenaltyConfigLog`.
- **04** fills `Loans.Penalty` from `CustomerStatement`. Every loan → `dbo.MicroEazyPenaltyBackfillLog`.
- 01 and 05 refuse to run if the live procedure's SHA-256 differs from the 17 Sep read.

## The portal fix (ServiceSuite-Portal, uncommitted)

Root cause: `ProductManager.GetLoanProduct` never loaded `RollOverApplication`, so the edit
form reopened with no option ticked and every save wrote NULL. It happened again live at
**02:27 on 17 Sep**, when user 9096 saved Micro Eazy (30219).

- `Models/ProductManager.cs`: loads `RollOverApplication` and `RollOverStartDate`.
- `Models/LoanProduct.cs`: `RollOverStartDate`.
- `Views/Product/New.cshtml`, `Update.cshtml`: a "Penalty start date" field.
- `Controllers/ProductController.cs`: with penalty = yes, a save needs the option, a start
  date, a grace period, a type and a value above zero. The start date is written in the same
  transaction as the save.

Builds clean (0 errors). **Install 05 before deploying it to Micromart.** The repo's current
build already sends `@RolloverJlAccount`, which Micromart's procedures reject with "too many
arguments", so without 05 no product can be saved there at all.

## After the run, the next morning

```sql
SELECT COUNT(*) loans, SUM(EffectedAmount) kes FROM ManagedLoans
WHERE TransType = 6 AND DoneBy = 101 AND DateDone >= CAST(GETDATE() AS date);
SELECT COUNT(*) sms, SUM(CASE WHEN isSent = 1 THEN 1 ELSE 0 END) sent FROM Notifications.dbo.SMS
WHERE CreatedBy = 101 AND CreateDate >= CAST(GETDATE() AS date) AND smsMessage LIKE '%penalty of KES%';
```

Then run `00-preview.sql`: the backlog should be gone and only newly late loans queued.

## Not fixed here (known)

- **The SMS promises "further penalties"**, but the engine charges each loan once. The
  product screen also offers "Recurring", which the engine ignores.
- **4,125 open loans have `IsRolledOver = NULL`** (16 months to 5½ years overdue) and can
  never be selected.
- **22 of the queued loans have no open instalment**, so their penalty raises the balance
  but not the schedule.
- **`sp_RolloverService` is the legacy engine.** Someone ran it manually on 24 Jun
  (2,760 charges). It has no application filter: do not run it.
- **The arrears report defects are unchanged**: no `LoanCleared = 0` filter, loans at
  exactly 90 days fall through, and the date pickers do nothing.
- **The unscoped update also set the option on all 32 Check off (3003) products.** It is
  harmless (their penalty is off), but the old values were never logged.
- **01 and 05 are Micromart-only.** The repo's `deploy_233*.sql` copies of the rollover
  procedures for other servers are untouched.
