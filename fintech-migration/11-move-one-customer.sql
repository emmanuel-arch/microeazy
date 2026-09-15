/*==========================================================================
  11 · MOVE ONE NAMED CUSTOMER TO MICROMART FINTECH (3005)

  The manual counterpart to 10-dormancy-service.sql. Same move, same child
  restamps, same notifications, same log -- but for one customer you name,
  and without the 60-day dormancy rule, because a manual move is a human
  decision rather than a clock.

  It is NOT a shortcut past the things that protect the data:

    * the destination is checked exactly as the nightly job checks it;
    * an identity already present on the other book is refused UP FRONT,
      with the same information script 05's trigger would throw -- so you
      get a sentence instead of a rolled-back transaction;
    * an OPEN LOAN is refused unless you pass @AllowOpenLoans = 1. Moving a
      live loan between books is an accounting event: the balance leaves one
      portfolio and joins another and the customer changes collections
      queue. That is Geoffrey's call, not a side effect of this script.
      (Same reasoning that keeps the 58 out of 04-merge-duplicates.sql.)

  DRY RUN IS THE DEFAULT. It reports and changes nothing.

      EXEC dbo.sp_MicroEazy_MoveCustomerToFintech @PhoneNumber = '254719112304';
      EXEC dbo.sp_MicroEazy_MoveCustomerToFintech @PhoneNumber = '254719112304', @DryRun = 0;

  Like the nightly job this sets UssdPin and MobileAppPassword to NULL --
  BCrypt cannot be computed in T-SQL, so the customer sets their own PIN on
  the USSD set-PIN screen. No PIN travels by SMS.

  Note on speed: Journals, CustomerStatement and loanSchedule are heaps with
  no indexes, so the child restamps full-scan even for one customer. Expect
  a few minutes, and prefer running it outside business hours.
  ==========================================================================*/
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_MicroEazy_MoveCustomerToFintech
    @BorrowerId      INT           = NULL,   -- give ONE of these three
    @PhoneNumber     VARCHAR(30)   = NULL,
    @NationalID      VARCHAR(50)   = NULL,
    @DryRun          BIT           = 1,      -- default is SAFE
    @AllowOpenLoans  BIT           = 0,      -- deliberate override, see header
    @RequireDormancy BIT           = 0,      -- 1 = also enforce the 60-day rule
    @DormantDays     INT           = 60,
    @SendSms         BIT           = 1,
    @SendEmail       BIT           = 1,
    @Reason          NVARCHAR(200) = NULL    -- goes into the log and the comment
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FromEntity INT = 3002,
            @ToEntity   INT = 3005,
            @ToUnit     INT = 129,     -- Main Office, the only branch of 3005
            @HeadAgent  INT = 9098,    -- Geoffrey Njane
            @OwnAgent   INT = 9096;    -- Emmanuel Birgen (console origin)

    /* -- 1 · the destination must be sound before anybody is parked on it -- */
    IF NOT EXISTS (SELECT 1 FROM dbo.UserMaster
                   WHERE ID = @HeadAgent AND ISNULL(UserStatus,0) = 1 AND ISNULL(OrganizationUnit,0) = @ToUnit)
    BEGIN
        RAISERROR('Halted: user %d is not active in unit %d. Run 01-fix-destination.sql.', 16, 1, @HeadAgent, @ToUnit);
        RETURN;
    END

    /* -- 2 · resolve exactly one customer -------------------------------- */
    IF (CASE WHEN @BorrowerId IS NULL THEN 0 ELSE 1 END
      + CASE WHEN NULLIF(LTRIM(RTRIM(@PhoneNumber)),'') IS NULL THEN 0 ELSE 1 END
      + CASE WHEN NULLIF(LTRIM(RTRIM(@NationalID)), '') IS NULL THEN 0 ELSE 1 END) <> 1
    BEGIN
        RAISERROR('Give exactly one of @BorrowerId, @PhoneNumber or @NationalID.', 16, 1);
        RETURN;
    END

    IF OBJECT_ID('tempdb..#one') IS NOT NULL DROP TABLE #one;
    SELECT b.ID AS BorrowerId, b.EntityId, b.EntityUnit AS FromUnit, b.EntityAgent AS FromAgent,
           b.firstName, b.otherName, b.PhoneNumber, b.EmailAddress, b.NationalID, b.CreatedBy
    INTO #one
    FROM dbo.Borrowers b
    WHERE ISNULL(b.AccountStatus, 1) <> 0
      AND (   (@BorrowerId  IS NOT NULL AND b.ID = @BorrowerId)
           OR (@PhoneNumber IS NOT NULL AND LTRIM(RTRIM(b.PhoneNumber)) = LTRIM(RTRIM(@PhoneNumber)))
           OR (@NationalID  IS NOT NULL AND LTRIM(RTRIM(b.NationalID))  = LTRIM(RTRIM(@NationalID))) );

    DECLARE @hits INT = (SELECT COUNT(*) FROM #one);

    IF @hits = 0
    BEGIN
        RAISERROR('No active borrower matches that identifier. Nothing done.', 16, 1);
        RETURN;
    END

    IF @hits > 1
    BEGIN
        PRINT 'Ambiguous -- that identifier matches more than one active borrower:';
        SELECT BorrowerId, EntityId, firstName, otherName, PhoneNumber, NationalID FROM #one;
        RAISERROR('Ambiguous identifier: %d active borrowers matched. Re-run with @BorrowerId.', 16, 1, @hits);
        RETURN;
    END

    DECLARE @Id        INT           = (SELECT BorrowerId FROM #one),
            @OnEntity  INT           = (SELECT EntityId   FROM #one),
            @Name      NVARCHAR(200) = (SELECT LTRIM(RTRIM(ISNULL(firstName,'') + ' ' + ISNULL(otherName,''))) FROM #one),
            @CreatedBy INT           = (SELECT CreatedBy  FROM #one);

    IF @OnEntity = @ToEntity
    BEGIN
        PRINT 'Borrower ' + CAST(@Id AS VARCHAR(20)) + ' (' + @Name + ') is ALREADY on Micromart Fintech (3005). Nothing to do.';
        RETURN;
    END

    IF @OnEntity <> @FromEntity
    BEGIN
        RAISERROR('Borrower %d is on entity %d, not Micromart Africa (3002). This procedure only moves 3002 -> 3005.', 16, 1, @Id, @OnEntity);
        RETURN;
    END

    /* -- 3 · the identity lock, checked BEFORE any work ------------------ */
    DECLARE @twin NVARCHAR(1000) = NULL;
    SELECT TOP 1 @twin =
           'borrower ' + CAST(t.ID AS NVARCHAR(20))
         + ' (' + LTRIM(RTRIM(ISNULL(t.firstName,'') + ' ' + ISNULL(t.otherName,''))) + ')'
         + ' on entity ' + CAST(t.EntityId AS NVARCHAR(10))
         + ', matched on ' + CASE WHEN NULLIF(LTRIM(RTRIM(o.NationalID)),'') IS NOT NULL
                                       AND LTRIM(RTRIM(t.NationalID)) = LTRIM(RTRIM(o.NationalID))
                                  THEN 'national ID ' + LTRIM(RTRIM(o.NationalID))
                                  ELSE 'phone number ' + LTRIM(RTRIM(o.PhoneNumber)) END
    FROM #one o
    JOIN dbo.Borrowers t
      ON  t.ID <> o.BorrowerId
      AND t.EntityId IN (3002, 3005)
      AND ISNULL(t.AccountStatus,1) <> 0
      AND ( (NULLIF(LTRIM(RTRIM(o.NationalID)),  '') IS NOT NULL AND LTRIM(RTRIM(t.NationalID))  = LTRIM(RTRIM(o.NationalID)))
         OR (NULLIF(LTRIM(RTRIM(o.PhoneNumber)), '') IS NOT NULL AND LTRIM(RTRIM(t.PhoneNumber)) = LTRIM(RTRIM(o.PhoneNumber))) );

    IF @twin IS NOT NULL
    BEGIN
        RAISERROR('Refused: this identity already exists as %s. Script 05''s lock would reject the move. Merge the records first -- see 04-merge-duplicates.sql.', 16, 1, @twin);
        RETURN;
    END

    /* -- 4 · loan position ----------------------------------------------- */
    DECLARE @LoanCount    INT  = (SELECT COUNT(*) FROM dbo.Loans WHERE EntityId = @FromEntity AND BorrowerId = @Id),
            @OpenLoans    INT  = (SELECT COUNT(*) FROM dbo.Loans WHERE EntityId = @FromEntity AND BorrowerId = @Id AND ISNULL(LoanCleared,0) = 0),
            @LastMaturity DATE = (SELECT MAX(CAST(ExpectedClearDate AS DATE)) FROM dbo.Loans
                                   WHERE EntityId = @FromEntity AND BorrowerId = @Id AND ExpectedClearDate IS NOT NULL);

    DECLARE @DaysDormant INT = CASE WHEN @LastMaturity IS NULL THEN NULL
                                    ELSE DATEDIFF(DAY, @LastMaturity, CAST(GETDATE() AS DATE)) END;

    IF @OpenLoans > 0 AND @AllowOpenLoans = 0
    BEGIN
        RAISERROR('Refused: borrower %d has %d OPEN loan(s) on 3002. Moving a live loan between books is an accounting event -- the balance leaves one portfolio and joins another. Get the decision made, then re-run with @AllowOpenLoans = 1.', 16, 1, @Id, @OpenLoans);
        RETURN;
    END

    IF @RequireDormancy = 1 AND (@DaysDormant IS NULL OR @DaysDormant < @DormantDays)
    BEGIN
        RAISERROR('Refused: @RequireDormancy = 1 and this customer is %d day(s) past last maturity, under the %d-day rule.', 16, 1, @DaysDormant, @DormantDays);
        RETURN;
    END

    DECLARE @ToAgent INT = CASE WHEN @CreatedBy = @OwnAgent
                                  OR @CreatedBy IN (SELECT ID FROM dbo.UserMaster WHERE EntityID = @ToEntity)
                                THEN @OwnAgent ELSE @HeadAgent END;

    /* -- 5 · report ------------------------------------------------------ */
    PRINT '--------------------------------------------------------------';
    PRINT ' Borrower      : ' + CAST(@Id AS VARCHAR(20)) + '  ' + @Name;
    PRINT ' Move          : 3002 -> 3005, unit ' + CAST(@ToUnit AS VARCHAR(10)) + ', agent ' + CAST(@ToAgent AS VARCHAR(10));
    PRINT ' Loans on 3002 : ' + CAST(@LoanCount AS VARCHAR(10)) + ' (' + CAST(@OpenLoans AS VARCHAR(10)) + ' open)';
    PRINT ' Last maturity : ' + ISNULL(CONVERT(VARCHAR(10), @LastMaturity, 120), 'none')
                              + '  (' + ISNULL(CAST(@DaysDormant AS VARCHAR(10)), '-') + ' days)';
    PRINT ' PIN / password: cleared -- customer re-sets on *483*490#';
    PRINT '--------------------------------------------------------------';

    IF @DryRun = 1
    BEGIN
        PRINT 'DRY RUN -- nothing changed. Re-run with @DryRun = 0 to apply.';
        SELECT 'would move' AS action, @Id AS BorrowerId, @Name AS Name, @LoanCount AS LoansOnBook,
               @OpenLoans AS OpenLoans, @LastMaturity AS LastMaturity, @DaysDormant AS DaysDormant,
               @ToAgent AS ToAgent, @ToUnit AS ToUnit;
        RETURN;
    END

    /* -- 6 · the move, identical to the nightly service ------------------ */
    DECLARE @Note NVARCHAR(400) = LEFT(
        'Manual move by sp_MicroEazy_MoveCustomerToFintech.'
      + ISNULL(' Reason: ' + @Reason, '')
      + CASE WHEN @OpenLoans > 0
             THEN ' Moved WITH ' + CAST(@OpenLoans AS NVARCHAR(10)) + ' open loan(s) (@AllowOpenLoans = 1).'
             ELSE '' END, 400);

    BEGIN TRANSACTION;

        IF OBJECT_ID('tempdb..#mloans') IS NOT NULL DROP TABLE #mloans;
        SELECT l.id AS LoanId INTO #mloans
        FROM dbo.Loans l WHERE l.EntityId = @FromEntity AND l.BorrowerId = @Id;
        CREATE CLUSTERED INDEX IX_mloans ON #mloans(LoanId);

        UPDATE l SET l.EntityId = @ToEntity
        FROM dbo.Loans l JOIN #mloans t ON t.LoanId = l.id;

        /* every entity-stamped child of those loans */
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.loanSchedule        x JOIN #mloans t ON t.LoanId = x.Loanid WHERE x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.loanChargesSchedule x JOIN #mloans t ON t.LoanId = x.Loanid WHERE x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.CustomerStatement   x JOIN #mloans t ON t.LoanId = x.LoanId WHERE x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.ManagedLoans        x JOIN #mloans t ON t.LoanId = x.LoanId WHERE x.EntityId <> @ToEntity;

        /* and the children stamped against the borrower rather than the loan */
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.Journals              x WHERE x.BorrowerId = @Id AND x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.LoanGraduationHistory x WHERE x.BorrowerId = @Id AND x.EntityId <> @ToEntity;
        UPDATE x SET x.EntityId = @ToEntity FROM dbo.STKPaymentRequests    x WHERE x.BorrowerId = @Id AND x.EntityId <> @ToEntity;

        /* the customer themselves -- new book, head office, no RO, no stale PIN */
        UPDATE b
           SET b.EntityId          = @ToEntity,
               b.EntityUnit        = @ToUnit,
               b.OldAgent          = b.EntityAgent,   -- keep the trail of who held them
               b.EntityAgent       = @ToAgent,
               b.UssdPin           = NULL,            -- customer sets their own on first dial
               b.MobileAppPassword = NULL,
               b.UpdatedBy         = @OwnAgent,
               b.UpdatedDate       = GETDATE()
        FROM dbo.Borrowers b WHERE b.ID = @Id;

        /* ------------------------------------------------------------------
           TELL THEM. Micromart's own sender ID, because the SMS row carries
           the entity and the entity owns the Africa's Talking credentials.
           ------------------------------------------------------------------ */
        IF @SendSms = 1
        INSERT INTO Notifications.dbo.SMS (smsMessage, smsto, EntityId, CreateDate, isSent, ScheduleDate, SmsProviderId)
        SELECT
            'Dear ' + LTRIM(RTRIM(ISNULL(o.firstName, 'Customer')))
          + ', your Micromart account has moved to Micromart Fintech. You can now '
          + 'apply for a loan from home - no branch visit, no agent. '
          + 'App: microeazy.servicesuitecloud.com  USSD: *483*490# '
          + 'Dial the USSD code to set your new PIN. PIN yako ni siri yako.',
            o.PhoneNumber, @ToEntity, GETDATE(), 0, GETDATE(), 5
        FROM #one o
        WHERE NULLIF(LTRIM(RTRIM(o.PhoneNumber)), '') IS NOT NULL;

        IF @SendEmail = 1
        INSERT INTO dbo.Mails (tomail, Subject, Message, CreatedBy, CreatedDate, Status, ScheduleDate, isSent)
        SELECT
            o.EmailAddress,
            /* Mails.Subject is varchar(50) -- keep this at or under 50 chars.
               A 53-char subject aborted the whole nightly transaction (error
               2628) on 9 and 10 Sep 2026. */
            'Your account has moved to Micromart Fintech',
            'Dear ' + LTRIM(RTRIM(ISNULL(o.firstName, 'Customer'))) + ',' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Your Micromart account has moved to Micromart Fintech. You can now apply for a loan '
          + 'from the comfort of your home - no branch visit and no agent needed.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Mobile app:  https://microeazy.servicesuitecloud.com' + CHAR(13) + CHAR(10)
          + 'USSD:        *483*490#' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Dial *483*490# from ' + LTRIM(RTRIM(ISNULL(o.PhoneNumber, 'your registered number')))
          + ' and you will be asked to choose a new PIN. That PIN works on both the USSD '
          + 'service and the mobile app.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Keep your PIN secret. Micromart will never ask you for it.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
          + 'Micromart Fintech',
            @OwnAgent, GETDATE(), 0, GETDATE(), 0
        FROM #one o
        WHERE NULLIF(LTRIM(RTRIM(o.EmailAddress)), '') IS NOT NULL
          AND o.EmailAddress LIKE '%_@_%._%';

        /* the same audit trail the nightly job writes, so both paths land
           in one place and MicroEazyDormancyLog stays the whole story */
        INSERT INTO dbo.MicroEazyDormancyLog
            (BorrowerId, FromEntityId, ToEntityId, FromUnit, FromAgent, ToAgent,
             LastMaturity, DaysDormant, LoansMoved, SmsQueued, MailQueued, Note)
        SELECT o.BorrowerId, @FromEntity, @ToEntity, o.FromUnit, o.FromAgent, @ToAgent,
               @LastMaturity, @DaysDormant, @LoanCount,
               CASE WHEN @SendSms   = 1 AND NULLIF(LTRIM(RTRIM(o.PhoneNumber)),  '') IS NOT NULL THEN 1 ELSE 0 END,
               CASE WHEN @SendEmail = 1 AND NULLIF(LTRIM(RTRIM(o.EmailAddress)), '') IS NOT NULL
                                       AND o.EmailAddress LIKE '%_@_%._%' THEN 1 ELSE 0 END,
               @Note
        FROM #one o;

        /* BorrowerComments.Comment is varchar(250) -- LEFT() so a long
           @Reason can never abort the move the way the subject line did */
        INSERT INTO dbo.BorrowerComments (borroweId, Comment, CreatedBy, DateCreated)
        SELECT @Id,
               LEFT('Moved to MICROMART FINTECH (3005) manually. '
                  + 'Loans: ' + CAST(@LoanCount AS VARCHAR(10)) + ' (' + CAST(@OpenLoans AS VARCHAR(10)) + ' open). '
                  + 'Last maturity ' + ISNULL(CONVERT(VARCHAR(10), @LastMaturity, 120), 'none')
                  + ISNULL('. Reason: ' + @Reason, '') + '.', 250),
               @OwnAgent, GETDATE();

    COMMIT TRANSACTION;

    PRINT 'Moved borrower ' + CAST(@Id AS VARCHAR(20)) + ' (' + @Name + ') to Micromart Fintech (3005).';
    PRINT 'They must dial *483*490# to set a new PIN before signing in.';
END
GO

PRINT '11 complete. Dry-run it first:';
PRINT '   EXEC dbo.sp_MicroEazy_MoveCustomerToFintech @PhoneNumber = ''254719112304'';';
GO
