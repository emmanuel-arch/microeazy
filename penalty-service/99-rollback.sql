/* ============================================================================
   99 · ROLL BACK THIS FOLDER'S CHANGES                        DRY RUN BY DEFAULT

   Choose what to undo with the three switches (all off by default). The dry
   run shows exactly what each would do and, for procedures, proves the saved
   originals still compile, then rolls back.

     @RestoreProcs          the procedures 01 and 05 replaced, from
                            dbo.MicroEazyProcBackup
     @RestoreProductConfig  the start dates / grace / rate / option that 02
                            and 03 changed, from dbo.MicroEazyPenaltyConfigLog
     @UndoBackfill          empties Loans.Penalty again on the loans 04 filled,
                            from dbo.MicroEazyPenaltyBackfillLog. If a newer
                            penalty has since been added on top, only 04's
                            part is subtracted.

   WHAT THIS CANNOT UNDO: a penalty run that already happened. Once the 01:01
   job has charged a loan, its balance, schedule, statement line,
   ManagedLoans row (TransType 6, DoneBy 101) and SMS all exist. Reversing
   charges is a separate, deliberate job, and the SMS cannot be recalled.
   Also not undone: the unscoped `update products set RollOverApplication=1`
   of 17 Sep 2026, which happened before this folder and logged no old values.
   ==========================================================================*/
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @DryRun               BIT = 1;   -- <<< DRY RUN (1 = rehearse, 0 = undo)
DECLARE @RestoreProcs         BIT = 0;
DECLARE @RestoreProductConfig BIT = 0;
DECLARE @UndoBackfill         BIT = 0;

/* -- what exists to undo ---------------------------------------------------- */
IF OBJECT_ID(N'dbo.MicroEazyProcBackup') IS NULL
    SELECT 'no procedure backups - 01 and 05 have not been installed' AS procedures_;
