/* ============================================================================
   13 · FIX THE DORMANCY CLOCK

   Script 10 measured dormancy from Loans.ExpectedClearDate -- when a loan was
   DUE to finish. Micromart's rule is that dormancy starts when the customer
   actually finished: the day IsCleared became 1, the day they paid off the last
   OLB, the day their OLB reached 0. Those are the same event.

   For a customer who paid on time the two dates differ by days and the bug is
   invisible. For an NPL customer who ran two years late and then settled, the
   old clock said "1509 days dormant" on the day after they finished paying. On
   11 Sep 2026 that moved 175 freshly-recovered customers off their officer's
   book. Script 12 puts them back; this script stops it happening again.

   -- WHERE THE TRUE DATE COMES FROM -------------------------------------------
   Not from Loans.DateCleared. That column exists and is the obvious candidate,
   but it is NULL on all 344,332 rows in the book -- ServiceSuite has never
   written to it. Checked on 11 Sep 2026 across entities 3002/3003/3005:
   205,162 cleared loans, 0 with a DateCleared.

   So the ledger is the only witness. CustomerStatement carries a running
   LoanBalance per transaction, so the moment a loan hit zero is the
   TransactedDate of the row where LoanBalance = 0. Per loan we take the LAST
   such moment, not the first: a late-payment penalty can push a settled loan
   back above zero and the customer then pays it down again, and what matters is
   when they finished for good. Per customer we take the latest across all their
   loans.

   Verified against the two customers Micromart raised:
     borrower 132659, loan 392908 -- matured 2026-01-28, ledger hit zero
       2026-09-02. Old clock: 226 days. True: 9 days. Moves 2026-11-01.
     borrower 148839, loan 420215 -- matured 2026-06-18, ledger hit zero
       2026-09-03. Old clock: 85 days. True: 8 days. Moves 2026-11-02.

   -- WHAT ELSE CHANGED ---------------------------------------------------------
   * A customer whose settled loan HAS ledger rows but never shows a zero is now
     HELD rather than moved. We cannot prove 60 days for them, and moving
     somebody we cannot date is how this went wrong the first time. The dry run
     counts them under Unverifiable so they can be looked at by hand. On the
     3002 book today that is 2 customers. Loans with no ledger row at all are a
     different case -- pre-2022 loans that predate CustomerStatement, 8
     customers -- and they fall back to maturity, which nothing can contradict.
   * "All loans cleared" now also requires the balance to actually be zero.
     LoanCleared = 1 with a positive LoanBalance exists on 2 loans in the book;
     they should not count as settled.
   * The queue is ordered by the true clear date, so when the @MaxBorrowers
     ceiling bites it is the longest-settled customers who go first.
   * MicroEazyDormancyLog gains LastClearedOn, so the audit trail records the
     date the decision was actually based on, next to the maturity it used to
     use.

   The 02:30 job in script 10.3 calls this procedure by name and is unchanged --
   installing this is enough for tonight's run to use the new rule.
   ==========================================================================*/
USE Serviceconnect;
GO
SET NOCOUNT ON;
GO

/* -- record the basis of the decision, not just the maturity --------------- */
IF COL_LENGTH('dbo.MicroEazyDormancyLog', 'LastClearedOn') IS NULL
    ALTER TABLE dbo.MicroEazyDormancyLog ADD LastClearedOn DATE NULL;
GO

