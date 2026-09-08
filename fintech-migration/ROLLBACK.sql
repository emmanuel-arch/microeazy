/* ============================================================================
   ROLLBACK — put everything back the way it was on 8 September 2026.

   Two sources, because the restamp records 3.5 million rows and the rest
   records a few thousand:

     dbo.FintechRestamp_*_20260908           scripts 02        (RowId, OldEntityId)
     dbo.FintechRemediationBackup_20260908   scripts 01/03/04/07 (old + new value)

   Both are still on the server unless somebody dropped them. If they are gone,
   this file cannot help you and the database backup taken in phase 0 is the
   only way back.

   -- READ BEFORE RUNNING -----------------------------------------------------
   Sections are INDEPENDENT and run newest-change-first. Run only the sections
   for the scripts you actually want to undo, and run them in the order given --
   undoing the merge (04) before the re-parent (03) matters, because 04 moved
   loans between borrowers and 03 only changed columns on the borrower.

   The identity lock from script 05 is dropped FIRST in every case: it would
   otherwise reject the rollback of the merge, since putting the duplicate
   records back is precisely what it exists to prevent.
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* -------------------------------------------------------------------------
   R0 · Stand the lock down. Always run this before any section below.
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.trg_Borrowers_MicromartIdentityLock') IS NOT NULL
BEGIN
    DROP TRIGGER dbo.trg_Borrowers_MicromartIdentityLock;
    PRINT 'R0: identity lock trigger dropped.';
END
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Borrowers_NationalIDLockKey' AND object_id = OBJECT_ID('dbo.Borrowers'))
BEGIN
    DROP INDEX UX_Borrowers_NationalIDLockKey ON dbo.Borrowers;
    PRINT 'R0: backstop unique index dropped.';
END
GO

/* -------------------------------------------------------------------------
   R1 · Undo 07 — restore the truncated PIN hashes.
        (They were unusable; you almost certainly do not want this.)
   ---------------------------------------------------------------------- */
BEGIN TRANSACTION;
    UPDATE b SET b.UssdPin = k.OldValue
    FROM dbo.Borrowers b
    JOIN dbo.FintechRemediationBackup_20260908 k
      ON k.TableName = 'Borrowers' AND k.ColumnName = 'UssdPin' AND k.Phase = '07-pins' AND k.KeyValue = b.ID;
    PRINT 'R1: PIN hashes restored: ' + CAST(@@ROWCOUNT AS VARCHAR(20));
COMMIT TRANSACTION;
GO

/* -------------------------------------------------------------------------
   R2 · Undo 04 — unmerge the duplicates.
        Loans go back to the original borrower and the original entity; the
        closed shells are reopened.
   ---------------------------------------------------------------------- */
BEGIN TRANSACTION;
    UPDATE l SET l.BorrowerId = CAST(k.OldValue AS INT)
    FROM dbo.Loans l
    JOIN dbo.FintechRemediationBackup_20260908 k
      ON k.TableName = 'Loans' AND k.ColumnName = 'BorrowerId' AND k.Phase = '04-merge' AND k.KeyValue = l.id;
    PRINT 'R2: loans returned to their original borrower: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

    UPDATE l SET l.EntityId = CAST(k.OldValue AS INT)
    FROM dbo.Loans l
    JOIN dbo.FintechRemediationBackup_20260908 k
      ON k.TableName = 'Loans' AND k.ColumnName = 'EntityId' AND k.Phase = '04-merge' AND k.KeyValue = l.id;
    PRINT 'R2: loan entities restored: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

    UPDATE b SET b.AccountStatus = CAST(k.OldValue AS INT)
    FROM dbo.Borrowers b
    JOIN dbo.FintechRemediationBackup_20260908 k
      ON k.TableName = 'Borrowers' AND k.ColumnName = 'AccountStatus' AND k.Phase = '04-merge' AND k.KeyValue = b.ID;
    PRINT 'R2: closed shells reopened: ' + CAST(@@ROWCOUNT AS VARCHAR(20));
COMMIT TRANSACTION;
-- NOTE: the borrower-owned child rows moved by 4.2 (attachments, contacts,
-- details, referees, guarantors, collaterals, ledger) are NOT returned by this
-- section. They followed the person, and the person is the same person. If you
-- need them back on the shell, take them from the phase-0 database backup.
GO

/* -------------------------------------------------------------------------
   R3 · Undo 03 — put the borrowers back on their branch and their RO.
   ---------------------------------------------------------------------- */
BEGIN TRANSACTION;
    UPDATE b SET b.EntityUnit = CAST(k.OldValue AS INT)
    FROM dbo.Borrowers b
    JOIN dbo.FintechRemediationBackup_20260908 k
      ON k.TableName = 'Borrowers' AND k.ColumnName = 'EntityUnit' AND k.Phase = '03-reparent' AND k.KeyValue = b.ID;
    PRINT 'R3: branches restored: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

    UPDATE b SET b.EntityAgent = CAST(k.OldValue AS INT)
    FROM dbo.Borrowers b
    JOIN dbo.FintechRemediationBackup_20260908 k
      ON k.TableName = 'Borrowers' AND k.ColumnName = 'EntityAgent' AND k.Phase = '03-reparent' AND k.KeyValue = b.ID;
    PRINT 'R3: relationship officers restored: ' + CAST(@@ROWCOUNT AS VARCHAR(20));
