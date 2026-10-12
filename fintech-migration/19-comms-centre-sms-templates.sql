/*==========================================================================
  19 · THE COMMS CENTRE: REMINDERS AND THE DISBURSEMENT SMS, EDITED FROM
       THE LENDING CONSOLE

  WHY THIS EXISTS
  Every SMS Micromart Fintech (3005) sends on its own is typed inside a
  stored procedure:
    · sp_FintechSmsReminders, run by a SQL Agent job (the reminders land at
      about 08:00) -- five fixed messages: two days and one day before a due
      date, on the day, and one and three days after it.
    · sp_DisbursmentNotifications -- the disbursement message (see 18).
  Changing one word is an ALTER PROCEDURE on the lender's production
  server. That is why the disbursement SMS sent Fintech customers to the
  3002 paybill for eight weeks, and why the arrears ladder Geoffrey wrote
  on 5 Oct 2026 (1, 4, 8, 10 and 13 days overdue) could not go live
  without a developer.

  WHAT THIS DOES
  Moves the WORDING into a table the Lending Console edits (Comms >
  Reminders, Comms > Templates) and leaves the SENDING where it is: the
  same job, the same procedure name and parameters, the same outbox
  (Notifications.dbo.SMS), CreatedBy 101, the entity's own SmsProviderId.

    19.0  preflight                     read-only; keep the output
    19.1  four small tables             templates, settings, a reminder log,
                                        and the procedure backup (if 18 was skipped)
    19.2  seed                          the three steps before the due date as
                                        they read today, Geoffrey's five arrears
                                        steps, and the disbursement copy
    19.3  dbo.sp_MicroEazy_DisbursementSms   new: renders the disbursement copy
    19.4  dbo.sp_FintechSmsReminders    REWRITTEN to read the ladder; the old
                                        text is saved first. Off until @Install = 1.
    19.5  the disbursement hook         a few lines in sp_DisbursmentNotifications,
                                        plus 18's paybill fix if 18 was skipped.
                                        Off until @Install = 1.
    19.6  verify + dry runs             read-only

  WHAT CHANGES FOR A CUSTOMER
  · ONE reminder per loan per day, chosen by the loan rather than by each
    instalment. A loan with an unpaid instalment past its due date takes
    the arrears step for its OLDEST such instalment (days overdue = days
    since that date) and {Amount} is everything overdue on the loan. A loan
    that is up to date takes the step for its next due date, and {Amount}
    is what falls due that day. A day with no step sends nothing.
  · The old day+1 and day+3 messages give way to Geoffrey's day 1, 4, 8, 10
    and 13. The two-day, one-day and due-day messages keep today's wording,
    with the paybill and the care line written as placeholders.
  · "Already texted today" used to count ANY message to the phone, so the
    01:01 penalty notice or a payment receipt silenced that day's reminder.
    It now counts reminders only (dbo.MicroEazySmsReminderLog).
  · First names are capitalised: "Dorine", not "dorine" or "DORINE".

  Three of Geoffrey's five texts -- day 8, day 10 and day 13 -- are longer
  than 160 characters for EVERY customer (166 to 192 with typical values),
  so each is billed as two SMS; day 1 becomes two when the first name is
  long. Seeded as he wrote them; the console shows the cost on every step
  and the wording is his to trim.

  Run in SSMS against Serviceconnect, ONE SECTION AT A TIME, reading the
  messages pane between each. Every section is safe to re-run.
  Undo with 18-19-ROLLBACK-comms-centre.sql.
  ==========================================================================*/


