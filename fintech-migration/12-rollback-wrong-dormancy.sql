/* ============================================================================
   12 · ROLL BACK THE 11 SEP 2026 DORMANCY RUN -- the customers it should
        never have touched.

   WHAT WENT WRONG
   ---------------
   Script 10 started the 60-day clock at Loans.ExpectedClearDate -- the date a
   loan was SCHEDULED to mature. Micromart's rule is that the clock starts when
   the customer actually finished paying: the day IsCleared became 1 / the day
   their OLB reached 0.

   For a performing customer those two dates are close, so the bug is invisible.
   For an NPL customer they are years apart. Borrower 5485's loan matured on
   2022-07-25; the job called them 1509 days dormant and moved them at 02:34 on
   11 Sep -- when in fact they had cleared that loan the previous afternoon.
   Rewarding a four-year recovery by moving the customer off their officer's
   book the same night is the exact opposite of the intent.

   MEASURED ON THE LIVE BOOK, 11 Sep 2026:
       500 customers moved (the @MaxBorrowers ceiling was hit)
       325 were genuinely dormant 60+ days  -> LEAVE THEM ON 3005
       175 had cleared within the last 60 days -> ROLL BACK
             26 of them had cleared in the last 7 days
             16 within 8-14 days
             42 within 15-30 days
             91 within 31-59 days

   WHAT THIS SCRIPT DOES AND DOES NOT UNDO
   ---------------------------------------
     UNDONE   EntityId / EntityUnit / EntityAgent on the borrower, restored from
              MicroEazyDormancyLog.FromUnit / FromAgent (verified: populated for
              all 500, and Borrowers.OldAgent agrees with the log on all 500).
     UNDONE   EntityId on every child row: Loans, loanSchedule,
              loanChargesSchedule, CustomerStatement, ManagedLoans, Journals,
              LoanGraduationHistory, STKPaymentRequests.
     UNDONE   The 83 notification e-mails still sitting unsent in dbo.Mails.

     NOT UNDONE -- THE SMS. All 500 messages were already drained (isSent = 1)
              by the time this was found. 175 customers have been told their
              account moved when it has not. That needs a business decision on
              a correction SMS; this script does not send one.

     NOT UNDONE -- THE PIN. Script 10 set UssdPin and MobileAppPassword to NULL.
              The old value was a BCrypt hash and is gone; 481 of the 500 are
              still NULL. There is nothing in the database to restore it from.
              This is harmless in practice -- a NULL PIN is a supported state and
              the USSD service walks the customer through setting a new one on
              their next dial -- but it is not a reversal, and Micromart should
              be told rather than discover it.

   ORDER: run this, then 13-fix-dormancy-clock.sql, before 02:30 tonight.
   ==========================================================================*/
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* -- audit column for the reversal, added once ---------------------------- */
IF COL_LENGTH('dbo.MicroEazyDormancyLog', 'ReversedAt') IS NULL
    ALTER TABLE dbo.MicroEazyDormancyLog ADD ReversedAt DATETIME2 NULL;
GO

/* ---------------------------------------------------------------------------
   FLIP @DryRun TO 0 TO APPLY. It reports and changes nothing while it is 1.
   --------------------------------------------------------------------------*/
DECLARE @DryRun      BIT  = 1;
DECLARE @RunDate     DATE = '2026-09-11';   -- the dormancy run being reversed
DECLARE @DormantDays INT  = 60;
DECLARE @FromEntity  INT  = 3002;           -- where they belong
DECLARE @ToEntity    INT  = 3005;           -- where they were wrongly parked
DECLARE @OwnAgent    INT  = 9096;           -- Emmanuel Birgen, for the audit trail

/* ===========================================================================
   1 · WHO WAS MOVED WRONGLY
   ---------------------------------------------------------------------------
   The true clock: per loan, the LAST moment the ledger showed LoanBalance = 0;
   per customer, the latest of those. "Last", not "first", because a penalty can
   push a settled loan back above zero -- what matters is when they finished for
   good. Loans.DateCleared is not usable: it is NULL on all 344,332 rows in the
   book, so the ledger is the only witness to when a loan actually cleared.
   ======================================================================== */
IF OBJECT_ID('tempdb..#moved') IS NOT NULL DROP TABLE #moved;
SELECT d.LogId, d.BorrowerId, d.FromUnit, d.FromAgent, d.ToAgent,
       d.LastMaturity, d.DaysDormant AS DaysClaimed, d.LoansMoved
INTO #moved
FROM dbo.MicroEazyDormancyLog d
WHERE CAST(d.MovedAt AS DATE) = @RunDate
  AND d.ReversedAt IS NULL;
CREATE CLUSTERED INDEX IX_moved ON #moved(BorrowerId);

