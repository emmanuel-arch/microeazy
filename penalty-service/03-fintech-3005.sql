/* ============================================================================
   03 · MICROMART FINTECH (3005): SWITCH THE 7-DAY PENALTY ON
                                                              DRY RUN BY DEFAULT
   Requires 01.

   The three Micro Eazy products (Micro Eazy, Micro Eazy Monthly, Micro Chap
   Chap) are already set to penalise 20% of the balance after a 7-day grace, but
   they have never had a RollOverStartDate, and the engine skips undated
   products. So nothing on the fintech book has ever been penalised.

   Grace 7 means the charge lands at 01:01 on the 8th day past maturity: "more
   than 7 days late". ExpectedClearDate is a date column, so there is no
   time-of-day slippage to day 9.

   @PenaliseFrom is the first penalty day that counts (with 01 installed):
     today (the default)         forward only: loans already 8+ days late are
                                 NOT back-charged
     an earlier date             also charges loans whose 8th day fell on or after
                                 it; '2026-07-13' (the entity's creation date)
                                 charges the whole backlog. That was 15 Micro Eazy
                                 loans, KES 19,381, on 17 Sep 2026.

   @RatePercent: NULL keeps the configured 20%. Confirm the rate with Micromart
   before going live. 20% of the whole balance on day 8 is steep for a digital
   product.

   Loans that sit on the 3005 book but belong to 3002 products (migrated
   customers' old loans) follow their 3002 product's 60-day rule, not this one.

   Dry run: changes nothing, previews the options. Live: logs old values to
   dbo.MicroEazyPenaltyConfigLog, then updates the three products in one
   transaction. 99-rollback.sql puts them back.
   ==========================================================================*/
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Temp tables from an earlier run in the same SSMS window (this script or another
-- in this folder) break the next compile, so clear them in a batch of their own.
DROP TABLE IF EXISTS #next, #plan, #cand, #chosen, #ledger, #todo;
GO

DECLARE @DryRun           BIT           = 1;      -- <<< DRY RUN (1 = preview, 0 = apply)
DECLARE @PenaliseFrom     DATE          = NULL;   -- <<< NULL = today (forward only)
DECLARE @GraceDays        INT           = 7;      -- charged on day @GraceDays + 1
DECLARE @RatePercent      DECIMAL(18,2) = NULL;   -- NULL = keep the configured rate
DECLARE @ExpectedProducts INT           = 3;      -- refuses to run if 3005's penalty products are not exactly these
DECLARE @RunAt            DATETIME      = NULL;   -- NULL = the next 01:01 run

IF @RunAt IS NULL
BEGIN
    SET @RunAt = DATEADD(MINUTE, 61, CAST(CAST(GETDATE() AS DATE) AS DATETIME));
    IF @RunAt <= GETDATE() SET @RunAt = DATEADD(DAY, 1, @RunAt);
END;
IF @PenaliseFrom IS NULL SET @PenaliseFrom = CAST(GETDATE() AS DATE);

DECLARE @Fixed BIT = CASE WHEN OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_GeneralRolloverService')) LIKE N'%penalty-service/01%' THEN 1 ELSE 0 END;

SELECT P.ID AS ProductId, P.ProductName, P.IsActive,
       P.RollOverApplication AS CurrentApplication, 1 AS NewApplication,
       P.RollOverStartDate AS CurrentStart, @PenaliseFrom AS NewStart,
       P.RollOverGracePeriod AS CurrentGrace, @GraceDays AS NewGrace,
       P.RollOverValueType AS ValueType,
       P.RollOverValue AS CurrentRate, ISNULL(@RatePercent, P.RollOverValue) AS NewRate
INTO #plan
FROM dbo.Products P
WHERE P.EntityId = 3005 AND P.RollOverPenalty = 1;

SELECT @RunAt AS next_run, @PenaliseFrom AS penalise_from, @GraceDays AS grace_days, @RatePercent AS rate_override,
       CASE WHEN @Fixed = 1 THEN 'installed' ELSE 'NOT INSTALLED' END AS script_01;
SELECT * FROM #plan ORDER BY ProductId;