COMMIT TRANSACTION;
GO

/* -------------------------------------------------------------------------
   R4 · Undo 02 — put the 3.5 million child rows back on their old entity.
        Batched exactly like the forward script, for the same reason.
   ---------------------------------------------------------------------- */
DECLARE @n INT, @total BIGINT;

SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = d.OldEntityId
    FROM dbo.Journals x JOIN dbo.FintechRestamp_Journals_20260908 d ON d.RowId = x.Id
    WHERE x.EntityId <> d.OldEntityId;
    SET @n = @@ROWCOUNT; SET @total = @total + @n; IF @n = 0 BREAK;
END
PRINT 'R4 Journals reverted: ' + CAST(@total AS VARCHAR(20));

SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = d.OldEntityId
    FROM dbo.LoanGraduationHistory x JOIN dbo.FintechRestamp_LoanGraduationHistory_20260908 d ON d.RowId = x.Id
    WHERE x.EntityId <> d.OldEntityId;
    SET @n = @@ROWCOUNT; SET @total = @total + @n; IF @n = 0 BREAK;
END
PRINT 'R4 LoanGraduationHistory reverted: ' + CAST(@total AS VARCHAR(20));

SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = d.OldEntityId
    FROM dbo.CustomerStatement x JOIN dbo.FintechRestamp_CustomerStatement_20260908 d ON d.RowId = x.id
    WHERE x.EntityId <> d.OldEntityId;
    SET @n = @@ROWCOUNT; SET @total = @total + @n; IF @n = 0 BREAK;
END
PRINT 'R4 CustomerStatement reverted: ' + CAST(@total AS VARCHAR(20));

SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = d.OldEntityId
    FROM dbo.loanSchedule x JOIN dbo.FintechRestamp_loanSchedule_20260908 d ON d.RowId = x.id
    WHERE x.EntityId <> d.OldEntityId;
    SET @n = @@ROWCOUNT; SET @total = @total + @n; IF @n = 0 BREAK;
END
PRINT 'R4 loanSchedule reverted: ' + CAST(@total AS VARCHAR(20));

UPDATE x SET x.EntityId = d.OldEntityId
FROM dbo.loanChargesSchedule x JOIN dbo.FintechRestamp_loanChargesSchedule_20260908 d ON d.RowId = x.id
WHERE x.EntityId <> d.OldEntityId;
PRINT 'R4 loanChargesSchedule reverted: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

UPDATE x SET x.EntityId = d.OldEntityId
FROM dbo.ManagedLoans x JOIN dbo.FintechRestamp_ManagedLoans_20260908 d ON d.RowId = x.ID
WHERE x.EntityId <> d.OldEntityId;
PRINT 'R4 ManagedLoans reverted: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

UPDATE x SET x.EntityId = d.OldEntityId
FROM dbo.STKPaymentRequests x JOIN dbo.FintechRestamp_STKPaymentRequests_20260908 d ON d.RowId = x.ID
WHERE x.EntityId <> d.OldEntityId;
PRINT 'R4 STKPaymentRequests reverted: ' + CAST(@@ROWCOUNT AS VARCHAR(20));
GO

/* -------------------------------------------------------------------------
   R5 · Undo 01 — disable Geoffrey again and restore both users' branch.
   ---------------------------------------------------------------------- */
BEGIN TRANSACTION;
    UPDATE u SET u.UserStatus = CAST(k.OldValue AS INT)
    FROM dbo.UserMaster u
    JOIN dbo.FintechRemediationBackup_20260908 k
      ON k.TableName = 'UserMaster' AND k.ColumnName = 'UserStatus' AND k.Phase = '01-destination' AND k.KeyValue = u.ID;

    UPDATE u SET u.OrganizationUnit = CAST(k.OldValue AS INT)
    FROM dbo.UserMaster u
    JOIN dbo.FintechRemediationBackup_20260908 k
      ON k.TableName = 'UserMaster' AND k.ColumnName = 'OrganizationUnit' AND k.Phase = '01-destination' AND k.KeyValue = u.ID;
    PRINT 'R5: destination users restored.';
COMMIT TRANSACTION;
GO

/* -------------------------------------------------------------------------
   R6 · Undo 10 — stop the service.
   ---------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'MicroEazy - Dormancy migration to Fintech')
BEGIN
    EXEC msdb.dbo.sp_update_job @job_name = N'MicroEazy - Dormancy migration to Fintech', @enabled = 0;
    PRINT 'R6: dormancy job DISABLED (not deleted -- its log is the audit trail).';
END
GO

/* -------------------------------------------------------------------------
   R7 · Undo 06 — the original sp_restBorrowerPin body is at the bottom of
        06-fix-sp-restBorrowerPin.sql. Uncomment and run it there.
   ---------------------------------------------------------------------- */
PRINT 'ROLLBACK sections complete. Re-run 00-preflight.sql and compare the numbers.';