IF OBJECT_ID('tempdb..#truth') IS NOT NULL DROP TABLE #truth;
SELECT m.BorrowerId,
       (SELECT MAX(z.ZeroDate)
          FROM dbo.Loans l
          CROSS APPLY (SELECT MAX(cs.TransactedDate) AS ZeroDate
                         FROM dbo.CustomerStatement cs
                        WHERE cs.LoanId = l.id AND cs.LoanBalance = 0) z
         WHERE l.BorrowerId = m.BorrowerId) AS TrueClearDate
INTO #truth
FROM #moved m;
CREATE CLUSTERED INDEX IX_truth ON #truth(BorrowerId);

IF OBJECT_ID('tempdb..#wrong') IS NOT NULL DROP TABLE #wrong;
SELECT m.LogId, m.BorrowerId, m.FromUnit, m.FromAgent,
       m.LastMaturity, m.DaysClaimed, m.LoansMoved,
       t.TrueClearDate,
       DATEDIFF(DAY, t.TrueClearDate, GETDATE()) AS TrueDaysDormant
INTO #wrong
FROM #moved m
JOIN #truth t ON t.BorrowerId = m.BorrowerId
WHERE t.TrueClearDate IS NULL                                    -- cannot prove 60 days: hold
   OR DATEDIFF(DAY, t.TrueClearDate, GETDATE()) < @DormantDays;  -- cleared too recently
CREATE CLUSTERED INDEX IX_wrong ON #wrong(BorrowerId);

IF OBJECT_ID('tempdb..#wloans') IS NOT NULL DROP TABLE #wloans;
SELECT l.id AS LoanId INTO #wloans
FROM dbo.Loans l JOIN #wrong w ON w.BorrowerId = l.BorrowerId
WHERE l.EntityId = @ToEntity;
CREATE CLUSTERED INDEX IX_wloans ON #wloans(LoanId);

