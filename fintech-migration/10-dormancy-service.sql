/* ============================================================================
   10 · THE DORMANCY SERVICE

   From today onwards, a customer on Micromart Africa (3002) whose loans are all
   cleared and whose last loan matured more than 60 days ago moves, by itself,
   to Micromart Fintech (3005) under Geoffrey Njane in Main Office -- with every
   one of their ledger rows -- and is told they can now borrow from home.

   Backlog on first run: ~568 customers (566 of whom have an email on file).

   -- THE CLOCK ---------------------------------------------------------------
   60 days after Loans.ExpectedClearDate, the scheduled maturity, per your
   ruling. Customers who have never taken a loan do not move. Both are single
   lines in the WHERE clause below and are commented, so the rule can be changed
   without re-reading the whole procedure.

   -- WHY NO PIN IS SENT IN THE MESSAGE ---------------------------------------
   Borrowers.UssdPin is a BCrypt hash and BCrypt cannot be computed in T-SQL.
   A SQL Agent job therefore cannot mint a working PIN -- and writing a plain
   number into that column would be worse than useless: BCrypt.Verify throws on
   a non-hash, which is exactly the defect script 07 exists to clear.

   So the service NULLs the PIN instead. That is already a supported state:
   Login.UssdPinStatus returns "no PIN set" and the USSD service routes the
   customer straight into its own set-your-PIN screen on their first dial. The
   customer chooses their own PIN, it is hashed by the code that owns hashing,
   and no PIN ever travels by SMS.

   If you would rather the message carry a pre-set PIN, this has to be the .NET
   worker instead of a SQL Agent job -- that was the trade-off behind the
   "where should the service run" question, and it is the one thing the SQL
   Agent option cannot do.

   INSTALL ORDER: run 01-07 first. This script installs a log table, a
   procedure, and a daily job. It does not move anybody until the job runs --
   or until you call the procedure yourself with @DryRun = 0.
   ==========================================================================*/
SET NOCOUNT ON;
GO

/* -------------------------------------------------------------------------
   10.1 · The log. One row per customer moved, forever.
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.MicroEazyDormancyLog') IS NULL
BEGIN
    CREATE TABLE dbo.MicroEazyDormancyLog (
        LogId          BIGINT IDENTITY(1,1) PRIMARY KEY,
        BorrowerId     INT           NOT NULL,
        MovedAt        DATETIME2     NOT NULL CONSTRAINT DF_MEDL_MovedAt DEFAULT SYSDATETIME(),
        FromEntityId   INT           NOT NULL,
        ToEntityId     INT           NOT NULL,
        FromUnit       INT           NULL,
        FromAgent      INT           NULL,
        ToAgent        INT           NOT NULL,
        LastMaturity   DATE          NULL,
        DaysDormant    INT           NULL,
        LoansMoved     INT           NULL,
        SmsQueued      BIT           NOT NULL CONSTRAINT DF_MEDL_Sms  DEFAULT 0,
        MailQueued     BIT           NOT NULL CONSTRAINT DF_MEDL_Mail DEFAULT 0,
        Note           NVARCHAR(400) NULL
    );
    CREATE NONCLUSTERED INDEX IX_MEDL_BorrowerId ON dbo.MicroEazyDormancyLog(BorrowerId);
    PRINT 'Created dbo.MicroEazyDormancyLog';
END
GO

/* -------------------------------------------------------------------------
   10.2 · The procedure.
          EXEC dbo.sp_MicroEazy_MigrateDormantToFintech;              -- dry run
          EXEC dbo.sp_MicroEazy_MigrateDormantToFintech @DryRun = 0;  -- for real
   ---------------------------------------------------------------------- */
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
       WHO QUALIFIES
       --------------------------------------------------------------------- */
    IF OBJECT_ID('tempdb..#eligible') IS NOT NULL DROP TABLE #eligible;

    SELECT TOP (@MaxBorrowers)
           b.ID                AS BorrowerId,
           b.EntityUnit        AS FromUnit,
           b.EntityAgent       AS FromAgent,
           b.firstName, b.otherName, b.PhoneNumber, b.EmailAddress,
           x.LastMaturity,
           DATEDIFF(DAY, x.LastMaturity, GETDATE()) AS DaysDormant,
           x.LoanCount,
           CASE WHEN b.CreatedBy = @OwnAgent
                  OR b.CreatedBy IN (SELECT ID FROM dbo.UserMaster WHERE EntityID = @ToEntity)
                THEN @OwnAgent ELSE @HeadAgent END AS ToAgent
    INTO #eligible
    FROM (
            SELECT l.BorrowerId,
                   MAX(CASE WHEN l.LoanCleared = 1 THEN 0 ELSE 1 END) AS AnyOpen,
                   MAX(CAST(l.ExpectedClearDate AS DATE))             AS LastMaturity,
                   COUNT(*)                                           AS LoanCount
            FROM dbo.Loans l
            WHERE l.EntityId = @FromEntity
            GROUP BY l.BorrowerId
         ) x
    JOIN dbo.Borrowers b
      ON b.ID = x.BorrowerId
     AND b.EntityId = @FromEntity
    WHERE x.AnyOpen = 0                                                    -- every loan cleared
      AND x.LastMaturity < DATEADD(DAY, -@DormantDays, CAST(GETDATE() AS DATE))  -- the 60-day clock, on MATURITY
      AND ISNULL(b.AccountStatus, 1) <> 0                                  -- not a closed record
      /* never move somebody whose identity is already on the fintech book --
         script 05's lock would reject it, and rightly */
      AND NOT EXISTS (
            SELECT 1 FROM dbo.Borrowers s
            WHERE s.EntityId = @ToEntity AND ISNULL(s.AccountStatus,1) <> 0
              AND ( (NULLIF(LTRIM(RTRIM(b.NationalID)),  '') IS NOT NULL AND LTRIM(RTRIM(s.NationalID))  = LTRIM(RTRIM(b.NationalID)))
                 OR (NULLIF(LTRIM(RTRIM(b.PhoneNumber)), '') IS NOT NULL AND LTRIM(RTRIM(s.PhoneNumber)) = LTRIM(RTRIM(b.PhoneNumber))) ))
    ORDER BY x.LastMaturity ASC;   -- longest dormant first

    CREATE CLUSTERED INDEX IX_eligible ON #eligible(BorrowerId);
    DECLARE @count INT = (SELECT COUNT(*) FROM #eligible);

    IF @DryRun = 1
    BEGIN
        PRINT 'DRY RUN -- nothing changed. Eligible customers: ' + CAST(@count AS VARCHAR(20));
        SELECT 'would move' AS action, * FROM #eligible ORDER BY DaysDormant DESC;
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
            'Your Micromart account has moved to Micromart Fintech',
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
             LastMaturity, DaysDormant, LoansMoved, SmsQueued, MailQueued, Note)
        SELECT e.BorrowerId, @FromEntity, @ToEntity, e.FromUnit, e.FromAgent, e.ToAgent,
               e.LastMaturity, e.DaysDormant, e.LoanCount,
               CASE WHEN @SendSms = 1 AND NULLIF(LTRIM(RTRIM(e.PhoneNumber)),  '') IS NOT NULL THEN 1 ELSE 0 END,
               CASE WHEN @SendEmail = 1 AND NULLIF(LTRIM(RTRIM(e.EmailAddress)), '') IS NOT NULL THEN 1 ELSE 0 END,
               'Auto-migrated after ' + CAST(e.DaysDormant AS NVARCHAR(10)) + ' days dormant.'
        FROM #eligible e;

        INSERT INTO dbo.BorrowerComments (borroweId, Comment, CreatedBy, DateCreated)
        SELECT e.BorrowerId,
               'Moved to MICROMART FINTECH (3005) by the dormancy service: all loans cleared, '
             + 'last maturity ' + CONVERT(VARCHAR(10), e.LastMaturity, 120)
             + ' (' + CAST(e.DaysDormant AS VARCHAR(10)) + ' days).',
               @OwnAgent, GETDATE()
        FROM #eligible e;

    COMMIT TRANSACTION;

    PRINT 'Dormancy service moved ' + CAST(@count AS VARCHAR(20)) + ' customer(s) to Micromart Fintech.';
