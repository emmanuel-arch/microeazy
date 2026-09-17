/* ============================================================================
   04 · BACKFILL THE PENALTY COLUMN FROM THE LEDGER            DRY RUN BY DEFAULT

   Loans.Penalty is what the arrears and NPL reports print. The old procedures
   wrote Penalty = Penalty + amount, and NULL + amount is NULL, so on 17 Sep
   2026 15,253 loans (14,862 on 3002, 391 on 3005) had KES 15.53M of penalties
   in CustomerStatement and nothing in the column. The money was charged; only
   the reporting column is behind. No customer balance, schedule or SMS is
   touched here.

   Wherever the column IS filled it matches the ledger exactly (0 mismatches on
   17 Sep), so the ledger total is the right figure to write.

   Expect the NPL report's penalty total to rise by about KES 15M the morning
   after. Warn the CEO before, not after. Only 3 of these loans are under 90
   days, so the arrears report barely moves. Script 01 is what fills the
   column for new charges.

   Live: writes in committed batches of @BatchSize, stops at @MaxLoans, and logs
   every loan to dbo.MicroEazyPenaltyBackfillLog. 99-rollback.sql empties them
   again. Re-running is safe: it only ever fills a column that is still NULL.
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

DECLARE @DryRun    BIT = 1;        -- <<< DRY RUN (1 = preview, 0 = write)
DECLARE @BatchSize INT = 2000;
DECLARE @MaxLoans  INT = 20000;    -- ceiling for one run; 15,253 qualified on 17 Sep 2026

/* one pass over the 3.5M-row CustomerStatement heap */
SELECT cs.LoanId, SUM(cs.Amount) AS LedgerPenalty, COUNT(*) AS LedgerRows
INTO #ledger
FROM dbo.CustomerStatement cs WITH (NOLOCK)
WHERE cs.TransType = 1 AND cs.Narration IN ('Late Payment Penalty', 'Rollover Penalty')
GROUP BY cs.LoanId;

SELECT IDENTITY(INT, 1, 1) AS RowNo, L.ID AS LoanId, L.EntityId, lg.LedgerPenalty, lg.LedgerRows,
       DATEDIFF(DAY, L.ExpectedClearDate, GETDATE()) AS DaysPastDue, L.LoanCleared
INTO #todo
FROM dbo.Loans L
JOIN #ledger lg ON lg.LoanId = L.ID
WHERE L.Penalty IS NULL AND lg.LedgerPenalty > 0
ORDER BY L.ID;

SELECT EntityId,
       COUNT(*) AS loans_to_fill, SUM(LedgerPenalty) AS kes,
       SUM(CASE WHEN DaysPastDue < 90 THEN 1 ELSE 0 END) AS on_arrears_report_under_90,
       SUM(CASE WHEN DaysPastDue > 90 AND LoanCleared = 0 THEN 1 ELSE 0 END) AS on_npl_report_open_over_90,
       SUM(CASE WHEN LoanCleared = 1 THEN 1 ELSE 0 END) AS already_cleared
FROM #todo GROUP BY EntityId
UNION ALL
SELECT NULL, COUNT(*), SUM(LedgerPenalty), SUM(CASE WHEN DaysPastDue < 90 THEN 1 ELSE 0 END),
       SUM(CASE WHEN DaysPastDue > 90 AND LoanCleared = 0 THEN 1 ELSE 0 END), SUM(CASE WHEN LoanCleared = 1 THEN 1 ELSE 0 END)
FROM #todo;

-- the consistency this relies on: filled columns agree with the ledger
SELECT COUNT(*) AS filled_columns_disagreeing_with_ledger
FROM dbo.Loans L JOIN #ledger lg ON lg.LoanId = L.ID
WHERE L.Penalty IS NOT NULL AND L.Penalty <> lg.LedgerPenalty;

IF @DryRun = 1
BEGIN
    PRINT 'DRY RUN: nothing written. Set @DryRun = 0 to fill the column.';
    RETURN;
END;

/* -- write ------------------------------------------------------------------ */
IF OBJECT_ID(N'dbo.MicroEazyPenaltyBackfillLog') IS NULL
    CREATE TABLE dbo.MicroEazyPenaltyBackfillLog (
        Id           INT IDENTITY(1,1) PRIMARY KEY,
        LoanId       INT            NOT NULL,
        EntityId     INT            NULL,
        OldPenalty   DECIMAL(18,2)  NULL,
        NewPenalty   DECIMAL(18,2)  NOT NULL,
        LedgerRows   INT            NOT NULL,
        FilledAt     DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
        RolledBackAt DATETIME2(0)   NULL,
        INDEX IX_MicroEazyPenaltyBackfillLog_Loan (LoanId)
    );

DECLARE @from INT = 1, @last INT = (SELECT MIN(v) FROM (VALUES ((SELECT MAX(RowNo) FROM #todo)), (@MaxLoans)) x(v)),
        @filled INT = 0, @n INT;

WHILE @from <= @last
BEGIN
    BEGIN TRANSACTION;

    UPDATE L
    SET L.Penalty = t.LedgerPenalty
    OUTPUT inserted.ID, inserted.EntityId, deleted.Penalty, inserted.Penalty, t.LedgerRows
      INTO dbo.MicroEazyPenaltyBackfillLog (LoanId, EntityId, OldPenalty, NewPenalty, LedgerRows)
    FROM dbo.Loans L
    JOIN #todo t ON t.LoanId = L.ID
    WHERE t.RowNo BETWEEN @from AND @from + @BatchSize - 1
      AND t.RowNo <= @last
      AND L.Penalty IS NULL;            -- re-checked at write time

    SET @n = @@ROWCOUNT;
    COMMIT TRANSACTION;

    SET @filled += @n;
    SET @from += @BatchSize;
    RAISERROR('filled %d so far', 0, 1, @filled) WITH NOWAIT;
END;

PRINT 'FILLED ' + CAST(@filled AS VARCHAR(10)) + ' loan(s). Logged in dbo.MicroEazyPenaltyBackfillLog.';
GO