DECLARE @n     INT = (SELECT COUNT(*) FROM #wrong);
DECLARE @all   INT = (SELECT COUNT(*) FROM #moved);
DECLARE @nLoan INT = (SELECT COUNT(*) FROM #wloans);

PRINT '--------------------------------------------------------------';
PRINT 'Dormancy run reversed .... ' + CONVERT(VARCHAR(10), @RunDate, 120);
PRINT 'Customers in that run .... ' + CAST(@all AS VARCHAR(10));
PRINT 'Wrongly moved ............ ' + CAST(@n AS VARCHAR(10));
PRINT 'Correctly moved (kept) ... ' + CAST(@all - @n AS VARCHAR(10));
PRINT 'Loans to return .......... ' + CAST(@nLoan AS VARCHAR(10));
PRINT '--------------------------------------------------------------';

IF @DryRun = 1
BEGIN
    SELECT 'would roll back' AS action, w.BorrowerId,
           b.firstName + ' ' + ISNULL(b.otherName,'') AS Customer, b.PhoneNumber,
           w.LastMaturity      AS MaturityTheJobUsed,
           w.DaysClaimed       AS DaysTheJobClaimed,
           CAST(w.TrueClearDate AS DATE) AS ActuallyClearedOn,
           w.TrueDaysDormant,
           DATEADD(DAY, @DormantDays, CAST(w.TrueClearDate AS DATE)) AS EligibleFrom,
           w.FromUnit AS ReturnToUnit, w.FromAgent AS ReturnToAgent, w.LoansMoved
    FROM #wrong w JOIN dbo.Borrowers b ON b.ID = w.BorrowerId
    ORDER BY w.TrueDaysDormant ASC;

    PRINT 'DRY RUN -- nothing changed. Set @DryRun = 0 to apply.';
END
ELSE IF @n = 0
BEGIN
    PRINT 'Nothing to roll back.';
END
ELSE
BEGIN
    /* =======================================================================
       2 · PUT THEM BACK
       -----------------------------------------------------------------------
       CustomerStatement (3.5M), Journals (6.8M), loanSchedule (2.0M) and
       loanChargesSchedule (618k) are heaps with no index at all, so each UPDATE
       below is a full scan -- roughly 13M rows of scanning inside one
       transaction, on a server that also carries live ServiceSuite traffic.
       Run it in a quiet window, not mid-morning.
       ==================================================================== */
    BEGIN TRANSACTION;

        UPDATE x SET x.EntityId = @FromEntity FROM dbo.loanSchedule        x JOIN #wloans t ON t.LoanId = x.Loanid WHERE x.EntityId = @ToEntity;
        UPDATE x SET x.EntityId = @FromEntity FROM dbo.loanChargesSchedule x JOIN #wloans t ON t.LoanId = x.Loanid WHERE x.EntityId = @ToEntity;
        UPDATE x SET x.EntityId = @FromEntity FROM dbo.CustomerStatement   x JOIN #wloans t ON t.LoanId = x.LoanId WHERE x.EntityId = @ToEntity;
        UPDATE x SET x.EntityId = @FromEntity FROM dbo.ManagedLoans        x JOIN #wloans t ON t.LoanId = x.LoanId WHERE x.EntityId = @ToEntity;

        UPDATE x SET x.EntityId = @FromEntity FROM dbo.Journals              x JOIN #wrong w ON w.BorrowerId = x.BorrowerId WHERE x.EntityId = @ToEntity;
        UPDATE x SET x.EntityId = @FromEntity FROM dbo.LoanGraduationHistory x JOIN #wrong w ON w.BorrowerId = x.BorrowerId WHERE x.EntityId = @ToEntity;
        UPDATE x SET x.EntityId = @FromEntity FROM dbo.STKPaymentRequests    x JOIN #wrong w ON w.BorrowerId = x.BorrowerId WHERE x.EntityId = @ToEntity;

        /* the loans last, so the child joins above still matched on @ToEntity */
        UPDATE l SET l.EntityId = @FromEntity
        FROM dbo.Loans l JOIN #wloans t ON t.LoanId = l.id;

        /* the customer -- back to their own branch and their own officer */
        UPDATE b
           SET b.EntityId    = @FromEntity,
               b.EntityUnit  = w.FromUnit,
               b.EntityAgent = w.FromAgent,
               b.OldAgent    = NULL,          -- trail the move left; no longer true
               b.UpdatedBy   = @OwnAgent,
               b.UpdatedDate = GETDATE()
        FROM dbo.Borrowers b JOIN #wrong w ON w.BorrowerId = b.ID;

        /* pull the e-mails that have not gone out yet (the SMS already has) */
        DELETE m
        FROM dbo.Mails m
        JOIN dbo.Borrowers b ON LTRIM(RTRIM(b.EmailAddress)) = LTRIM(RTRIM(m.tomail))
        JOIN #wrong w        ON w.BorrowerId = b.ID
        WHERE m.isSent = 0
          AND m.CreatedBy = @OwnAgent
          AND m.Subject = 'Your account has moved to Micromart Fintech'
          AND CAST(m.CreatedDate AS DATE) = @RunDate;

        /* say so on the customer's file */
        INSERT INTO dbo.BorrowerComments (borroweId, Comment, CreatedBy, DateCreated)
        SELECT w.BorrowerId,
               LEFT('Returned to MICROMART AFRICA (3002) under agent '
             + CAST(w.FromAgent AS VARCHAR(10))
             + '. Dormancy move of ' + CONVERT(VARCHAR(10), @RunDate, 120)
             + ' used loan maturity, not settlement: cleared '
             + CONVERT(VARCHAR(10), w.TrueClearDate, 120)
             + ' (' + CAST(w.TrueDaysDormant AS VARCHAR(10)) + ' days ago). PIN reset stands.', 250),
               @OwnAgent, GETDATE()
        FROM #wrong w;

        UPDATE d SET d.ReversedAt = SYSDATETIME(),
                     d.Note = LEFT(ISNULL(d.Note,'') + ' | REVERSED '
                            + CONVERT(VARCHAR(10), GETDATE(), 120)
                            + ': cleared ' + CONVERT(VARCHAR(10), w.TrueClearDate, 120)
                            + ', only ' + CAST(w.TrueDaysDormant AS VARCHAR(10)) + ' days dormant.', 400)
        FROM dbo.MicroEazyDormancyLog d JOIN #wrong w ON w.LogId = d.LogId;

    COMMIT TRANSACTION;

    PRINT 'Rolled back ' + CAST(@n AS VARCHAR(10)) + ' customer(s) to Micromart Africa (3002).';
    PRINT 'REMINDER: their SMS was already delivered, and their USSD PIN is still NULL.';
END
GO

/* ---------------------------------------------------------------------------
   3 · PROOF. Every number here should be zero after a real run.
   --------------------------------------------------------------------------*/
SELECT 'borrowers still on 3005' AS check_, COUNT(*) AS should_be_zero
FROM dbo.MicroEazyDormancyLog d JOIN dbo.Borrowers b ON b.ID = d.BorrowerId
WHERE d.ReversedAt IS NOT NULL AND b.EntityId <> 3002
UNION ALL
SELECT 'their loans still on 3005', COUNT(*)
FROM dbo.MicroEazyDormancyLog d JOIN dbo.Loans l ON l.BorrowerId = d.BorrowerId
WHERE d.ReversedAt IS NOT NULL AND l.EntityId <> 3002
UNION ALL
SELECT 'their statement rows still on 3005', COUNT(*)
FROM dbo.MicroEazyDormancyLog d
JOIN dbo.Loans l ON l.BorrowerId = d.BorrowerId
JOIN dbo.CustomerStatement cs ON cs.LoanId = l.id
WHERE d.ReversedAt IS NOT NULL AND cs.EntityId <> 3002
UNION ALL
SELECT 'their unsent move e-mails', COUNT(*)
FROM dbo.MicroEazyDormancyLog d
JOIN dbo.Borrowers b ON b.ID = d.BorrowerId
JOIN dbo.Mails m ON LTRIM(RTRIM(m.tomail)) = LTRIM(RTRIM(b.EmailAddress))
WHERE d.ReversedAt IS NOT NULL AND m.isSent = 0
  AND m.Subject = 'Your account has moved to Micromart Fintech';
GO
