-- READ-ONLY
/* ============================================================================
   00 · PREVIEW THE NEXT PENALTY RUN                                 READ-ONLY

   What the 01:01 job will do on its next run, as the database stands right
   now. Changes nothing. Run it before and after every other script in this
   folder, and once more in the evening before the run.

   It mirrors sp_GeneralRolloverService's own selection, and it notices whether
   script 01 has been installed (with 01, the product start date also limits
   the backlog; without it, it does not).

   Figures assume balances do not change before the run. Customers who pay
   during the day drop out or get a smaller penalty.
   ==========================================================================*/
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;   -- no shared locks on the live heaps
GO

-- Temp tables from an earlier run in the same SSMS window (this script or another
-- in this folder) break the next compile, so clear them in a batch of their own.
DROP TABLE IF EXISTS #next, #plan, #cand, #chosen, #ledger, #todo;
GO

DECLARE @RunAt DATETIME = DATEADD(MINUTE, 61, CAST(CAST(GETDATE() AS DATE) AS DATETIME));
IF @RunAt <= GETDATE() SET @RunAt = DATEADD(DAY, 1, @RunAt);

DECLARE @Fixed BIT = CASE WHEN OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_GeneralRolloverService')) LIKE N'%penalty-service/01%' THEN 1 ELSE 0 END;

/* -- 1 · the run and the engine ------------------------------------------- */
SELECT @RunAt AS next_run_server_time,
       DATEDIFF(MINUTE, GETDATE(), @RunAt) AS minutes_from_now,
       CASE WHEN @Fixed = 1 THEN 'script 01 installed' ELSE 'ORIGINAL procedures (01 not installed)' END AS engine,
       CASE WHEN @Fixed = 1 THEN 'charges fill the Penalty column'
            ELSE 'charges on loans with an empty Penalty column stay INVISIBLE to the arrears/NPL reports' END AS report_effect;

/* -- 2 · every product with the penalty switched on, and whether the engine sees it */
SELECT P.EntityId, P.ID AS ProductId, P.ProductName, P.IsActive,
       P.RollOverApplication AS application_, P.RollOverStartDate AS start_date,
       P.RollOverGracePeriod AS grace_days, P.RollOverValueType AS value_type, P.RollOverValue AS value_,
       CASE WHEN ISNULL(P.RollOverApplication, 0) NOT IN (1, 2) THEN 'SKIPPED: no application option'
            WHEN P.RollOverStartDate IS NULL THEN 'SKIPPED: no start date'
            WHEN P.RollOverStartDate > @RunAt THEN 'SKIPPED: start date after the run'
            WHEN ISNULL(P.RollOverValue, 0) <= 0 THEN CASE WHEN @Fixed = 1 THEN 'SKIPPED: no value' ELSE 'DANGER: no value would NULL loan balances' END
            WHEN P.RollOverApplication = 2 THEN 'penalised per instalment'
            ELSE 'penalised on maturity' END AS engine_sees_it
FROM dbo.Products P
WHERE P.RollOverPenalty = 1
ORDER BY P.EntityId, P.ID;

/* -- 3 · the loans the maturity procedure will select --------------------- */
SELECT L.ID AS LoanId, L.BorrowerId, L.EntityId AS LoanEntity, P.EntityId AS ProductEntity, P.ID AS ProductId, P.ProductName,
       L.LoanBalance, L.Penalty AS PenaltyColumn,
       DATEDIFF(DAY, L.ExpectedClearDate, @RunAt) AS DaysPastDueAtRun,
       CAST(CASE WHEN P.RollOverValueType = 1 THEN (P.RollOverValue / 100) * L.LoanBalance ELSE P.RollOverValue END AS DECIMAL(18,2)) AS Penalty
