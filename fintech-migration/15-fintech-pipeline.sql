/* ============================================================================
   15 · THE FINTECH PIPELINE TABLE — the date a settled customer crosses, precomputed

   WHY THIS EXISTS
   Micro Eazy's create-account door now asks, before it sends a code, which of
   Micromart's books a phone number is on. A customer on Micromart Africa (3002)
   whose loans are all settled is told the day they move to Fintech (3005) and
   can apply from home — "9 days to go" rather than "you cannot register".

   That day is 60 days after the ledger last showed a zero balance. The only
   witness to that moment is CustomerStatement, a 3.5M-row heap with no index
   (see script 13). Scanning it once per welcome-page submit would put load on
   the SHARED production server every time somebody types their number. So the
   answer is computed ONCE A NIGHT, in the same scan the dormancy job already
   performs, and the app reads one keyed row.

   Until this script is installed the app still works: it tells the customer
   they are in the pipeline without a day count.

   WHAT IT INSTALLS (all additive; nothing existing is altered)
     15.1  dbo.MicroEazyFintechPipeline         one row per settled 3002 customer
     15.2  dbo.sp_MicroEazy_RefreshFintechPipeline   rebuilds it (dry run default)
     15.3  a second step on the existing 02:30 dormancy job, AFTER the move,
           so the table reflects who is still waiting once tonight's moves land

   SAFE TO RE-RUN. Run in SSMS against Serviceconnect.
   ==========================================================================*/
USE Serviceconnect;
GO
SET NOCOUNT ON;
GO