END
GO

/* -------------------------------------------------------------------------
   10.3 · The daily job. 02:30, every day.
   ---------------------------------------------------------------------- */
USE msdb;
GO
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'MicroEazy - Dormancy migration to Fintech')
    EXEC msdb.dbo.sp_delete_job @job_name = N'MicroEazy - Dormancy migration to Fintech', @delete_unused_schedule = 1;

EXEC msdb.dbo.sp_add_job
     @job_name    = N'MicroEazy - Dormancy migration to Fintech',
     @description = N'Moves Micromart Africa (3002) customers whose loans are all cleared and whose last loan matured over 60 days ago to Micromart Fintech (3005), under Geoffrey Njane in Main Office, with every child row. Notifies by SMS and email. See dbo.MicroEazyDormancyLog.',
     @enabled     = 1;

EXEC msdb.dbo.sp_add_jobstep
     @job_name   = N'MicroEazy - Dormancy migration to Fintech',
     @step_name  = N'Migrate dormant customers',
     @subsystem  = N'TSQL',
     @database_name = N'Serviceconnect',
     @command    = N'EXEC dbo.sp_MicroEazy_MigrateDormantToFintech @DryRun = 0, @DormantDays = 60, @MaxBorrowers = 500;',
     @retry_attempts = 2,
     @retry_interval = 10;

EXEC msdb.dbo.sp_add_schedule
     @schedule_name  = N'MicroEazy daily 0230',
     @freq_type      = 4,          -- daily
     @freq_interval  = 1,
     @active_start_time = 023000;

EXEC msdb.dbo.sp_attach_schedule
     @job_name      = N'MicroEazy - Dormancy migration to Fintech',
     @schedule_name = N'MicroEazy daily 0230';

EXEC msdb.dbo.sp_add_jobserver
     @job_name = N'MicroEazy - Dormancy migration to Fintech';
GO

USE Serviceconnect;
GO
PRINT '10 complete. Dry-run it before the first scheduled fire:';
PRINT '   EXEC dbo.sp_MicroEazy_MigrateDormantToFintech;';
GO
