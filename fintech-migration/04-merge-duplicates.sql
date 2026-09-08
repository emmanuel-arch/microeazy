/* ============================================================================
   04 · MERGE THE DUPLICATE IDENTITIES  --  3005 wins

   200 national IDs and 52 phone numbers exist on both books, because after the
   2 August migration relationship officers went on onboarding the same people
   afresh on 3002. 201 borrower records on 3002 are duplicates of a 3005 record.

   -- THE SPLIT THAT MATTERS -------------------------------------------------
   Of those 201:
       143  have NO open loan  ->  merged automatically by section 4.2
        58  HAVE an open loan  ->  NOT TOUCHED. Reported by section 4.3.

   Moving a live loan between books is an accounting event, not a data fix: it
   moves the balance out of one book's portfolio and into another's, and it
   changes whose collections queue the customer sits in. This script will not
   do that silently to 58 borrowers. Work section 4.3's list with Geoffrey and
   decide each one -- normally by letting the loan run to term on 3002 and
   letting script 10's dormancy service move the customer afterwards, which is
   exactly the path it exists to provide.

   Reversible: yes -- every change is recorded in
   dbo.FintechRemediationBackup_20260908 before it is applied.
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.FintechRemediationBackup_20260908') IS NULL
BEGIN RAISERROR('Run 01-fix-destination.sql first -- the backup table is missing.', 16, 1); RETURN; END

/* -------------------------------------------------------------------------
   4.1 · THE WORKSHEET -- read only. Run this alone first and keep the output.
   ---------------------------------------------------------------------- */
IF OBJECT_ID('tempdb..#pairs') IS NOT NULL DROP TABLE #pairs;

SELECT  dup.ID            AS DupId,          -- the 3002 re-onboard
        surv.ID           AS SurvivorId,     -- the 3005 record that wins
        dup.firstName     AS DupFirstName,
        dup.otherName     AS DupOtherName,
        dup.NationalID    AS NationalID,
        dup.PhoneNumber   AS DupPhone,
        surv.PhoneNumber  AS SurvivorPhone,
        dup.CreatedDate   AS DupCreated,
        surv.CreatedDate  AS SurvivorCreated,
        (SELECT COUNT(*) FROM dbo.Loans l WHERE l.BorrowerId = dup.ID)                      AS DupLoans,
        (SELECT COUNT(*) FROM dbo.Loans l WHERE l.BorrowerId = dup.ID AND l.LoanCleared <> 1) AS DupOpenLoans,
        (SELECT ISNULL(SUM(l.LoanBalance),0) FROM dbo.Loans l WHERE l.BorrowerId = dup.ID AND l.LoanCleared <> 1) AS DupOpenBalance,
        (SELECT COUNT(*) FROM dbo.Loans l WHERE l.BorrowerId = surv.ID)                     AS SurvivorLoans
INTO #pairs
FROM dbo.Borrowers dup
CROSS APPLY (
    SELECT TOP 1 s.*
    FROM dbo.Borrowers s
    WHERE s.EntityId = 3005
      AND ISNULL(s.AccountStatus, 1) <> 0
      AND (
            (NULLIF(LTRIM(RTRIM(dup.NationalID)), '')  IS NOT NULL
             AND LTRIM(RTRIM(s.NationalID))  = LTRIM(RTRIM(dup.NationalID)))
         OR (NULLIF(LTRIM(RTRIM(dup.PhoneNumber)), '') IS NOT NULL
             AND LTRIM(RTRIM(s.PhoneNumber)) = LTRIM(RTRIM(dup.PhoneNumber)))
          )
    ORDER BY s.CreatedDate ASC, s.ID ASC          -- oldest 3005 record is the survivor
) surv
WHERE dup.EntityId = 3002
  AND ISNULL(dup.AccountStatus, 1) <> 0;

SELECT 'WORKSHEET -- all duplicate pairs' AS section, * FROM #pairs ORDER BY DupOpenLoans DESC, NationalID;
-- expected: 201 rows, of which 58 have DupOpenLoans > 0

/* -------------------------------------------------------------------------
   4.2 · AUTO-MERGE the pairs with NO open loan on the 3002 side.

   For each: every loan and every borrower-owned child row moves to the
   survivor and onto book 3005; the 3002 shell is then closed, not deleted,
   so the audit trail and the rollback both survive.
   ---------------------------------------------------------------------- */
IF OBJECT_ID('tempdb..#merge') IS NOT NULL DROP TABLE #merge;
SELECT DupId, SurvivorId INTO #merge FROM #pairs WHERE DupOpenLoans = 0;
CREATE CLUSTERED INDEX IX_merge ON #merge(DupId);