/* -------------------------------------------------------------------------
   19.0 · PREFLIGHT — read-only. Keep the output.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;

-- (a) The job that sends the reminders. 19.4 keeps the procedure's name and
--     parameters, so the job needs no change -- but if a step calls it with
--     parameters other than @EntityId / @DryRun, stop and send this output.
SELECT j.name AS job, j.enabled, s.step_id, s.step_name, s.database_name,
       LEFT(REPLACE(REPLACE(s.command, CHAR(13), ' '), CHAR(10), ' '), 400) AS command
  FROM msdb.dbo.sysjobs j
  JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
 WHERE s.command LIKE '%sp_FintechSmsReminders%';

SELECT j.name AS job, sc.name AS schedule, sc.enabled, sc.freq_type, sc.freq_interval,
       sc.freq_subday_type, sc.freq_subday_interval, sc.active_start_time
  FROM msdb.dbo.sysjobs j
  JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
  JOIN msdb.dbo.sysschedules sc    ON sc.schedule_id = js.schedule_id
 WHERE j.job_id IN (SELECT job_id FROM msdb.dbo.sysjobsteps WHERE command LIKE '%sp_FintechSmsReminders%');

-- (b) The two procedures this script touches, as they stand.
SELECT o.name, o.modify_date, m.uses_ansi_nulls, m.uses_quoted_identifier,
       CASE WHEN m.definition LIKE '%MicroEazySmsTemplate%'          THEN 1 ELSE 0 END AS readsTemplatesAlready,
       CASE WHEN m.definition LIKE '%sp_MicroEazy_DisbursementSms%' THEN 1 ELSE 0 END AS hookedAlready,
       CASE WHEN m.definition LIKE '%Repay via Paybill 4038021%'     THEN 1 ELSE 0 END AS wrongPaybill
  FROM sys.sql_modules m
  JOIN sys.objects o ON o.object_id = m.object_id
 WHERE o.name IN (N'sp_FintechSmsReminders', N'sp_DisbursmentNotifications');

-- (c) 19.5 inserts its lines after this text; it must appear exactly once.
SELECT (DATALENGTH(m.definition) - DATALENGTH(REPLACE(m.definition, N'to apply your next loan.''', N'')))
         / DATALENGTH(N'to apply your next loan.''')            AS hookAnchorLines   -- must be 1
  FROM sys.sql_modules m
 WHERE m.object_id = OBJECT_ID(N'dbo.sp_DisbursmentNotifications');

-- (d) The reminders the old procedure sent in the last week, per day.
SELECT CAST(CreateDate AS DATE) AS sentOn, COUNT(*) AS reminders,
       SUM(CASE WHEN isSent = 1 THEN 1 ELSE 0 END) AS delivered,
       SUM(CASE WHEN isSent = 2 THEN 1 ELSE 0 END) AS failed
  FROM Notifications.dbo.SMS
 WHERE EntityId = 3005 AND CreatedBy = 101
   AND CreateDate >= DATEADD(DAY, -7, CAST(GETDATE() AS DATE))
   AND (   smsMessage LIKE 'Hello %timely repayment keeps your good standing%'
        OR smsMessage LIKE 'Dear %your loan of Ksh.%is due on%'
        OR smsMessage LIKE 'Dear %your loan installment of Ksh.%is due.%'
        OR smsMessage LIKE 'Dear %a courtesy alert: your loan balance%'
        OR smsMessage LIKE 'Dear %remains unpaid & is now overdue%')
 GROUP BY CAST(CreateDate AS DATE)
 ORDER BY sentOn;
GO


/* -------------------------------------------------------------------------
   19.1 · Four small tables, all additive.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.MicroEazyProcBackup') IS NULL
BEGIN
    -- The exact text of every Micromart procedure scripts 18 and 19 alter,
    -- saved before the ALTER. The rollback reads it. (18 creates it too.)
    CREATE TABLE dbo.MicroEazyProcBackup (
        -- The same shape as penalty-service/01 (17 Sep 2026), which created this
        -- table on Micromart live first. Its columns are the ones that exist.
        Id         INT IDENTITY(1,1) PRIMARY KEY,
        ProcName   SYSNAME        NOT NULL,
        Definition NVARCHAR(MAX)  NOT NULL,
        Sha256     VARCHAR(64)    NOT NULL,
        SavedAt    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
        SavedBy    SYSNAME        NOT NULL DEFAULT SUSER_SNAME(),
        Script     VARCHAR(60)    NOT NULL
    );
    PRINT 'Created dbo.MicroEazyProcBackup';
END

IF OBJECT_ID(N'dbo.MicroEazySmsTemplate') IS NULL
BEGIN
    -- One row per message the Lending Console can edit. REMINDER rows carry
    -- the day they go out, relative to the due date: -2 = two days before,
    -- 0 = the due day, 4 = four days overdue. Other events carry NULL, and the
    -- unique index (NULLs compare equal in it) allows one row per event.
    CREATE TABLE dbo.MicroEazySmsTemplate (
        Id         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MicroEazySmsTemplate PRIMARY KEY,
        EntityId   INT               NOT NULL,
        EventKey   VARCHAR(30)       NOT NULL,
        DayOffset  INT               NULL,
        Title      NVARCHAR(80)      NOT NULL,
        -- varchar, like the outbox column it ends up in: nothing can be saved
        -- here that the outbox could not hold.
        Body       VARCHAR(480)      NOT NULL,
        IsActive   BIT               NOT NULL CONSTRAINT DF_MEST_IsActive  DEFAULT 1,
        CreatedAt  DATETIME2(0)      NOT NULL CONSTRAINT DF_MEST_CreatedAt DEFAULT SYSDATETIME(),
        UpdatedAt  DATETIME2(0)      NOT NULL CONSTRAINT DF_MEST_UpdatedAt DEFAULT SYSDATETIME(),
        UpdatedBy  NVARCHAR(120)     NULL,       -- who saved it on the console
        CONSTRAINT CK_MEST_Event  CHECK (EventKey IN ('REMINDER', 'DISBURSED')),
        CONSTRAINT CK_MEST_Offset CHECK ((EventKey = 'REMINDER' AND DayOffset BETWEEN -14 AND 90)
                                      OR (EventKey <> 'REMINDER' AND DayOffset IS NULL))
    );
    CREATE UNIQUE INDEX UX_MEST_Step ON dbo.MicroEazySmsTemplate (EntityId, EventKey, DayOffset);
    PRINT 'Created dbo.MicroEazySmsTemplate';
END

IF OBJECT_ID(N'dbo.MicroEazySmsSetting') IS NULL
BEGIN
    -- One row per book: the numbers the templates print, and what the
    -- console's spend figures are priced at. Edited from Comms > Settings.
    CREATE TABLE dbo.MicroEazySmsSetting (
        EntityId       INT            NOT NULL CONSTRAINT PK_MicroEazySmsSetting PRIMARY KEY,
        Paybill        VARCHAR(20)    NULL,   -- {Paybill}; NULL = the book's only row in Transactions.dbo.PAYBILLS
        CustomerCare   VARCHAR(20)    NULL,   -- {CustomerCare}
        UnitPrice      DECIMAL(10,4)  NULL,   -- KES per SMS segment; NULL = BsEntity.SmsRate, else 0.60
        MonthlyBudget  DECIMAL(18,2)  NULL,   -- KES; the console sets the month's projection against it
        UpdatedAt      DATETIME2(0)   NOT NULL CONSTRAINT DF_MESS_UpdatedAt DEFAULT SYSDATETIME(),
        UpdatedBy      NVARCHAR(120)  NULL
    );
    PRINT 'Created dbo.MicroEazySmsSetting';
END

IF OBJECT_ID(N'dbo.MicroEazySmsReminderLog') IS NULL
BEGIN
    -- One row per reminder queued. It does two jobs: the "already reminded
    -- today" check -- one per phone per day per book, and the unique index
    -- makes a second run on the same day fail instead of double-sending --
    -- and the console's per-step history, joined to the outbox row by SmsId.
    CREATE TABLE dbo.MicroEazySmsReminderLog (
        Id          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MicroEazySmsReminderLog PRIMARY KEY,
        RunDate     DATE              NOT NULL,
        EntityId    INT               NOT NULL,
        TemplateId  INT               NULL,   -- NULL only for the install-day backfill in 19.4
        DayOffset   INT               NOT NULL,
        LoanId      INT               NULL,
        BorrowerId  INT               NULL,
        Phone       VARCHAR(20)       NOT NULL,
        Amount      DECIMAL(18,2)     NULL,
        Chars       INT               NULL,
        SmsId       INT               NULL,   -- Notifications.dbo.SMS.id
        QueuedAt    DATETIME2(0)      NOT NULL CONSTRAINT DF_MESRL_QueuedAt DEFAULT SYSDATETIME()
    );
    CREATE UNIQUE INDEX UX_MESRL_Day    ON dbo.MicroEazySmsReminderLog (RunDate, EntityId, Phone);
    CREATE        INDEX IX_MESRL_Entity ON dbo.MicroEazySmsReminderLog (EntityId, RunDate)
                                       INCLUDE (DayOffset, TemplateId, SmsId, Chars, Amount);
    PRINT 'Created dbo.MicroEazySmsReminderLog';
END
GO


/* -------------------------------------------------------------------------
   19.2 · SEED — Micromart Fintech (3005). Adds missing rows only; a row the
   console has already edited is never overwritten.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;

DECLARE @EntityId INT = 3005;

IF NOT EXISTS (SELECT 1 FROM dbo.MicroEazySmsSetting WHERE EntityId = @EntityId)
    INSERT INTO dbo.MicroEazySmsSetting (EntityId, Paybill, CustomerCare, UpdatedBy)
    VALUES (@EntityId, '4329635', '0756445237', 'fintech-migration/19');

DECLARE @seed TABLE (EventKey VARCHAR(30), DayOffset INT NULL, Title NVARCHAR(80), Body VARCHAR(480));
INSERT INTO @seed (EventKey, DayOffset, Title, Body) VALUES
-- Today's wording, unchanged except that the paybill and the care line are placeholders.
('REMINDER', -2, N'Two days before the due date',
 'Hello {FirstName}, timely repayment keeps your good standing and speeds future approvals. Pay Ksh.{Amount} via Paybill {Paybill}. Call {CustomerCare}.'),
('REMINDER', -1, N'The day before the due date',
 'Dear {FirstName}, your loan of Ksh.{Amount} is due on {DueDate}. Pay early via Paybill {Paybill}. On-time payment unlocks better rates next loan.'),
('REMINDER',  0, N'On the due date',
 'Dear {FirstName}, your loan installment of Ksh.{Amount} is due. Please pay promptly through Paybill {Paybill}. Call {CustomerCare} for assistance.'),
-- Geoffrey's arrears ladder (WhatsApp, 5 Oct 2026, 17:25). His second message
-- is headed "4 days" twice; its text says 8 days overdue, so it is seeded at 8.
('REMINDER',  1, N'1 day in arrears',
 'Dear {FirstName}, your loan payment of Ksh.{Amount} is now overdue. Please make your payment today via Paybill {Paybill}. Pay now to keep your account up to date.'),
('REMINDER',  4, N'4 days in arrears',
 'URGENT; Your account is {DaysOverdue} days in arrears. Delays negatively impact your credit score and loan limit. Please pay Ksh.{Amount} immediately via {Paybill}.'),
('REMINDER',  8, N'8 days in arrears',
 'Attention {FirstName}: Your loan of KSh {Amount} is now {DaysOverdue} days overdue. Continued non-payment will attract late penalties and further credit action. Pay now via Paybill {Paybill}.'),
('REMINDER', 10, N'Final notice (10 days)',
 'Final Notice: Your loan of KSh {Amount} is {DaysOverdue} days overdue. Please be advised that a late payment penalty will be charged to your account if unpaid after 14 days. Pay today via Paybill {Paybill}.'),
('REMINDER', 13, N'Final reminder (day 13)',
 'Final Reminder: Penalty charges will be applied to your overdue balance of KSh {Amount} after 24 hours. Clear your loan today via Paybill {Paybill} to stop fee imposition.'),
-- The disbursement message as script 18 leaves it.
('DISBURSED', NULL, N'Loan disbursed',
 'Dear {FirstName}, your loan of Ksh.{DisbursedAmount} has been disbursed to your account. Repay via Paybill {Paybill}. Dial *483*490# to apply your next loan.');

INSERT INTO dbo.MicroEazySmsTemplate (EntityId, EventKey, DayOffset, Title, Body, UpdatedBy)
SELECT @EntityId, s.EventKey, s.DayOffset, s.Title, s.Body, N'fintech-migration/19'
  FROM @seed s
 WHERE NOT EXISTS (SELECT 1 FROM dbo.MicroEazySmsTemplate t
                    WHERE t.EntityId = @EntityId
                      AND t.EventKey = s.EventKey
                      AND ISNULL(t.DayOffset, -999) = ISNULL(s.DayOffset, -999));
PRINT CONCAT(@@ROWCOUNT, ' template row(s) added for entity ', @EntityId, '. Rows already there were left as they are.');

SELECT EventKey, DayOffset, Title, IsActive, LEN(Body) AS templateChars, Body
  FROM dbo.MicroEazySmsTemplate
 WHERE EntityId = @EntityId
 ORDER BY EventKey DESC, DayOffset;
GO


/* -------------------------------------------------------------------------
   19.3 · dbo.sp_MicroEazy_DisbursementSms — new. Nothing calls it until
   19.5 is installed. It runs INSIDE the loan-approval transaction
   (sp_FinalApproval -> sp_DisbursmentNotifications), so it only reads, it
   reads loanSchedule only when the copy needs it, and every failure ends
   in "no message" -- the caller then sends its own built-in text.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_MicroEazy_DisbursementSms
    @Loanid  INT,
    @Message VARCHAR(MAX) OUTPUT
AS
BEGIN
    /* Micro Eazy (fintech-migration/19). Renders the Lending Console's
       disbursement copy (dbo.MicroEazySmsTemplate, EventKey 'DISBURSED') for
       one loan. @Message stays NULL when there is no active copy for the
       loan's book, or when anything the copy names cannot be filled. */
    SET NOCOUNT ON;
    SET @Message = NULL;

    BEGIN TRY
        DECLARE @EntityId INT, @BorrowerId INT,
                @Disburse DECIMAL(18,2), @LoanAmount DECIMAL(18,2), @Balance DECIMAL(18,2),
                @Body VARCHAR(480), @First VARCHAR(200), @Other VARCHAR(200), @Phone VARCHAR(30),
                @Given VARCHAR(200), @Installment DECIMAL(18,2), @FirstDue DATE,
                @Paybill VARCHAR(20), @Care VARCHAR(20), @Out VARCHAR(MAX);

        SELECT @EntityId = EntityId, @BorrowerId = BorrowerId, @Disburse = AmountToDisburse,
               @LoanAmount = LoanAmount, @Balance = LoanBalance
          FROM dbo.Loans
         WHERE id = @Loanid;
        IF @EntityId IS NULL RETURN;

        SELECT @Body = Body
          FROM dbo.MicroEazySmsTemplate
         WHERE EntityId = @EntityId AND EventKey = 'DISBURSED' AND IsActive = 1;
        IF @Body IS NULL RETURN;

        SELECT @First = LTRIM(RTRIM(firstName)), @Other = LTRIM(RTRIM(otherName)), @Phone = LTRIM(RTRIM(PhoneNumber))
          FROM dbo.Borrowers
         WHERE ID = @BorrowerId;

        -- loanSchedule is an unindexed heap; read it only when the copy asks.
        IF CHARINDEX('{Installment}', @Body) > 0 OR CHARINDEX('{FirstDueDate}', @Body) > 0
            SELECT TOP 1 @Installment = InstallmentAmount, @FirstDue = CAST(ExpectedDueDate AS DATE)
              FROM dbo.loanSchedule WITH (NOLOCK)
             WHERE Loanid = @Loanid
             ORDER BY ExpectedDueDate, id;

        SELECT @Paybill = NULLIF(LTRIM(RTRIM(Paybill)), ''), @Care = NULLIF(LTRIM(RTRIM(CustomerCare)), '')
          FROM dbo.MicroEazySmsSetting
         WHERE EntityId = @EntityId;
        IF @Paybill IS NULL
            SELECT @Paybill = CASE WHEN COUNT(*) = 1 THEN CONVERT(VARCHAR(20), MAX(PayBillNumber)) END
              FROM Transactions.dbo.PAYBILLS
             WHERE EntityId = @EntityId;

        -- First word of FirstName, capped at 15, capitalised.
        SET @Given = LEFT(LEFT(@First, CHARINDEX(' ', @First + ' ') - 1), 15);
        SET @Given = UPPER(LEFT(@Given, 1)) + LOWER(SUBSTRING(@Given, 2, 14));

        SET @Out = @Body;
        SET @Out = REPLACE(@Out, '{FirstName}',       ISNULL(NULLIF(@Given, ''), 'Customer'));
        SET @Out = REPLACE(@Out, '{FullName}',        ISNULL(NULLIF(LTRIM(RTRIM(CONCAT(@First, ' ', @Other))), ''), 'Customer'));
        SET @Out = REPLACE(@Out, '{Phone}',           ISNULL(@Phone, ''));
        SET @Out = REPLACE(@Out, '{DisbursedAmount}', ISNULL(FORMAT(@Disburse, 'N0', 'en-US'), ''));
        SET @Out = REPLACE(@Out, '{LoanAmount}',      ISNULL(FORMAT(@LoanAmount, 'N0', 'en-US'), ''));
        SET @Out = REPLACE(@Out, '{Balance}',         ISNULL(FORMAT(@Balance, 'N0', 'en-US'), ''));
        SET @Out = REPLACE(@Out, '{Installment}',     ISNULL(FORMAT(@Installment, 'N0', 'en-US'), ''));
        SET @Out = REPLACE(@Out, '{FirstDueDate}',    ISNULL(CONVERT(VARCHAR(11), @FirstDue, 106), ''));
        SET @Out = REPLACE(@Out, '{Paybill}',         ISNULL(@Paybill, ''));
        SET @Out = REPLACE(@Out, '{CustomerCare}',    ISNULL(@Care, ''));
        SET @Out = REPLACE(@Out, '{LoanId}',          CONVERT(VARCHAR(20), @Loanid));

        -- An unfilled placeholder, or a number this book has not set, never
        -- reaches a customer as a gap: the caller's own text goes instead.
        IF CHARINDEX('{', @Out) > 0 RETURN;
        IF (CHARINDEX('{Paybill}', @Body) > 0 AND @Paybill IS NULL)
        OR (CHARINDEX('{CustomerCare}', @Body) > 0 AND @Care IS NULL)
        OR (CHARINDEX('{DisbursedAmount}', @Body) > 0 AND @Disburse IS NULL)
        OR (CHARINDEX('{Installment}', @Body) > 0 AND @Installment IS NULL)
        OR (CHARINDEX('{FirstDueDate}', @Body) > 0 AND @FirstDue IS NULL)
            RETURN;

        SET @Message = @Out;
    END TRY
    BEGIN CATCH
        SET @Message = NULL;
    END CATCH
