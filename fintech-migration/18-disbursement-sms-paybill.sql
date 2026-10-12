/*==========================================================================
  18 · THE FINTECH DISBURSEMENT SMS NAMES THE WRONG PAYBILL

  WHY THIS EXISTS
  sp_DisbursmentNotifications writes the "your loan has been disbursed" SMS
  for every book; sp_FinalApproval and sp_RedisburseLoanFinalize call it.
  Its Micromart Fintech (3005) block, added on 13 Aug 2026, tells the
  customer:

      "Dear <name>, your loan of Ksh.<amount> has been disbursed to your
       account. Repay via Paybill 4038021. Dial *483*490# to apply your
       next loan."

  4038021 is Micromart Africa's (3002) paybill. Fintech's is 4329635:
  Transactions.dbo.PAYBILLS holds exactly one paybill for 3005, and it is
  4329635 (3002 has four: 4038021, 4037989, 4038015, 4038023).

  Read live on 6 Oct 2026: 139 Fintech disbursement messages in the
  previous 30 days carried 4038021, including the two latest on 5 Oct. A
  customer who does what the SMS says pays into a 3002 account, where
  RepaymentTrigger allocates by phone inside 3002 -- the Fintech loan is
  not credited and starts ageing into arrears.

  WHAT THIS DOES
  Changes ONE literal inside the 3005 block:
      'Repay via Paybill 4038021'  ->  'Repay via Paybill 4329635'
  Nothing else in the procedure moves. The script edits the CURRENT
  definition (a change Micromart made since 6 Oct survives it) and saves
  that definition to dbo.MicroEazyProcBackup in the same transaction.

  The message length does not change (same number of digits), so the
  one-segment sizing the block was written to still holds: 148 characters
  at worst, with a 15-character name and a 6-digit amount.

  19-comms-centre-sms-templates.sql goes further (the console can then
  edit this message), and repeats this fix if 18 was skipped. Run 18 now;
  it does not wait for 19.

  Run in SSMS against Serviceconnect, ONE SECTION AT A TIME, reading the
  messages pane between each. Every section is safe to re-run.
  Undo with 18-19-ROLLBACK-comms-centre.sql, section R1.
  ==========================================================================*/