CREATE OR ALTER PROCEDURE dbo.sp_MicroEazy_MigrateDormantToFintech
    @DryRun        BIT = 1,     -- default is SAFE: reports, changes nothing
    @DormantDays   INT = 60,
    @MaxBorrowers  INT = 500,   -- ceiling per run, so one bad day is bounded
    @SendSms       BIT = 1,
    @SendEmail     BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FromEntity INT = 3002,
            @ToEntity   INT = 3005,
            @ToUnit     INT = 129,     -- Main Office, the only branch of 3005
            @HeadAgent  INT = 9098,    -- Geoffrey Njane
            @OwnAgent   INT = 9096;    -- Emmanuel Birgen (console / shelf origin)

    /* -- the destination must be sound before anybody is parked on it -- */
    IF NOT EXISTS (SELECT 1 FROM dbo.UserMaster
                   WHERE ID = @HeadAgent AND ISNULL(UserStatus,0) = 1 AND ISNULL(OrganizationUnit,0) = @ToUnit)
    BEGIN
        RAISERROR('Dormancy service halted: user %d is not active in unit %d. Run 01-fix-destination.sql.', 16, 1, @HeadAgent, @ToUnit);
        RETURN;
    END

    /* ---------------------------------------------------------------------
       THE CLOCK -- when each loan last stood at zero, from the ledger.
       Pulled once into a temp table: CustomerStatement is a 3.5M-row heap with
       no index, so this is one scan rather than one per borrower.

       LedgerRows is carried alongside so the three cases can be told apart:
         has a zero row      -> that date is the truth
         no ledger rows AT ALL -> nothing can contradict the maturity date, so
                                fall back to it. These are pre-2022 loans that
                                predate CustomerStatement; 8 customers on the
                                3002 book today. Holding them would be wrong --
                                they really are long dormant.
         ledger rows but never zero -> an anomaly (2 customers today). We cannot
                                date the settlement, so we HOLD rather than
                                guess. Holding is reversible; moving is not.
       --------------------------------------------------------------------- */
    IF OBJECT_ID('tempdb..#ledger') IS NOT NULL DROP TABLE #ledger;
    SELECT cs.LoanId,
           COUNT(*)                                                       AS LedgerRows,
           MAX(CASE WHEN cs.LoanBalance = 0 THEN cs.TransactedDate END)   AS ZeroDate
    INTO #ledger
    FROM dbo.CustomerStatement cs
    JOIN dbo.Loans l ON l.id = cs.LoanId AND l.EntityId = @FromEntity
    GROUP BY cs.LoanId;
    CREATE CLUSTERED INDEX IX_ledger ON #ledger(LoanId);

    /* ---------------------------------------------------------------------
       WHO QUALIFIES
       --------------------------------------------------------------------- */
    IF OBJECT_ID('tempdb..#book') IS NOT NULL DROP TABLE #book;
    SELECT l.BorrowerId,
           /* a loan counts as settled only if it is flagged cleared AND the
              balance really is gone */
           MAX(CASE WHEN l.LoanCleared = 1 AND ISNULL(l.LoanBalance, 0) <= 0
                    THEN 0 ELSE 1 END)                       AS AnyOpen,
           MAX(CAST(l.ExpectedClearDate AS DATE))            AS LastMaturity,
           MAX(COALESCE(d.ZeroDate,
                        CASE WHEN d.LedgerRows IS NULL
                             THEN CAST(l.ExpectedClearDate AS DATETIME) END)) AS LastClearedOn,
           SUM(CASE WHEN d.LedgerRows IS NOT NULL AND d.ZeroDate IS NULL
                    THEN 1 ELSE 0 END)                       AS UndatableLoans,
           COUNT(*)                                          AS LoanCount
    INTO #book
    FROM dbo.Loans l
    LEFT JOIN #ledger d ON d.LoanId = l.id
    WHERE l.EntityId = @FromEntity
    GROUP BY l.BorrowerId;
    CREATE CLUSTERED INDEX IX_book ON #book(BorrowerId);

    IF OBJECT_ID('tempdb..#eligible') IS NOT NULL DROP TABLE #eligible;

    SELECT TOP (@MaxBorrowers)
           b.ID                AS BorrowerId,
           b.EntityUnit        AS FromUnit,
           b.EntityAgent       AS FromAgent,
           b.firstName, b.otherName, b.PhoneNumber, b.EmailAddress,
           x.LastMaturity,
           CAST(x.LastClearedOn AS DATE)                        AS LastClearedOn,
           DATEDIFF(DAY, x.LastClearedOn, GETDATE())            AS DaysDormant,
           x.LoanCount,
           CASE WHEN b.CreatedBy = @OwnAgent
                  OR b.CreatedBy IN (SELECT ID FROM dbo.UserMaster WHERE EntityID = @ToEntity)
                THEN @OwnAgent ELSE @HeadAgent END AS ToAgent
    INTO #eligible
    FROM #book x
    JOIN dbo.Borrowers b
      ON b.ID = x.BorrowerId
     AND b.EntityId = @FromEntity
    WHERE x.AnyOpen = 0                                                    -- every loan settled
      AND x.UndatableLoans = 0                                             -- and every one datable
      AND x.LastClearedOn IS NOT NULL                                      -- never-borrowed do not move
      /* THE 60-DAY CLOCK, ON SETTLEMENT -- the day the last OLB reached zero,
         not the day the loan was scheduled to mature. This one line is the
         whole fix; change it here if the rule ever changes again. */
      AND DATEDIFF(DAY, x.LastClearedOn, GETDATE()) >= @DormantDays
      AND ISNULL(b.AccountStatus, 1) <> 0                                  -- not a closed record
      /* never move somebody whose identity is already on the fintech book --
         script 05's lock would reject it, and rightly */
      AND NOT EXISTS (
            SELECT 1 FROM dbo.Borrowers s
            WHERE s.EntityId = @ToEntity AND ISNULL(s.AccountStatus,1) <> 0
              AND ( (NULLIF(LTRIM(RTRIM(b.NationalID)),  '') IS NOT NULL AND LTRIM(RTRIM(s.NationalID))  = LTRIM(RTRIM(b.NationalID)))
                 OR (NULLIF(LTRIM(RTRIM(b.PhoneNumber)), '') IS NOT NULL AND LTRIM(RTRIM(s.PhoneNumber)) = LTRIM(RTRIM(b.PhoneNumber))) ))
    ORDER BY x.LastClearedOn ASC;   -- longest settled first when the ceiling bites

    CREATE CLUSTERED INDEX IX_eligible ON #eligible(BorrowerId);
    DECLARE @count INT = (SELECT COUNT(*) FROM #eligible);

    IF @DryRun = 1
    BEGIN
        PRINT 'DRY RUN -- nothing changed. Eligible customers: ' + CAST(@count AS VARCHAR(20));

        /* the customers we deliberately will not touch, and why */
        SELECT 'held - settled but the ledger never shows a zero' AS reason,
               COUNT(*) AS Unverifiable
        FROM #book WHERE AnyOpen = 0 AND UndatableLoans > 0;

        SELECT 'would move' AS action, e.*,
               DATEDIFF(DAY, e.LastMaturity, GETDATE()) AS DaysSinceMaturity_oldRule
        FROM #eligible e ORDER BY e.DaysDormant DESC;
        RETURN;
    END

    IF @count = 0
    BEGIN
        PRINT 'Nothing to move today.';
        RETURN;
    END

    /* ---------------------------------------------------------------------
       THE MOVE
       --------------------------------------------------------------------- */
    BEGIN TRANSACTION;

        /* the loans first, so the child restamps below can follow them */
        IF OBJECT_ID('tempdb..#loans') IS NOT NULL DROP TABLE #loans;
        SELECT l.id AS LoanId INTO #loans
        FROM dbo.Loans l JOIN #eligible e ON e.BorrowerId = l.BorrowerId
        WHERE l.EntityId = @FromEntity;
        CREATE CLUSTERED INDEX IX_loans ON #loans(LoanId);

        UPDATE l SET l.EntityId = @ToEntity
        FROM dbo.Loans l JOIN #loans t ON t.LoanId = l.id;

        /* every entity-stamped child of those loans */
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.loanSchedule        x JOIN #loans t ON t.LoanId = x.Loanid WHERE x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.loanChargesSchedule x JOIN #loans t ON t.LoanId = x.Loanid WHERE x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.CustomerStatement   x JOIN #loans t ON t.LoanId = x.LoanId WHERE x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.ManagedLoans        x JOIN #loans t ON t.LoanId = x.LoanId WHERE x.EntityId <> @ToEntity;

        /* and the children stamped against the borrower rather than the loan */
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.Journals              x JOIN #eligible e ON e.BorrowerId = x.BorrowerId WHERE x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.LoanGraduationHistory x JOIN #eligible e ON e.BorrowerId = x.BorrowerId WHERE x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.STKPaymentRequests    x JOIN #eligible e ON e.BorrowerId = x.BorrowerId WHERE x.EntityId <> @ToEntity;

        /* the customer themselves -- new book, head office, no RO, no stale PIN */
        UPDATE b
           SET b.EntityId          = @ToEntity,
               b.EntityUnit        = @ToUnit,
               b.OldAgent          = b.EntityAgent,   -- keep the trail of who held them
               b.EntityAgent       = e.ToAgent,
               b.UssdPin           = NULL,            -- customer sets their own on first dial
               b.MobileAppPassword = NULL,
               b.UpdatedBy         = @OwnAgent,
               b.UpdatedDate       = GETDATE()
        FROM dbo.Borrowers b JOIN #eligible e ON e.BorrowerId = b.ID;

        /* ------------------------------------------------------------------
           TELL THEM. Micromart's own sender ID, because the SMS row carries
           the entity and the entity owns the Africa's Talking credentials.
           ------------------------------------------------------------------ */
        IF @SendSms = 1
        INSERT INTO Notifications.dbo.SMS (smsMessage, smsto, EntityId, CreateDate, isSent, ScheduleDate, SmsProviderId)
        SELECT
            'Dear ' + LTRIM(RTRIM(ISNULL(e.firstName, 'Customer')))
          + ', your Micromart account has moved to Micromart Fintech. You can now '
          + 'apply for a loan from home - no branch visit, no agent. '
          + 'App: portal.servicesuitecloud.com  USSD: *483*490# '
          + 'Dial the USSD code to set your new PIN. PIN yako ni siri yako.',
            e.PhoneNumber, @ToEntity, GETDATE(), 0, GETDATE(), 5
        FROM #eligible e
        WHERE NULLIF(LTRIM(RTRIM(e.PhoneNumber)), '') IS NOT NULL;

        IF @SendEmail = 1
        INSERT INTO dbo.Mails (tomail, Subject, Message, CreatedBy, CreatedDate, Status, ScheduleDate, isSent)
        SELECT
            e.EmailAddress,
            /* Mails.Subject is varchar(50) -- keep this at or under 50 chars.
               The full 53-char wording overflowed and aborted the whole nightly
               transaction (error 2628) on 9 and 10 Sep 2026. */
            'Your account has moved to Micromart Fintech',
            'Dear ' + LTRIM(RTRIM(ISNULL(e.firstName, 'Customer'))) + ',' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Your Micromart account has moved to Micromart Fintech. You can now apply for a loan '
          + 'from the comfort of your home - no branch visit and no agent needed.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Mobile app:  https://portal.servicesuitecloud.com' + CHAR(13) + CHAR(10)
          + 'USSD:        *483*490#' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Dial *483*490# from ' + LTRIM(RTRIM(ISNULL(e.PhoneNumber, 'your registered number')))
          + ' and you will be asked to choose a new PIN. That PIN works on both the USSD '
          + 'service and the mobile app.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Keep your PIN secret. Micromart will never ask you for it.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Micromart Fintech',
            @OwnAgent, GETDATE(), 0, GETDATE(), 0
        FROM #eligible e
        WHERE NULLIF(LTRIM(RTRIM(e.EmailAddress)), '') IS NOT NULL
          AND e.EmailAddress LIKE '%_@_%._%';

        /* ------------------------------------------------------------------ */
        INSERT INTO dbo.MicroEazyDormancyLog
            (BorrowerId, FromEntityId, ToEntityId, FromUnit, FromAgent, ToAgent,
             LastMaturity, LastClearedOn, DaysDormant, LoansMoved, SmsQueued, MailQueued, Note)
        SELECT e.BorrowerId, @FromEntity, @ToEntity, e.FromUnit, e.FromAgent, e.ToAgent,
               e.LastMaturity, e.LastClearedOn, e.DaysDormant, e.LoanCount,
               CASE WHEN @SendSms = 1 AND NULLIF(LTRIM(RTRIM(e.PhoneNumber)),  '') IS NOT NULL THEN 1 ELSE 0 END,
               CASE WHEN @SendEmail = 1 AND NULLIF(LTRIM(RTRIM(e.EmailAddress)), '') IS NOT NULL THEN 1 ELSE 0 END,
               'Auto-migrated ' + CAST(e.DaysDormant AS NVARCHAR(10))
             + ' days after settling on ' + CONVERT(NVARCHAR(10), e.LastClearedOn, 120) + '.'
        FROM #eligible e;

        INSERT INTO dbo.BorrowerComments (borroweId, Comment, CreatedBy, DateCreated)
        SELECT e.BorrowerId,
               LEFT('Moved to MICROMART FINTECH (3005) by the dormancy service: all loans settled, '
             + 'last cleared ' + CONVERT(VARCHAR(10), e.LastClearedOn, 120)
             + ' (' + CAST(e.DaysDormant AS VARCHAR(10)) + ' days dormant).', 250),
               @OwnAgent, GETDATE()
        FROM #eligible e;

    COMMIT TRANSACTION;

    PRINT 'Dormancy service moved ' + CAST(@count AS VARCHAR(20)) + ' customer(s) to Micromart Fintech.';
END
GO

PRINT '13 complete. Dry-run it before 02:30:';
PRINT '   EXEC dbo.sp_MicroEazy_MigrateDormantToFintech;';
GO