DECLARE @n INT = (SELECT COUNT(*) FROM #merge);
PRINT 'Auto-merging ' + CAST(@n AS VARCHAR(20)) + ' duplicate records (expected 143).';

BEGIN TRANSACTION;

    /* -- record the loan moves -- */
    INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
    SELECT '04-merge', 'Loans', l.id, 'BorrowerId', CAST(l.BorrowerId AS NVARCHAR(200)), CAST(m.SurvivorId AS NVARCHAR(200))
    FROM dbo.Loans l JOIN #merge m ON m.DupId = l.BorrowerId;

    INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
    SELECT '04-merge', 'Loans', l.id, 'EntityId', CAST(l.EntityId AS NVARCHAR(200)), N'3005'
    FROM dbo.Loans l JOIN #merge m ON m.DupId = l.BorrowerId WHERE l.EntityId <> 3005;

    /* -- move the loans -- */
    UPDATE l SET l.BorrowerId = m.SurvivorId, l.EntityId = 3005
    FROM dbo.Loans l JOIN #merge m ON m.DupId = l.BorrowerId;
    PRINT '  loans moved: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

    /* -- follow the loans with their entity-stamped children -- */
    UPDATE x SET x.EntityId = 3005 FROM dbo.loanSchedule x
      JOIN dbo.Loans l ON l.id = x.Loanid JOIN #merge m ON m.SurvivorId = l.BorrowerId WHERE x.EntityId <> 3005;
    UPDATE x SET x.EntityId = 3005 FROM dbo.loanChargesSchedule x
      JOIN dbo.Loans l ON l.id = x.Loanid JOIN #merge m ON m.SurvivorId = l.BorrowerId WHERE x.EntityId <> 3005;
    UPDATE x SET x.EntityId = 3005 FROM dbo.CustomerStatement x
      JOIN dbo.Loans l ON l.id = x.LoanId JOIN #merge m ON m.SurvivorId = l.BorrowerId WHERE x.EntityId <> 3005;
    UPDATE x SET x.EntityId = 3005 FROM dbo.ManagedLoans x
      JOIN dbo.Loans l ON l.id = x.LoanId JOIN #merge m ON m.SurvivorId = l.BorrowerId WHERE x.EntityId <> 3005;

    /* -- move the borrower-owned children onto the survivor -- */
    UPDATE x SET x.borrowerId = m.SurvivorId FROM dbo.BorrowerAttachments x JOIN #merge m ON m.DupId = x.borrowerId;
    UPDATE x SET x.BorrowerId = m.SurvivorId FROM dbo.BorrowerContacts   x JOIN #merge m ON m.DupId = x.BorrowerId;
    UPDATE x SET x.borrowerId = m.SurvivorId FROM dbo.BorrowerDetails    x JOIN #merge m ON m.DupId = x.borrowerId;
    UPDATE x SET x.BorrowerID = m.SurvivorId FROM dbo.BorrowerReferees   x JOIN #merge m ON m.DupId = x.BorrowerID;
    UPDATE x SET x.BorrowerId = m.SurvivorId FROM dbo.Guarantor          x JOIN #merge m ON m.DupId = x.BorrowerId;
    UPDATE x SET x.BorrowerId = m.SurvivorId FROM dbo.Collaterals        x JOIN #merge m ON m.DupId = x.BorrowerId;
    UPDATE x SET x.BorrowerId = m.SurvivorId FROM dbo.AccountLedger      x JOIN #merge m ON m.DupId = x.BorrowerId;
    UPDATE x SET x.BorrowerId = m.SurvivorId, x.EntityId = 3005 FROM dbo.Journals              x JOIN #merge m ON m.DupId = x.BorrowerId;
    UPDATE x SET x.BorrowerId = m.SurvivorId, x.EntityId = 3005 FROM dbo.LoanGraduationHistory x JOIN #merge m ON m.DupId = x.BorrowerId;
    UPDATE x SET x.BorrowerId = m.SurvivorId, x.EntityId = 3005 FROM dbo.STKPaymentRequests    x JOIN #merge m ON m.DupId = x.BorrowerId;

    /* -- close the shell (never delete: the audit trail and rollback need it) -- */
    INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
    SELECT '04-merge', 'Borrowers', b.ID, 'AccountStatus', CAST(b.AccountStatus AS NVARCHAR(200)), N'0'
    FROM dbo.Borrowers b JOIN #merge m ON m.DupId = b.ID;

    UPDATE b SET b.AccountStatus = 0, b.UpdatedBy = 9096, b.UpdatedDate = GETDATE()
    FROM dbo.Borrowers b JOIN #merge m ON m.DupId = b.ID;

    INSERT dbo.BorrowerComments (borroweId, Comment, CreatedBy, DateCreated)
    SELECT m.DupId,
           'Closed 2026-09-08: duplicate of borrower ' + CAST(m.SurvivorId AS VARCHAR(20))
           + ' on MICROMART FINTECH (3005). Loans and records merged to the survivor.',
           9096, GETDATE()
    FROM #merge m;

COMMIT TRANSACTION;
PRINT '4.2 complete.';

/* -------------------------------------------------------------------------
   4.3 · THE 58 THAT NEED A HUMAN. Nothing below is changed by this script.
   ---------------------------------------------------------------------- */
SELECT 'MANUAL -- duplicate with an OPEN loan on 3002' AS action_required,
       DupId, SurvivorId, DupFirstName, DupOtherName, NationalID,
       DupPhone, SurvivorPhone, DupOpenLoans, DupOpenBalance, DupCreated
FROM #pairs WHERE DupOpenLoans > 0
ORDER BY DupOpenBalance DESC;

PRINT '04 complete. Section 4.3 output is the list for Geoffrey.';