/* -------------------------------------------------------------------------
   18.0 · PREFLIGHT — read-only. Keep the output.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;

-- (a) The wrong literal must appear exactly once, and the right one not at all.
SELECT (DATALENGTH(m.definition) - DATALENGTH(REPLACE(m.definition, N'Repay via Paybill 4038021', N'')))
         / DATALENGTH(N'Repay via Paybill 4038021')                         AS wrongPaybillLines,   -- must be 1
       (DATALENGTH(m.definition) - DATALENGTH(REPLACE(m.definition, N'Repay via Paybill 4329635', N'')))
         / DATALENGTH(N'Repay via Paybill 4329635')                         AS rightPaybillLines,   -- 0 before, 1 after
       m.uses_ansi_nulls, m.uses_quoted_identifier,
       o.modify_date
  FROM sys.sql_modules m
  JOIN sys.objects o ON o.object_id = m.object_id
 WHERE m.object_id = OBJECT_ID(N'dbo.sp_DisbursmentNotifications');

-- (b) Which paybill each book really owns.
SELECT EntityId, PayBillNumber FROM Transactions.dbo.PAYBILLS WHERE EntityId IN (3002, 3005) ORDER BY EntityId;

-- (c) What customers have been told. Notifications.dbo.SMS is a heap with no
--     index, so this scans it (about a second); run it once, not in a loop.
SELECT CASE WHEN smsMessage LIKE '%Paybill 4038021%' THEN 'told 4038021 (WRONG)'
            WHEN smsMessage LIKE '%Paybill 4329635%' THEN 'told 4329635'
            ELSE 'other' END                                  AS paybillInSms,
       COUNT(*) AS messages, MIN(CreateDate) AS firstSent, MAX(CreateDate) AS lastSent
  FROM Notifications.dbo.SMS
 WHERE EntityId = 3005
   AND smsMessage LIKE '%has been disbursed to your account%'
 GROUP BY CASE WHEN smsMessage LIKE '%Paybill 4038021%' THEN 'told 4038021 (WRONG)'
               WHEN smsMessage LIKE '%Paybill 4329635%' THEN 'told 4329635'
               ELSE 'other' END;
GO


/* -------------------------------------------------------------------------
   18.0b · OPTIONAL, READ-ONLY — who may have paid into the wrong book.

   Repayments into 4038021 land in INCOMINGC2B under EntityId 3002, keyed by
   the account the customer typed (BillRefNumber, normally their phone).
   This lists the 3002 payments made, since the first 3005 disbursement SMS
   that named 4038021, by phones belonging to Fintech borrowers who were sent
   that SMS. Every row is a payment to reconcile by hand against the Fintech
   loan; none is moved by this script.

   It is slow by construction (INCOMINGC2B and SMS are unindexed) -- a minute
   or two. INCOMINGC2B has no transaction date, so the window is the row id
   of the first payment reconciled on or after the first wrong SMS.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

IF OBJECT_ID('tempdb..#told') IS NOT NULL DROP TABLE #told;
SELECT RIGHT(REPLACE(REPLACE(LTRIM(RTRIM(smsto)), '+', ''), ' ', ''), 9) AS p9,
       MIN(CreateDate) AS firstTold
  INTO #told
  FROM Notifications.dbo.SMS
 WHERE EntityId = 3005
   AND smsMessage LIKE '%has been disbursed to your account%'
   AND smsMessage LIKE '%Paybill 4038021%'
 GROUP BY RIGHT(REPLACE(REPLACE(LTRIM(RTRIM(smsto)), '+', ''), ' ', ''), 9);
CREATE CLUSTERED INDEX ix_told ON #told (p9);

DECLARE @since DATETIME = (SELECT MIN(firstTold) FROM #told);
DECLARE @fromId INT = (SELECT MIN(Id) FROM dbo.INCOMINGC2B WHERE DateReconcilled >= @since);

SELECT COUNT(*) AS customersToldWrongPaybill, @since AS firstWrongSms, @fromId AS fromC2BId FROM #told;

SELECT c.Id AS c2bId, c.TransId, c.TransAmount, c.BillRefNumber, c.EntityId,
       c.BorrowerId, c.LoanId, c.IsReconciled, c.DateReconcilled
  FROM dbo.INCOMINGC2B c
  JOIN #told t ON t.p9 = RIGHT(REPLACE(REPLACE(LTRIM(RTRIM(c.BillRefNumber)), '+', ''), ' ', ''), 9)
 WHERE c.Id >= ISNULL(@fromId, 0)
   AND c.EntityId <> 3005
 ORDER BY c.Id;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;   -- back to the default for the sections below
GO


/* -------------------------------------------------------------------------
   18.1 · THE FIX — one literal in Micromart's procedure.

   Run once with @Install = 0 (the default): it checks everything and prints
   the procedure as it would read. Then set @Install = 1.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 60000;   -- an approval in flight holds the procedure for a moment

DECLARE @Install BIT = 0;   -- <<< set to 1 once the printout reads right

IF OBJECT_ID(N'dbo.MicroEazyProcBackup') IS NULL
BEGIN
    -- The exact text of every Micromart procedure scripts 18 and 19 alter,
    -- saved in the same transaction as the ALTER. The rollback reads it.
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

DECLARE @obj   INT           = OBJECT_ID(N'dbo.sp_DisbursmentNotifications');
DECLARE @def   NVARCHAR(MAX) = OBJECT_DEFINITION(@obj);
DECLARE @wrong NVARCHAR(100) = N'Repay via Paybill 4038021';
DECLARE @right NVARCHAR(100) = N'Repay via Paybill 4329635';
DECLARE @n INT, @at INT, @len INT, @new NVARCHAR(MAX);

IF @def IS NULL
BEGIN
    RAISERROR(N'dbo.sp_DisbursmentNotifications was not found. Nothing changed.', 16, 1);
    RETURN;
END

SET @n = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @wrong, N''))) / DATALENGTH(@wrong);
IF @n = 0 AND CHARINDEX(@right, @def) > 0
BEGIN
    PRINT N'The Fintech block already names 4329635. Nothing to do.';
    RETURN;
END
IF @n <> 1
BEGIN
    RAISERROR(N'"%s" appears %d times in the procedure, not once: it has changed since 6 Oct 2026. Nothing changed. Send its current text.', 16, 1, @wrong, @n);
    RETURN;
END

-- The one occurrence must sit inside the 3005 block, after its marker.
IF CHARINDEX(N'IF (@EntityId = 3005)', @def) = 0
   OR CHARINDEX(@wrong, @def) < CHARINDEX(N'IF (@EntityId = 3005)', @def)
BEGIN
    RAISERROR(N'The wrong paybill is not inside the IF (@EntityId = 3005) block. Nothing changed. Send the procedure''s current text.', 16, 1);
    RETURN;
END

IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = @obj AND (uses_ansi_nulls = 0 OR uses_quoted_identifier = 0))
BEGIN
    RAISERROR(N'The procedure was created with ANSI_NULLS or QUOTED_IDENTIFIER off, and this session would change that. Nothing changed.', 16, 1);
    RETURN;
END

-- The stored text opens with CREATE (or ALTER, once altered); that keyword becomes ALTER.
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

-- The literal sits after the keyword, so the replacement leaves @at where it was.
SET @new = STUFF(REPLACE(@def, @wrong, @right), @at, @len, N'ALTER');

IF @Install = 0
BEGIN
    PRINT N'All checks passed. NOTHING CHANGED. After the fix the procedure would read:';
    PRINT N'------------------------------------------------------------------';
    PRINT @new;
    PRINT N'------------------------------------------------------------------';
    PRINT N'Set @Install = 1 and run 18.1 again to apply it.';
    RETURN;
END

BEGIN TRANSACTION;
    INSERT INTO dbo.MicroEazyProcBackup (Script, ProcName, Sha256, Definition)
    VALUES ('18', N'dbo.sp_DisbursmentNotifications', CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', @def), 2), @def);
    EXEC sys.sp_executesql @new;
COMMIT TRANSACTION;

IF CHARINDEX(@right, OBJECT_DEFINITION(@obj)) > 0 AND CHARINDEX(@wrong, OBJECT_DEFINITION(@obj)) = 0
    PRINT N'Fixed. The next Fintech disbursement SMS names Paybill 4329635 -- confirm with 18.2 after it goes out.';
ELSE
    RAISERROR(N'The ALTER ran but the definition does not read right. Look before going further.', 16, 1);
GO


/* -------------------------------------------------------------------------
   18.2 · VERIFY — read-only. After the next Fintech disbursement.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SELECT TOP 5 CreateDate, isSent, DeliveryStatus,
       CASE WHEN smsMessage LIKE '%Paybill 4329635%' THEN 'RIGHT (4329635)'
            WHEN smsMessage LIKE '%Paybill 4038021%' THEN 'WRONG (4038021)'
            ELSE '?' END AS paybill
  FROM Notifications.dbo.SMS
 WHERE EntityId = 3005
   AND smsMessage LIKE '%has been disbursed to your account%'
 ORDER BY CreateDate DESC;
GO