INTO #next
FROM dbo.Loans L
JOIN dbo.Borrowers B ON B.ID = L.BorrowerId
JOIN dbo.Products P ON P.ID = L.ProductId
WHERE P.RollOverApplication = 1
  AND P.RollOverPenalty = 1
  AND P.RollOverStartDate <= @RunAt
  AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), L.ExpectedClearDate) < @RunAt
  AND (@Fixed = 0 OR (DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), L.ExpectedClearDate) >= P.RollOverStartDate AND P.RollOverValue > 0))
  AND L.LoanBalance > 0
  AND L.IsRolledOver = 0;

SELECT ProductEntity AS entity_, COUNT(*) AS loans_charged, COUNT(*) AS sms_sent, COUNT(DISTINCT BorrowerId) AS customers,
       SUM(LoanBalance) AS balance_kes, SUM(Penalty) AS penalty_kes, MAX(Penalty) AS largest_penalty,
       SUM(CASE WHEN DaysPastDueAtRun < 90 THEN 1 ELSE 0 END) AS days_61_89,
       SUM(CASE WHEN DaysPastDueAtRun >= 90 THEN 1 ELSE 0 END) AS days_90_plus,
       SUM(CASE WHEN PenaltyColumn IS NULL THEN 1 ELSE 0 END) AS empty_penalty_column
FROM #next GROUP BY ProductEntity
UNION ALL
SELECT NULL, COUNT(*), COUNT(*), COUNT(DISTINCT BorrowerId), SUM(LoanBalance), SUM(Penalty), MAX(Penalty),
       SUM(CASE WHEN DaysPastDueAtRun < 90 THEN 1 ELSE 0 END), SUM(CASE WHEN DaysPastDueAtRun >= 90 THEN 1 ELSE 0 END),
       SUM(CASE WHEN PenaltyColumn IS NULL THEN 1 ELSE 0 END)
FROM #next;

SELECT ProductEntity AS entity_, ProductId, ProductName, COUNT(*) AS loans, SUM(Penalty) AS penalty_kes,
       MIN(DaysPastDueAtRun) AS min_days_past_due, MAX(DaysPastDueAtRun) AS max_days_past_due
FROM #next GROUP BY ProductEntity, ProductId, ProductName ORDER BY loans DESC;

/* -- 4 · instalment procedure (products on option 2) ---------------------- */
SELECT COUNT(DISTINCT LS.LoanId) AS instalment_loans_selected
FROM dbo.LoanSchedule LS
JOIN dbo.Loans L ON L.ID = LS.LoanId
JOIN dbo.Borrowers B ON B.ID = L.BorrowerId
JOIN dbo.Products P ON P.ID = L.ProductId
WHERE P.RollOverApplication = 2 AND P.RollOverPenalty = 1 AND P.RollOverStartDate <= @RunAt
  AND LS.IsPenaltyAppled = 0
  AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), LS.ExpectedDueDate) < @RunAt
  AND (@Fixed = 0 OR (DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), LS.ExpectedDueDate) >= P.RollOverStartDate AND P.RollOverValue > 0))
  AND (LS.PrincipleToPay > 1 OR LS.InterestToPay > 1);

/* -- 5 · what this folder has changed so far ------------------------------ */
IF OBJECT_ID(N'dbo.MicroEazyPenaltyConfigLog') IS NOT NULL
    EXEC (N'SELECT ChangedAt, Script, EntityId, ProductId, ProductName, Field, OldValue, NewValue, RolledBackAt
            FROM dbo.MicroEazyPenaltyConfigLog ORDER BY Id DESC;');
IF OBJECT_ID(N'dbo.MicroEazyPenaltyBackfillLog') IS NOT NULL
    EXEC (N'SELECT COUNT(*) AS backfilled_loans, SUM(NewPenalty) AS backfilled_kes,
                   SUM(CASE WHEN RolledBackAt IS NOT NULL THEN 1 ELSE 0 END) AS rolled_back
            FROM dbo.MicroEazyPenaltyBackfillLog;');
GO