END
GO


/* -------------------------------------------------------------------------
   19.4 · dbo.sp_FintechSmsReminders — REWRITTEN to read the ladder.

   Same name, same parameters (@EntityId, @DryRun) and one new optional one
   (@AsOf, preview only), so the job that runs it needs no change. Its
   current text is saved to dbo.MicroEazyProcBackup first.

   With @Install = 0 (the default) the new procedure is COMPILED but not
   created (SET NOEXEC), so a typo shows here without touching anything.
   Run 19.1 and 19.2 first.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;

DECLARE @Install BIT = 0;   -- <<< set to 1 once 19.0 to 19.3 have run clean

IF OBJECT_ID(N'dbo.MicroEazySmsTemplate') IS NULL OR OBJECT_ID(N'dbo.MicroEazySmsReminderLog') IS NULL
   OR OBJECT_ID(N'dbo.MicroEazyProcBackup') IS NULL OR OBJECT_ID(N'dbo.MicroEazySmsSetting') IS NULL
BEGIN
    RAISERROR(N'Run 19.1 and 19.2 first. Nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF NOT EXISTS (SELECT 1 FROM dbo.MicroEazySmsTemplate WHERE EntityId = 3005 AND EventKey = 'REMINDER' AND IsActive = 1)
BEGIN
    RAISERROR(N'There are no active reminder steps for 3005 -- the new procedure would send nothing. Run 19.2 first. Nothing changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF @Install = 0
BEGIN
    PRINT N'Checks passed. The procedure below is compiled but NOT created. Set @Install = 1 and run 19.4 again.';
    SET NOEXEC ON;
END
ELSE
BEGIN
    BEGIN TRY
        IF CHARINDEX(N'MicroEazySmsTemplate', ISNULL(OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_FintechSmsReminders')), N'')) = 0
           AND OBJECT_ID(N'dbo.sp_FintechSmsReminders') IS NOT NULL
            INSERT INTO dbo.MicroEazyProcBackup (Script, ProcName, Sha256, Definition)
            SELECT '19', N'dbo.sp_FintechSmsReminders',
                   CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_FintechSmsReminders'))), 2),
                   OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_FintechSmsReminders'));
        PRINT N'Old text saved (or already replaced). Creating the new procedure.';
    END TRY
    BEGIN CATCH
        PRINT N'Could not save the old text: ' + ERROR_MESSAGE() + N' -- nothing changed.';
        SET NOEXEC ON;
    END CATCH
END
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_FintechSmsReminders
    @EntityId INT  = 3005,
    @DryRun   BIT  = 1,      -- 1 = preview only, nothing written. 0 = queue (what the job runs).
    @AsOf     DATE = NULL    -- preview another day (tomorrow, say). Ignored when queuing.
AS
BEGIN
    /* Micro Eazy, 6 Oct 2026 (fintech-migration/19). The WORDING lives in
       dbo.MicroEazySmsTemplate and is edited from the Lending Console
       (Comms > Reminders). This procedure chooses who is reminded and fills
       the placeholders.

       ONE reminder per loan per day:
         · a loan with an unpaid instalment past its due date takes the step
           for its OLDEST such instalment -- days overdue = days since that
           date -- and {Amount} is everything overdue on the loan;
         · a loan that is up to date takes the step for its next due date, and
           {Amount} is what falls due that day.
       A day with no active step sends nothing. One reminder per phone per day
       per book, enforced by dbo.MicroEazySmsReminderLog.

       DRY RUN returns ONE result set (the console's relay forwards only the
       first), one row per loan with a step, Outcome:
         queue       would be sent now
         sent        already reminded today
         unresolved  the copy names something this procedure cannot fill */
    SET NOCOUNT ON;

    DECLARE @Today DATE = CASE WHEN @DryRun = 1 AND @AsOf IS NOT NULL THEN @AsOf ELSE CAST(GETDATE() AS DATE) END;
    DECLARE @Paybill VARCHAR(20), @Care VARCHAR(20), @Provider INT;

    SELECT @Paybill = NULLIF(LTRIM(RTRIM(Paybill)), ''), @Care = NULLIF(LTRIM(RTRIM(CustomerCare)), '')
      FROM dbo.MicroEazySmsSetting
     WHERE EntityId = @EntityId;
    IF @Paybill IS NULL
        SELECT @Paybill = CASE WHEN COUNT(*) = 1 THEN CONVERT(VARCHAR(20), MAX(PayBillNumber)) END
          FROM Transactions.dbo.PAYBILLS
         WHERE EntityId = @EntityId;
    -- The same provider rule as Notifications.dbo.sp_InsertsmsAndEmails.
    SET @Provider = ISNULL((SELECT SmsProviderId FROM dbo.BsEntity WHERE ID = @EntityId), 1);

    CREATE TABLE #steps (DayOffset INT NOT NULL PRIMARY KEY, TemplateId INT NOT NULL, Body VARCHAR(480) NOT NULL);
    INSERT INTO #steps (DayOffset, TemplateId, Body)
    SELECT DayOffset, Id, Body
      FROM dbo.MicroEazySmsTemplate
     WHERE EntityId = @EntityId AND EventKey = 'REMINDER' AND IsActive = 1 AND DayOffset IS NOT NULL;

    -- Every unpaid instalment of every open loan on the book.
    CREATE TABLE #due (LoanId INT NOT NULL, Due DATE NOT NULL, ToPay DECIMAL(18,2) NOT NULL, Installment DECIMAL(18,2) NULL);
    IF EXISTS (SELECT 1 FROM #steps)
        INSERT INTO #due (LoanId, Due, ToPay, Installment)
        SELECT LS.Loanid, CAST(LS.ExpectedDueDate AS DATE), LS.amounttopay, LS.InstallmentAmount
          FROM dbo.loanSchedule LS
          JOIN dbo.Loans L ON L.id = LS.Loanid
         WHERE L.EntityId = @EntityId
           AND L.isApproved = 1
           AND ISNULL(L.LoanCleared, 0) = 0
           AND LS.amounttopay > 0;

    -- One row per loan: where it stands today.
    CREATE TABLE #loan (LoanId INT NOT NULL PRIMARY KEY, DayOffset INT NOT NULL, Anchor DATE NOT NULL, Amount DECIMAL(18,2) NOT NULL,
                        Arrears DECIMAL(18,2) NOT NULL, Installment DECIMAL(18,2) NULL);
    ;WITH p AS (
        SELECT LoanId,
               MIN(CASE WHEN Due <  @Today THEN Due END)            AS OldestOverdue,
               SUM(CASE WHEN Due <  @Today THEN ToPay ELSE 0 END)   AS Overdue,
               MIN(CASE WHEN Due >= @Today THEN Due END)            AS NextDue
          FROM #due
         GROUP BY LoanId
    )
    INSERT INTO #loan (LoanId, DayOffset, Anchor, Amount, Arrears, Installment)
    SELECT p.LoanId,
           CASE WHEN p.OldestOverdue IS NOT NULL THEN DATEDIFF(DAY, p.OldestOverdue, @Today)
                ELSE -DATEDIFF(DAY, @Today, p.NextDue) END,
           ISNULL(p.OldestOverdue, p.NextDue),
           CASE WHEN p.OldestOverdue IS NOT NULL THEN p.Overdue
                ELSE (SELECT SUM(d.ToPay) FROM #due d WHERE d.LoanId = p.LoanId AND d.Due = p.NextDue) END,
           p.Overdue,
           (SELECT MAX(d.Installment) FROM #due d WHERE d.LoanId = p.LoanId AND d.Due = ISNULL(p.OldestOverdue, p.NextDue))
      FROM p
     WHERE ISNULL(p.OldestOverdue, p.NextDue) IS NOT NULL;

    -- The loans that have a step today, rendered.
    CREATE TABLE #msg (LoanId INT NOT NULL, BorrowerId INT NULL, Phone VARCHAR(20) NOT NULL, DayOffset INT NOT NULL,
                       TemplateId INT NOT NULL, Amount DECIMAL(18,2) NOT NULL, Anchor DATE NOT NULL,
                       Body VARCHAR(480) NOT NULL, Message VARCHAR(MAX) NOT NULL, Outcome VARCHAR(12) NOT NULL);
    ;WITH c AS (
        SELECT lo.LoanId, L.BorrowerId, lo.DayOffset, lo.Anchor, lo.Amount, lo.Arrears, lo.Installment,
               s.TemplateId, s.Body, L.LoanBalance, L.LoanAmount,
               LEFT(CASE WHEN LEFT(LTRIM(B.PhoneNumber), 1) = '0'
                         THEN '254' + SUBSTRING(LTRIM(RTRIM(B.PhoneNumber)), 2, 20)
                         ELSE REPLACE(LTRIM(RTRIM(B.PhoneNumber)), '+', '') END, 20)       AS Phone,
               LTRIM(RTRIM(B.firstName))                                                     AS First,
               LTRIM(RTRIM(CONCAT(LTRIM(RTRIM(B.firstName)), ' ', LTRIM(RTRIM(B.otherName))))) AS FullName
          FROM #loan lo
          JOIN #steps s       ON s.DayOffset = lo.DayOffset
          JOIN dbo.Loans L     ON L.id = lo.LoanId
          JOIN dbo.Borrowers B ON B.ID = L.BorrowerId
         WHERE NULLIF(LTRIM(RTRIM(B.PhoneNumber)), '') IS NOT NULL
    ),
    g AS (
        -- First word of FirstName, capped at 15, capitalised.
        SELECT c.*, LEFT(LEFT(c.First, CHARINDEX(' ', c.First + ' ') - 1), 15) AS Word
          FROM c
    ),
    r AS (
        SELECT g.*,
               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                   g.Body,
                   '{FirstName}',   ISNULL(NULLIF(UPPER(LEFT(g.Word, 1)) + LOWER(SUBSTRING(g.Word, 2, 14)), ''), 'Customer')),
                   '{FullName}',    ISNULL(NULLIF(g.FullName, ''), 'Customer')),
                   '{Phone}',       g.Phone),
                   '{Amount}',      FORMAT(g.Amount, 'N0', 'en-US')),
                   '{Arrears}',     FORMAT(g.Arrears, 'N0', 'en-US')),
                   '{Installment}', ISNULL(FORMAT(g.Installment, 'N0', 'en-US'), '')),
                   '{DueDate}',     CONVERT(VARCHAR(11), g.Anchor, 106)),
                   '{DaysOverdue}', CONVERT(VARCHAR(10), CASE WHEN g.DayOffset > 0 THEN g.DayOffset ELSE 0 END)),
                   '{Balance}',     ISNULL(FORMAT(g.LoanBalance, 'N0', 'en-US'), '')),
                   '{LoanAmount}',  ISNULL(FORMAT(g.LoanAmount, 'N0', 'en-US'), '')),
                   '{Paybill}',     ISNULL(@Paybill, '')),
                   '{CustomerCare}', ISNULL(@Care, '')),
                   '{LoanId}',      CONVERT(VARCHAR(20), g.LoanId)) AS Message,
               ROW_NUMBER() OVER (PARTITION BY g.Phone ORDER BY g.DayOffset DESC, g.Amount DESC, g.LoanId) AS PhoneRank
          FROM g
    )
    INSERT INTO #msg (LoanId, BorrowerId, Phone, DayOffset, TemplateId, Amount, Anchor, Body, Message, Outcome)
    SELECT r.LoanId, r.BorrowerId, r.Phone, r.DayOffset, r.TemplateId, r.Amount, r.Anchor, r.Body, r.Message,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.MicroEazySmsReminderLog lg
                              WHERE lg.RunDate = @Today AND lg.EntityId = @EntityId AND lg.Phone = r.Phone) THEN 'sent'
                WHEN CHARINDEX('{', r.Message) > 0
                  OR (CHARINDEX('{Paybill}', r.Body) > 0 AND @Paybill IS NULL)
                  OR (CHARINDEX('{CustomerCare}', r.Body) > 0 AND @Care IS NULL) THEN 'unresolved'
                ELSE 'queue' END
      FROM r
     WHERE r.PhoneRank = 1;

    IF @DryRun = 1
    BEGIN
        SELECT m.DayOffset, m.TemplateId, m.LoanId, m.BorrowerId, m.Phone, m.Amount,
               m.Anchor AS DueDate, m.Outcome, LEN(m.Message) AS Chars,
               CASE WHEN LEN(m.Message) <= 160 THEN 1 ELSE CEILING(LEN(m.Message) / 153.0) END AS Segments,
               m.Message
          FROM #msg m
         ORDER BY m.DayOffset, m.LoanId;
        RETURN;
    END

    DECLARE @queued TABLE (SmsId INT NOT NULL, Phone VARCHAR(20) NOT NULL);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- The log first: its unique index is what stops a second run today.
        INSERT INTO dbo.MicroEazySmsReminderLog (RunDate, EntityId, TemplateId, DayOffset, LoanId, BorrowerId, Phone, Amount, Chars)
        SELECT @Today, @EntityId, m.TemplateId, m.DayOffset, m.LoanId, m.BorrowerId, m.Phone, m.Amount, LEN(m.Message)
          FROM #msg m
         WHERE m.Outcome = 'queue';

        -- The same row shape the previous version wrote.
        INSERT INTO Notifications.dbo.SMS (smsMessage, smsto, EntityId, CreateDate, ScheduleDate, CreatedBy, isSent, SmsProviderId)
        OUTPUT INSERTED.id, INSERTED.smsto INTO @queued (SmsId, Phone)
        SELECT m.Message, m.Phone, @EntityId, GETDATE(), GETDATE(), 101, 0, @Provider
          FROM #msg m
         WHERE m.Outcome = 'queue';

        UPDATE lg
           SET SmsId = q.SmsId
          FROM dbo.MicroEazySmsReminderLog lg
          JOIN @queued q ON q.Phone = lg.Phone
         WHERE lg.RunDate = @Today AND lg.EntityId = @EntityId AND lg.SmsId IS NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT COUNT(*) AS MessagesQueued,
           (SELECT COUNT(*) FROM #msg WHERE Outcome = 'sent')       AS AlreadyRemindedToday,
           (SELECT COUNT(*) FROM #msg WHERE Outcome = 'unresolved') AS SkippedUnresolved
      FROM @queued;
END
GO
SET NOEXEC OFF;
GO

-- Install day only: the old procedure may already have sent today's
-- reminders. Record those phones so a second run today skips them.
USE Serviceconnect;
GO
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.MicroEazySmsReminderLog') IS NOT NULL
   AND CHARINDEX(N'MicroEazySmsTemplate', ISNULL(OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_FintechSmsReminders')), N'')) > 0
BEGIN
    DECLARE @d DATE = CAST(GETDATE() AS DATE);
    ;WITH old AS (
        SELECT id, smsto, LEN(smsMessage) AS Chars,
               CASE WHEN smsMessage LIKE 'Hello %timely repayment keeps your good standing%' THEN -2
                    WHEN smsMessage LIKE 'Dear %your loan of Ksh.%is due on%'                 THEN -1
                    WHEN smsMessage LIKE 'Dear %your loan installment of Ksh.%is due.%'       THEN 0
                    WHEN smsMessage LIKE 'Dear %a courtesy alert: your loan balance%'         THEN 1
                    ELSE 3 END AS DayOffset,
               ROW_NUMBER() OVER (PARTITION BY smsto ORDER BY id) AS rn
          FROM Notifications.dbo.SMS
         WHERE EntityId = 3005 AND CreatedBy = 101
           AND CreateDate >= @d AND CreateDate < DATEADD(DAY, 1, @d)
           AND NULLIF(LTRIM(RTRIM(smsto)), '') IS NOT NULL
           AND (   smsMessage LIKE 'Hello %timely repayment keeps your good standing%'
                OR smsMessage LIKE 'Dear %your loan of Ksh.%is due on%'
                OR smsMessage LIKE 'Dear %your loan installment of Ksh.%is due.%'
                OR smsMessage LIKE 'Dear %a courtesy alert: your loan balance%'
                OR smsMessage LIKE 'Dear %remains unpaid & is now overdue%')
    )
    INSERT INTO dbo.MicroEazySmsReminderLog (RunDate, EntityId, TemplateId, DayOffset, Phone, Chars, SmsId)
    SELECT @d, 3005, NULL, o.DayOffset, LEFT(o.smsto, 20), o.Chars, o.id
      FROM old o
     WHERE o.rn = 1
       AND NOT EXISTS (SELECT 1 FROM dbo.MicroEazySmsReminderLog lg
                        WHERE lg.RunDate = @d AND lg.EntityId = 3005 AND lg.Phone = LEFT(o.smsto, 20));
    PRINT CONCAT(@@ROWCOUNT, ' phone(s) the old procedure already reminded today were recorded, so today is not repeated.');
END
GO


/* -------------------------------------------------------------------------
   19.5 · THE DISBURSEMENT HOOK — the change to Micromart's own procedure.

   Inside sp_DisbursmentNotifications' Fintech block, straight after the
   line that builds the built-in text, it adds:

       IF OBJECT_ID(N'dbo.sp_MicroEazy_DisbursementSms', N'P') IS NOT NULL
       BEGIN
           DECLARE @MicroEazySms VARCHAR(MAX) = NULL;
           EXEC dbo.sp_MicroEazy_DisbursementSms @Loanid = @Loanid, @Message = @MicroEazySms OUTPUT;
           IF NULLIF(LTRIM(RTRIM(@MicroEazySms)), '') IS NOT NULL SET @sms = @MicroEazySms;
       END

  so the console's copy goes out when it is active and renders completely,
  and the built-in text goes out otherwise. Only the 3005 block changes; it
  also corrects 18's paybill if 18 was skipped. Everything else stays byte
  for byte: the script edits the CURRENT definition and saves it first.

  Read on 6 Oct 2026: sp_FinalApproval wraps this in its own transaction
  and TRY/CATCH, without XACT_ABORT, and sp_MicroEazy_DisbursementSms
  catches its own errors -- a failure there cannot stop an approval.

  Run once with @Install = 0 (the default) to see the result, then @Install = 1.
  ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 60000;

DECLARE @Install BIT = 0;   -- <<< set to 1 once the printout reads right

DECLARE @obj    INT           = OBJECT_ID(N'dbo.sp_DisbursmentNotifications');
DECLARE @def    NVARCHAR(MAX) = OBJECT_DEFINITION(@obj);
DECLARE @anchor NVARCHAR(100) = N'to apply your next loan.''';
DECLARE @wrong  NVARCHAR(100) = N'Repay via Paybill 4038021';
DECLARE @right  NVARCHAR(100) = N'Repay via Paybill 4329635';
DECLARE @crlf   NCHAR(2)      = NCHAR(13) + NCHAR(10);
DECLARE @n INT, @at INT, @len INT, @hook NVARCHAR(MAX), @new NVARCHAR(MAX);

IF @def IS NULL
BEGIN
    RAISERROR(N'dbo.sp_DisbursmentNotifications was not found. Nothing changed.', 16, 1);
    RETURN;
END
IF CHARINDEX(N'sp_MicroEazy_DisbursementSms', @def) > 0
BEGIN
    PRINT N'The hook is already in sp_DisbursmentNotifications. Nothing to do.';
    RETURN;
END
IF OBJECT_ID(N'dbo.sp_MicroEazy_DisbursementSms') IS NULL OR OBJECT_ID(N'dbo.MicroEazyProcBackup') IS NULL
BEGIN
    RAISERROR(N'Run 19.1 and 19.3 first. Nothing changed.', 16, 1);
    RETURN;
END

SET @n = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @anchor, N''))) / DATALENGTH(@anchor);
IF @n <> 1
BEGIN
    RAISERROR(N'The text "%s" appears %d times in the procedure, not once: it has changed since 6 Oct 2026. Nothing changed. Send its current text.', 16, 1, @anchor, @n);
    RETURN;
END
IF CHARINDEX(N'IF (@EntityId = 3005)', @def) = 0 OR CHARINDEX(@anchor, @def) < CHARINDEX(N'IF (@EntityId = 3005)', @def)
BEGIN
    RAISERROR(N'The anchor is not inside the IF (@EntityId = 3005) block. Nothing changed. Send the procedure''s current text.', 16, 1);
    RETURN;
END
SET @n = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @wrong, N''))) / DATALENGTH(@wrong);
IF @n > 1
BEGIN
    RAISERROR(N'"%s" appears %d times, not at most once. Nothing changed. Send the procedure''s current text.', 16, 1, @wrong, @n);
    RETURN;
END
IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = @obj AND (uses_ansi_nulls = 0 OR uses_quoted_identifier = 0))
BEGIN
    RAISERROR(N'The procedure was created with ANSI_NULLS or QUOTED_IDENTIFIER off, and this session would change that. Nothing changed.', 16, 1);
    RETURN;
END

SET @at  = PATINDEX(N'%[^' + NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) + N']%', @def);
SET @len = CASE WHEN SUBSTRING(@def, @at, 15) = N'CREATE OR ALTER' THEN 15
                WHEN SUBSTRING(@def, @at, 6)  = N'CREATE'          THEN 6
                WHEN SUBSTRING(@def, @at, 5)  = N'ALTER'           THEN 5
                ELSE 0 END;
IF @len = 0
BEGIN
    RAISERROR(N'The procedure''s text does not open with CREATE or ALTER. Nothing changed.', 16, 1);
    RETURN;
END

SET @hook = @anchor + @crlf + @crlf
    + N'        -- Micro Eazy (fintech-migration/19): the Lending Console''s copy (Comms > Templates)' + @crlf
    + N'        -- goes instead when it is active and renders completely; otherwise the text above.' + @crlf
    + N'        IF OBJECT_ID(N''dbo.sp_MicroEazy_DisbursementSms'', N''P'') IS NOT NULL' + @crlf
    + N'        BEGIN' + @crlf
    + N'            DECLARE @MicroEazySms VARCHAR(MAX) = NULL;' + @crlf
    + N'            EXEC dbo.sp_MicroEazy_DisbursementSms @Loanid = @Loanid, @Message = @MicroEazySms OUTPUT;' + @crlf
    + N'            IF NULLIF(LTRIM(RTRIM(@MicroEazySms)), '''') IS NOT NULL' + @crlf
    + N'                SET @sms = @MicroEazySms;' + @crlf
    + N'        END';

-- Both edits sit after the CREATE keyword, so @at stays where it was.
SET @new = STUFF(REPLACE(REPLACE(@def, @wrong, @right), @anchor, @hook), @at, @len, N'ALTER');

IF @Install = 0
BEGIN
    PRINT N'All checks passed. NOTHING CHANGED. After the hook the procedure would read:';
    PRINT N'------------------------------------------------------------------';
    PRINT @new;
    PRINT N'------------------------------------------------------------------';
    PRINT N'Set @Install = 1 and run 19.5 again to apply it.';
    RETURN;
END

BEGIN TRANSACTION;
    INSERT INTO dbo.MicroEazyProcBackup (Script, ProcName, Sha256, Definition)
    VALUES ('19', N'dbo.sp_DisbursmentNotifications', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', @def), 2), @def);
    EXEC sys.sp_executesql @new;
COMMIT TRANSACTION;

IF CHARINDEX(N'sp_MicroEazy_DisbursementSms', OBJECT_DEFINITION(@obj)) > 0 AND CHARINDEX(@wrong, OBJECT_DEFINITION(@obj)) = 0
    PRINT N'Hook installed. The next Fintech disbursement uses the console''s copy -- check it with 19.6.';
ELSE
    RAISERROR(N'The ALTER ran but the definition does not read right. Look before going further.', 16, 1);
GO


/* -------------------------------------------------------------------------
   19.6 · VERIFY — read-only. Nothing below sends anything.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;

-- (a) What changed.
SELECT o.name, o.modify_date,
       CASE WHEN m.definition LIKE '%MicroEazySmsTemplate%'          THEN 1 ELSE 0 END AS readsTemplates,
       CASE WHEN m.definition LIKE '%sp_MicroEazy_DisbursementSms%' THEN 1 ELSE 0 END AS hooked,
       CASE WHEN m.definition LIKE '%Repay via Paybill 4038021%'     THEN 1 ELSE 0 END AS wrongPaybill   -- must be 0
  FROM sys.sql_modules m
  JOIN sys.objects o ON o.object_id = m.object_id
 WHERE o.name IN (N'sp_FintechSmsReminders', N'sp_DisbursmentNotifications', N'sp_MicroEazy_DisbursementSms');

-- (b) Today's and tomorrow's reminders, previewed. Outcome 'sent' = already
--     reminded today; 'unresolved' = a placeholder could not be filled.
EXEC dbo.sp_FintechSmsReminders @EntityId = 3005, @DryRun = 1;

DECLARE @tomorrow DATE = DATEADD(DAY, 1, CAST(GETDATE() AS DATE));
EXEC dbo.sp_FintechSmsReminders @EntityId = 3005, @DryRun = 1, @AsOf = @tomorrow;

-- (c) The disbursement copy for the latest Fintech loan, rendered, not sent.
DECLARE @m VARCHAR(MAX), @lid INT = (SELECT MAX(id) FROM dbo.Loans WHERE EntityId = 3005 AND isApproved = 1);
EXEC dbo.sp_MicroEazy_DisbursementSms @Loanid = @lid, @Message = @m OUTPUT;
SELECT @lid AS loanId, @m AS wouldSend, LEN(@m) AS chars;

-- (d) After tomorrow's run: the log, per step.
SELECT RunDate, DayOffset, COUNT(*) AS reminders, SUM(CASE WHEN SmsId IS NULL THEN 1 ELSE 0 END) AS withoutOutboxRow
  FROM dbo.MicroEazySmsReminderLog
 WHERE EntityId = 3005 AND RunDate >= DATEADD(DAY, -2, CAST(GETDATE() AS DATE))
 GROUP BY RunDate, DayOffset
 ORDER BY RunDate, DayOffset;
GO
