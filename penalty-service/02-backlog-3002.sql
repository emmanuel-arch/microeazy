/* ============================================================================
   02 · MICROMART AFRICA (3002): HOW MUCH OF THE BACKLOG TO CHARGE
                                                              DRY RUN BY DEFAULT
   Requires 01 (without it a start date cannot limit the backlog).

   The CEO's rule is "penalise loans more than 60 days past due". 3002's
   products already say that (grace 60: charged at 01:01 on day 61). The open
   question is the loans that passed day 61 while the penalty was switched off.
   On 17 Sep 2026 that was 3,044 loans, KES 3.56M, one SMS each.

   Pick ONE in @Option:

     'ALL'           Charge every loan past day 61 that was never penalised.
                     Start date 2025-03-20, the date the older products already
                     carry. Friday: all 3,044 (1,211 at 61-89 days, 1,833 at
                     90-349 days, already in NPL).

     'ARREARS_ONLY'  Charge only loans still under 90 days past due on the run
                     date, i.e. the arrears report's window. Start date is set
                     per product to (run date - 89 + grace + 1).
                     Friday: about 1,200 loans. The 90+ backlog is never charged.

     'FORWARD_ONLY'  Charge only loans whose day 61 falls on or after
                     @ForwardFrom (default today). Nothing from the backlog;
                     from then on each loan is charged the night it passes day 61.

   Whatever the option, every later night charges each loan as it passes day 61
   (about 1,143 loans every 30 days as of 17 Sep).

   @IncludeUndatedProducts = 1 also switches on the 7 products that never had a
   start date (the 4 ZIDISHA BIASHARA products, 3 WEEKS, 9 WEEKS, SCHOOL FEE -4
   MONTH), on the same terms. Set it to 0 to leave them off.

   Dry run (default): changes nothing. Prints all three options side by side,
   then the per-product plan for @Option if you set one.
   Live: logs every old value to dbo.MicroEazyPenaltyConfigLog, then updates
   RollOverStartDate on 3002's penalty products in one transaction.
   99-rollback.sql puts the old dates back.
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

DECLARE @DryRun                 BIT         = 1;      -- <<< DRY RUN (1 = preview, 0 = apply)
DECLARE @Option                 VARCHAR(20) = NULL;   -- <<< 'ALL' | 'ARREARS_ONLY' | 'FORWARD_ONLY'
DECLARE @ForwardFrom            DATE        = NULL;   -- FORWARD_ONLY: NULL = today
DECLARE @IncludeUndatedProducts BIT         = 1;
DECLARE @RunAt                  DATETIME    = NULL;   -- NULL = the next 01:01 run
DECLARE @AllFrom                DATE        = '2025-03-20';

IF @RunAt IS NULL
BEGIN
    SET @RunAt = DATEADD(MINUTE, 61, CAST(CAST(GETDATE() AS DATE) AS DATETIME));
    IF @RunAt <= GETDATE() SET @RunAt = DATEADD(DAY, 1, @RunAt);
END;
IF @ForwardFrom IS NULL SET @ForwardFrom = CAST(GETDATE() AS DATE);

DECLARE @Fixed BIT = CASE WHEN OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_GeneralRolloverService')) LIKE N'%penalty-service/01%' THEN 1 ELSE 0 END;

IF @Option IS NOT NULL AND @Option NOT IN ('ALL', 'ARREARS_ONLY', 'FORWARD_ONLY')
BEGIN
    RAISERROR('STOPPED: @Option must be ALL, ARREARS_ONLY or FORWARD_ONLY. Nothing was changed.', 16, 1);
    RETURN;
END;

SELECT @RunAt AS next_run, @Option AS option_, @IncludeUndatedProducts AS include_undated,
       CASE WHEN @Fixed = 1 THEN 'installed' ELSE 'NOT INSTALLED - ARREARS_ONLY/FORWARD_ONLY would not limit anything yet' END AS script_01;

/* -- the products, and the start date each option gives them -------------- */
SELECT P.ID AS ProductId, P.ProductName, P.IsActive, P.RollOverGracePeriod AS Grace,
       P.RollOverStartDate AS CurrentStart,
       @AllFrom AS AllStart,
       DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0) - 89, CAST(@RunAt AS DATE)) AS ArrearsStart,
       @ForwardFrom AS ForwardStart
INTO #plan
FROM dbo.Products P
WHERE P.EntityId = 3002
  AND P.RollOverPenalty = 1
  AND P.RollOverApplication = 1
  AND (P.RollOverStartDate IS NOT NULL OR @IncludeUndatedProducts = 1);

/* -- every loan any option could select ----------------------------------- */
SELECT L.ID AS LoanId, L.BorrowerId, P.ID AS ProductId, L.LoanBalance,
       DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), L.ExpectedClearDate) AS PenaltyDay,
       DATEDIFF(DAY, L.ExpectedClearDate, @RunAt) AS DaysPastDue,
       CAST(CASE WHEN P.RollOverValueType = 1 THEN (P.RollOverValue / 100) * L.LoanBalance ELSE P.RollOverValue END AS DECIMAL(18,2)) AS Penalty