/* -------------------------------------------------------------------------
   15.1 · The table. Keyed on BorrowerId, which is what the app looks up by.
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.MicroEazyFintechPipeline') IS NULL
BEGIN
    CREATE TABLE dbo.MicroEazyFintechPipeline (
        BorrowerId     INT        NOT NULL CONSTRAINT PK_MicroEazyFintechPipeline PRIMARY KEY,
        LastClearedOn  DATE       NULL,     -- the day the last OLB reached zero (script 13's clock)
        EligibleOn     DATE       NULL,     -- LastClearedOn + 60
        Held           BIT        NOT NULL CONSTRAINT DF_MEFP_Held DEFAULT 0,  -- ledger never shows a zero: not dated
        LoanCount      INT        NULL,
        RefreshedAt    DATETIME2  NOT NULL CONSTRAINT DF_MEFP_Refreshed DEFAULT SYSDATETIME()
    );
    PRINT 'Created dbo.MicroEazyFintechPipeline';
END
GO

/* -------------------------------------------------------------------------
   15.2 · The refresh.
          EXEC dbo.sp_MicroEazy_RefreshFintechPipeline;               -- dry run
          EXEC dbo.sp_MicroEazy_RefreshFintechPipeline @DryRun = 0;   -- for real
   ---------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_MicroEazy_RefreshFintechPipeline
    @DryRun      BIT = 1,
    @DormantDays INT = 60
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FromEntity INT = 3002;

    /* The ledger clock -- identical to script 13, so the date shown to a
       customer and the date the job acts on come from the same arithmetic. */
    IF OBJECT_ID('tempdb..#ledger') IS NOT NULL DROP TABLE #ledger;
    SELECT cs.LoanId,
           COUNT(*)                                                     AS LedgerRows,
           MAX(CASE WHEN cs.LoanBalance = 0 THEN cs.TransactedDate END) AS ZeroDate
    INTO #ledger
    FROM dbo.CustomerStatement cs
    JOIN dbo.Loans l ON l.id = cs.LoanId AND l.EntityId = @FromEntity
    GROUP BY cs.LoanId;
    CREATE CLUSTERED INDEX IX_ledger ON #ledger(LoanId);

    IF OBJECT_ID('tempdb..#book') IS NOT NULL DROP TABLE #book;
    SELECT l.BorrowerId,
           MAX(CASE WHEN l.LoanCleared = 1 AND ISNULL(l.LoanBalance, 0) <= 0 THEN 0 ELSE 1 END) AS AnyOpen,
           MAX(COALESCE(d.ZeroDate,
                        CASE WHEN d.LedgerRows IS NULL THEN CAST(l.ExpectedClearDate AS DATETIME) END)) AS LastClearedOn,
           SUM(CASE WHEN d.LedgerRows IS NOT NULL AND d.ZeroDate IS NULL THEN 1 ELSE 0 END)          AS UndatableLoans,
           COUNT(*) AS LoanCount
    INTO #book
    FROM dbo.Loans l
    LEFT JOIN #ledger d ON d.LoanId = l.id
    WHERE l.EntityId = @FromEntity
    GROUP BY l.BorrowerId;

    IF OBJECT_ID('tempdb..#pipeline') IS NOT NULL DROP TABLE #pipeline;
    SELECT x.BorrowerId,
           CAST(x.LastClearedOn AS DATE)                              AS LastClearedOn,
           CAST(DATEADD(DAY, @DormantDays, x.LastClearedOn) AS DATE)  AS EligibleOn,
           CAST(CASE WHEN x.UndatableLoans > 0 THEN 1 ELSE 0 END AS BIT) AS Held,
           x.LoanCount
    INTO #pipeline
    FROM #book x
    JOIN dbo.Borrowers b ON b.ID = x.BorrowerId AND b.EntityId = @FromEntity
    WHERE x.AnyOpen = 0
      AND ISNULL(b.AccountStatus, 1) <> 0;

    IF @DryRun = 1
    BEGIN
        SELECT COUNT(*) AS customers,
               SUM(CASE WHEN Held = 1 THEN 1 ELSE 0 END)                                        AS held,
               SUM(CASE WHEN Held = 0 AND EligibleOn >  CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS waiting,
               SUM(CASE WHEN Held = 0 AND EligibleOn <= CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS due
        FROM #pipeline;
        PRINT 'DRY RUN -- nothing written.';
        RETURN;
    END

    BEGIN TRANSACTION;
        DELETE FROM dbo.MicroEazyFintechPipeline;
        INSERT INTO dbo.MicroEazyFintechPipeline (BorrowerId, LastClearedOn, EligibleOn, Held, LoanCount, RefreshedAt)
        SELECT BorrowerId, LastClearedOn, EligibleOn, Held, LoanCount, SYSDATETIME() FROM #pipeline;
    COMMIT TRANSACTION;

    PRINT 'Micro Eazy pipeline refreshed.';
END
GO

/* -------------------------------------------------------------------------
   15.3 · Refresh after tonight's moves, on the job that already runs at 02:30.
   ---------------------------------------------------------------------- */
USE msdb;
GO
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'MicroEazy - Dormancy migration to Fintech')
AND NOT EXISTS (
    SELECT 1 FROM msdb.dbo.sysjobsteps s JOIN msdb.dbo.sysjobs j ON j.job_id = s.job_id
    WHERE j.name = N'MicroEazy - Dormancy migration to Fintech' AND s.step_name = N'Refresh Micro Eazy pipeline')
BEGIN
    -- Step 1 used to quit on success; it now continues to step 2.
    EXEC msdb.dbo.sp_update_jobstep
         @job_name = N'MicroEazy - Dormancy migration to Fintech',
         @step_id = 1,
         @on_success_action = 3;

    EXEC msdb.dbo.sp_add_jobstep
         @job_name      = N'MicroEazy - Dormancy migration to Fintech',
         @step_id       = 2,
         @step_name     = N'Refresh Micro Eazy pipeline',
         @subsystem     = N'TSQL',
         @database_name = N'Serviceconnect',
         @command       = N'EXEC dbo.sp_MicroEazy_RefreshFintechPipeline @DryRun = 0, @DormantDays = 60;',
         @retry_attempts = 1,
         @retry_interval = 10;
    PRINT 'Added the pipeline refresh as step 2 of the dormancy job.';
END
GO

USE Serviceconnect;
GO
PRINT '15 complete. Populate it now rather than waiting for 02:30:';
PRINT '   EXEC dbo.sp_MicroEazy_RefreshFintechPipeline;             -- dry run, read the counts';
PRINT '   EXEC dbo.sp_MicroEazy_RefreshFintechPipeline @DryRun = 0;';
GO