IF (SELECT COUNT(*) FROM #plan) <> @ExpectedProducts
   OR EXISTS (SELECT 1 FROM #plan WHERE ValueType <> 1 OR ISNULL(NewRate, 0) <= 0)
BEGIN
    RAISERROR('STOPPED: 3005 no longer has exactly the expected percentage-rate penalty products. Re-read before changing anything.', 16, 1);
    RETURN;
END;

/* -- what the next run would charge on the fintech book ------------------- */
SELECT L.ID AS LoanId, L.BorrowerId, pl.ProductId, L.LoanBalance,
       DATEADD(DAY, @GraceDays + 1, L.ExpectedClearDate) AS PenaltyDay,
       DATEDIFF(DAY, L.ExpectedClearDate, @RunAt) AS DaysPastDue,
       CAST((pl.NewRate / 100) * L.LoanBalance AS DECIMAL(18,2)) AS Penalty
INTO #cand
FROM dbo.Loans L
JOIN dbo.Borrowers B ON B.ID = L.BorrowerId
JOIN #plan pl ON pl.ProductId = L.ProductId
WHERE L.LoanBalance > 0
  AND L.IsRolledOver = 0
  AND DATEADD(DAY, @GraceDays + 1, L.ExpectedClearDate) < @RunAt;

SELECT s.Scenario, COUNT(c.LoanId) AS loans_charged_and_texted, ISNULL(SUM(c.LoanBalance), 0) AS balance_kes,
       ISNULL(SUM(c.Penalty), 0) AS penalty_kes, MIN(c.DaysPastDue) AS min_days_past_due, MAX(c.DaysPastDue) AS max_days_past_due
FROM (VALUES (1, 'as configured right now (no start date)', CAST(NULL AS DATE)),
             (2, 'with @PenaliseFrom', @PenaliseFrom),
             (3, 'whole backlog (from 2026-07-13)', CAST('2026-07-13' AS DATE))) s(Ord, Scenario, FromDate)
LEFT JOIN #cand c ON s.FromDate IS NOT NULL AND c.PenaltyDay >= s.FromDate AND s.FromDate <= @RunAt
GROUP BY s.Ord, s.Scenario
ORDER BY s.Ord;

IF @DryRun = 1
BEGIN
    PRINT 'DRY RUN: nothing changed. Set @DryRun = 0 to switch the fintech penalty on.';
    RETURN;
END;

/* -- apply ------------------------------------------------------------------ */
IF @Fixed = 0
BEGIN
    RAISERROR('STOPPED: install 01-fix-rollover-procs.sql first, or a start date of today still back-charges every late fintech loan. Nothing was changed.', 16, 1);
    RETURN;
END;

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.MicroEazyPenaltyConfigLog') IS NULL
    CREATE TABLE dbo.MicroEazyPenaltyConfigLog (
        Id           INT IDENTITY(1,1) PRIMARY KEY,
        ChangedAt    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
        ChangedBy    SYSNAME        NOT NULL DEFAULT SUSER_SNAME(),
        Script       VARCHAR(60)    NOT NULL,
        EntityId     INT            NOT NULL,
        ProductId    INT            NOT NULL,
        ProductName  NVARCHAR(200)  NULL,
        Field        VARCHAR(40)    NOT NULL,
        OldValue     NVARCHAR(100)  NULL,
        NewValue     NVARCHAR(100)  NULL,
        Reason       NVARCHAR(200)  NULL,
        RolledBackAt DATETIME2(0)   NULL
    );

INSERT dbo.MicroEazyPenaltyConfigLog (Script, EntityId, ProductId, ProductName, Field, OldValue, NewValue, Reason)
SELECT '03-fintech-3005', 3005, pl.ProductId, pl.ProductName, f.Field, f.OldValue, f.NewValue, 'fintech penalty switched on'
FROM #plan pl
CROSS APPLY (VALUES
    ('RollOverStartDate',   CONVERT(VARCHAR(10), pl.CurrentStart, 23), CONVERT(VARCHAR(10), pl.NewStart, 23)),
    ('RollOverApplication', CAST(pl.CurrentApplication AS VARCHAR(10)), CAST(pl.NewApplication AS VARCHAR(10))),
    ('RollOverGracePeriod', CAST(pl.CurrentGrace AS VARCHAR(10)),       CAST(pl.NewGrace AS VARCHAR(10))),
    ('RollOverValue',       CAST(pl.CurrentRate AS VARCHAR(30)),        CAST(pl.NewRate AS VARCHAR(30)))
) f(Field, OldValue, NewValue)
WHERE ISNULL(f.OldValue, '') <> ISNULL(f.NewValue, '');

UPDATE P
SET P.RollOverStartDate   = pl.NewStart,
    P.RollOverApplication = pl.NewApplication,
    P.RollOverGracePeriod = pl.NewGrace,
    P.RollOverValue       = pl.NewRate
FROM dbo.Products P
JOIN #plan pl ON pl.ProductId = P.ID
WHERE P.EntityId = 3005 AND P.RollOverPenalty = 1;

IF @@ROWCOUNT <> @ExpectedProducts
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('STOPPED: updated a different number of products than planned. Rolled back, nothing changed.', 16, 1);
    RETURN;
END;

COMMIT TRANSACTION;
PRINT 'APPLIED: fintech penalty on from ' + CONVERT(VARCHAR(10), @PenaliseFrom, 23) + '. Run 00-preview.sql to confirm the next run.';
GO