INTO #cand
FROM dbo.Loans L
JOIN dbo.Borrowers B ON B.ID = L.BorrowerId
JOIN dbo.Products P ON P.ID = L.ProductId
JOIN #plan pl ON pl.ProductId = P.ID
WHERE L.LoanBalance > 0
  AND L.IsRolledOver = 0
  AND P.RollOverValue > 0
  AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), L.ExpectedClearDate) < @RunAt;

;WITH hits AS (
    SELECT v.Ord, c.*
    FROM #cand c
    JOIN #plan pl ON pl.ProductId = c.ProductId
    CROSS APPLY (VALUES
        (1, CASE WHEN pl.CurrentStart <= @RunAt AND (@Fixed = 0 OR c.PenaltyDay >= pl.CurrentStart) THEN 1 ELSE 0 END),
        (2, CASE WHEN c.PenaltyDay >= pl.AllStart THEN 1 ELSE 0 END),
        (3, CASE WHEN c.PenaltyDay >= pl.ArrearsStart THEN 1 ELSE 0 END),
        (4, CASE WHEN c.PenaltyDay >= pl.ForwardStart AND pl.ForwardStart <= @RunAt THEN 1 ELSE 0 END)
    ) v(Ord, Hit)
    WHERE v.Hit = 1
)
SELECT s.Scenario,
       COUNT(h.LoanId) AS loans_charged_and_texted,
       ISNULL(SUM(h.LoanBalance), 0) AS balance_kes,
       ISNULL(SUM(h.Penalty), 0) AS penalty_kes,
       SUM(CASE WHEN h.DaysPastDue < 90 THEN 1 ELSE 0 END) AS days_61_89,
       SUM(CASE WHEN h.DaysPastDue >= 90 THEN 1 ELSE 0 END) AS days_90_plus,
       MAX(h.DaysPastDue) AS oldest_days_past_due
FROM (VALUES (1, 'as configured right now'), (2, 'ALL'), (3, 'ARREARS_ONLY'), (4, 'FORWARD_ONLY')) s(Ord, Scenario)
LEFT JOIN hits h ON h.Ord = s.Ord
GROUP BY s.Ord, s.Scenario
ORDER BY s.Ord;

IF @Option IS NULL
BEGIN
    PRINT 'Preview only. Set @Option to the CEO''s choice to see the per-product plan; set @DryRun = 0 as well to apply it.';
    RETURN;
END;

/* -- the plan for the chosen option ---------------------------------------- */
SELECT pl.ProductId, pl.ProductName, pl.IsActive, pl.Grace, pl.CurrentStart,
       CASE @Option WHEN 'ALL' THEN pl.AllStart WHEN 'ARREARS_ONLY' THEN pl.ArrearsStart ELSE pl.ForwardStart END AS NewStart
INTO #chosen
FROM #plan pl;

SELECT ch.ProductId, ch.ProductName, ch.IsActive, ch.Grace, ch.CurrentStart, ch.NewStart,
       CASE WHEN ch.CurrentStart = ch.NewStart THEN 'unchanged' ELSE 'CHANGES' END AS change_,
       COUNT(c.LoanId) AS loans_next_run, ISNULL(SUM(c.Penalty), 0) AS penalty_kes
FROM #chosen ch
LEFT JOIN #cand c ON c.ProductId = ch.ProductId AND c.PenaltyDay >= ch.NewStart AND ch.NewStart <= @RunAt
GROUP BY ch.ProductId, ch.ProductName, ch.IsActive, ch.Grace, ch.CurrentStart, ch.NewStart
ORDER BY loans_next_run DESC, ch.ProductId;

IF @DryRun = 1
BEGIN
    PRINT 'DRY RUN: nothing changed. Set @DryRun = 0 to apply ' + @Option + '.';
    RETURN;
END;

/* -- apply ------------------------------------------------------------------ */
IF @Fixed = 0
BEGIN
    RAISERROR('STOPPED: install 01-fix-rollover-procs.sql first. Without it the new start dates would not limit the backlog, and every charge would stay invisible to the reports. Nothing was changed.', 16, 1);
    RETURN;
END;

DECLARE @expected INT = (SELECT COUNT(*) FROM #chosen WHERE CurrentStart IS NULL OR CurrentStart <> NewStart);

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
SELECT '02-backlog-3002', 3002, ch.ProductId, ch.ProductName, 'RollOverStartDate',
       CONVERT(VARCHAR(10), ch.CurrentStart, 23), CONVERT(VARCHAR(10), ch.NewStart, 23),
       'backlog option ' + @Option
FROM #chosen ch
WHERE ch.CurrentStart IS NULL OR ch.CurrentStart <> ch.NewStart;

UPDATE P
SET P.RollOverStartDate = ch.NewStart
FROM dbo.Products P
JOIN #chosen ch ON ch.ProductId = P.ID
WHERE P.EntityId = 3002
  AND P.RollOverPenalty = 1
  AND (P.RollOverStartDate IS NULL OR P.RollOverStartDate <> ch.NewStart);

IF @@ROWCOUNT <> @expected
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('STOPPED: updated a different number of products than planned (someone edited a product mid-run?). Rolled back, nothing changed.', 16, 1);
    RETURN;
END;

COMMIT TRANSACTION;
PRINT 'APPLIED ' + @Option + ' to ' + CAST(@expected AS VARCHAR(10)) + ' product(s). Run 00-preview.sql to confirm the next run.';
GO