ELSE
    EXEC (N'SELECT b.ProcName, b.SavedAt, b.Script, b.Sha256 AS original_sha256,
                   CONVERT(VARCHAR(64), HASHBYTES(''SHA2_256'', m.definition), 2) AS live_sha256
            FROM dbo.MicroEazyProcBackup b
            LEFT JOIN sys.sql_modules m ON m.object_id = OBJECT_ID(N''dbo.'' + b.ProcName)
            WHERE b.Id IN (SELECT MIN(Id) FROM dbo.MicroEazyProcBackup GROUP BY ProcName)
            ORDER BY b.ProcName;');

IF OBJECT_ID(N'dbo.MicroEazyPenaltyConfigLog') IS NULL
    SELECT 'no product config changes logged - 02 and 03 have not been applied' AS product_config;
ELSE
    EXEC (N'SELECT Id, ChangedAt, Script, EntityId, ProductId, ProductName, Field, OldValue, NewValue, RolledBackAt
            FROM dbo.MicroEazyPenaltyConfigLog ORDER BY Id;');

IF OBJECT_ID(N'dbo.MicroEazyPenaltyBackfillLog') IS NULL
    SELECT 'no backfill logged - 04 has not been applied' AS backfill;
ELSE
    EXEC (N'SELECT COUNT(*) AS filled_loans, SUM(g.NewPenalty) AS filled_kes,
                   SUM(CASE WHEN g.RolledBackAt IS NULL AND L.Penalty = g.NewPenalty THEN 1 ELSE 0 END) AS would_empty,
                   SUM(CASE WHEN g.RolledBackAt IS NULL AND L.Penalty <> g.NewPenalty THEN 1 ELSE 0 END) AS would_subtract_newer_penalty_kept,
                   SUM(CASE WHEN g.RolledBackAt IS NOT NULL THEN 1 ELSE 0 END) AS already_rolled_back
            FROM dbo.MicroEazyPenaltyBackfillLog g JOIN dbo.Loans L ON L.ID = g.LoanId;');

IF @RestoreProcs = 0 AND @RestoreProductConfig = 0 AND @UndoBackfill = 0
BEGIN
    PRINT 'Nothing selected. Turn on @RestoreProcs, @RestoreProductConfig and/or @UndoBackfill.';
    RETURN;
END;

BEGIN TRANSACTION;

/* -- procedures -------------------------------------------------------------- */
IF @RestoreProcs = 1 AND OBJECT_ID(N'dbo.MicroEazyProcBackup') IS NOT NULL
BEGIN
    DECLARE @name SYSNAME, @def NVARCHAR(MAX), @at INT;
    DECLARE procs CURSOR LOCAL FAST_FORWARD FOR
        SELECT ProcName, Definition FROM dbo.MicroEazyProcBackup
        WHERE Id IN (SELECT MIN(Id) FROM dbo.MicroEazyProcBackup GROUP BY ProcName);   -- the true original
    OPEN procs;
    FETCH NEXT FROM procs INTO @name, @def;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- the stored text starts "CREATE PROCEDURE"; ALTER keeps permissions and
        -- stores the text back byte-for-byte, so 01/05's fingerprint check passes again
        SET @at = PATINDEX(N'%CREATE%PROC%', @def);
        SET @def = STUFF(@def, @at, 6, N'ALTER');
        EXEC sys.sp_executesql @def;
        PRINT 'restored ' + @name;
        FETCH NEXT FROM procs INTO @name, @def;
    END;
    CLOSE procs; DEALLOCATE procs;
END;

/* -- product configuration: back to the value before the FIRST logged change */
IF @RestoreProductConfig = 1 AND OBJECT_ID(N'dbo.MicroEazyPenaltyConfigLog') IS NOT NULL
BEGIN
    EXEC (N'
    ;WITH firstChange AS (
        SELECT ProductId, Field, OldValue,
               ROW_NUMBER() OVER (PARTITION BY ProductId, Field ORDER BY Id) AS rn
        FROM dbo.MicroEazyPenaltyConfigLog WHERE RolledBackAt IS NULL
    )
    UPDATE P SET
        P.RollOverStartDate   = CASE WHEN sd.ProductId IS NOT NULL THEN CONVERT(DATE, sd.OldValue, 23) ELSE P.RollOverStartDate END,
        P.RollOverApplication = CASE WHEN ap.ProductId IS NOT NULL THEN CAST(ap.OldValue AS INT) ELSE P.RollOverApplication END,
        P.RollOverGracePeriod = CASE WHEN gr.ProductId IS NOT NULL THEN CAST(gr.OldValue AS INT) ELSE P.RollOverGracePeriod END,
        P.RollOverValue       = CASE WHEN rv.ProductId IS NOT NULL THEN CAST(rv.OldValue AS DECIMAL(18,2)) ELSE P.RollOverValue END
    FROM dbo.Products P
    LEFT JOIN firstChange sd ON sd.ProductId = P.ID AND sd.Field = ''RollOverStartDate''   AND sd.rn = 1
    LEFT JOIN firstChange ap ON ap.ProductId = P.ID AND ap.Field = ''RollOverApplication'' AND ap.rn = 1
    LEFT JOIN firstChange gr ON gr.ProductId = P.ID AND gr.Field = ''RollOverGracePeriod'' AND gr.rn = 1
    LEFT JOIN firstChange rv ON rv.ProductId = P.ID AND rv.Field = ''RollOverValue''       AND rv.rn = 1
    WHERE COALESCE(sd.ProductId, ap.ProductId, gr.ProductId, rv.ProductId) IS NOT NULL;

    PRINT ''restored product fields on '' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '' product(s)'';

    UPDATE dbo.MicroEazyPenaltyConfigLog SET RolledBackAt = SYSDATETIME() WHERE RolledBackAt IS NULL;');
END;

/* -- backfill ---------------------------------------------------------------- */
IF @UndoBackfill = 1 AND OBJECT_ID(N'dbo.MicroEazyPenaltyBackfillLog') IS NOT NULL
BEGIN
    EXEC (N'
    UPDATE L SET L.Penalty = CASE WHEN L.Penalty = g.NewPenalty THEN NULL ELSE L.Penalty - g.NewPenalty END
    FROM dbo.Loans L
    JOIN dbo.MicroEazyPenaltyBackfillLog g ON g.LoanId = L.ID
    WHERE g.RolledBackAt IS NULL;

    PRINT ''undid the backfill on '' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '' loan(s)'';

    UPDATE dbo.MicroEazyPenaltyBackfillLog SET RolledBackAt = SYSDATETIME() WHERE RolledBackAt IS NULL;');
END;

IF @DryRun = 1
BEGIN
    ROLLBACK TRANSACTION;
    PRINT 'DRY RUN: the steps above ran inside a transaction and were ROLLED BACK. Nothing changed.';
END
ELSE
BEGIN
    COMMIT TRANSACTION;
    PRINT 'ROLLED BACK the selected changes. Run 00-preview.sql to see the next run as it now stands.';
END;
GO
