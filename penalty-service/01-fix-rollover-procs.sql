/* ============================================================================
   01 · FIX THE NIGHTLY PENALTY PROCEDURES                      DRY RUN BY DEFAULT

   The 01:01 job calls sp_GeneralRolloverService (and its _InstallmentWise twin)
   by name, with no parameters. This script replaces both, keeping everything
   they do today and changing six things:

   1. RollOverStartDate now limits the BACKLOG, not just the switch-on day.
      A loan is penalised only if its penalty day (maturity + grace + 1) falls
      on or after the product's start date. Today the start date is only
      compared with GETDATE(), so setting it to "today" still back-charges a
      loan that fell due two years ago. Script 02 uses this to give the CEO a
      choice: charge all, charge only the arrears window, or go forward only.
      Products whose start date is 2025-03-20 behave exactly as before.

   2. Penalty = ISNULL(Penalty, 0) + amount. NULL + 340 is NULL, so every loan
      that entered the engine with an empty column (all 3,044 queued on
      17 Sep 2026) was charged and texted while the arrears report kept
      reading 0.00.

   3. A product with no penalty value is skipped. A NULL RollOverValue makes
      the penalty NULL, and LoanBalance + NULL would have wiped the balance.

   4. The writes run in one transaction. The old procedure had none: a
      failure half-way left balances raised with no statement line or SMS.
      On failure it now rolls back and RAISERRORs (the job step shows the
      failure) without aborting whatever else the job runs after it.

   5. The statement line no longer needs a savings row (INNER -> LEFT JOIN).
      A borrower without Transactions.dbo.AccountSavings was charged with no
      line in CustomerStatement.

   6. (maturity procedure only) The schedule spread lands only on open
      instalments that still carry an amount. It divided the penalty by that
      count but added the share to zero-amount rows too, overstating the
      schedule on 19 of the 3,044 queued loans.

   NOT changed: the SMS wording ("...to avoid further penalties" - the engine
   is once-only), the 20% rate, the once-per-loan rule (IsRolledOver), the
   LoanChargesSchedule handling, and which loans the InstallmentWise
   procedure flags as penalised.

   SAFETY
   * Refuses to run if either live procedure differs from the version read on
     17 Sep 2026 (SHA-256 below) - someone has changed it since, re-read first.
     Re-running after a successful install is allowed.
   * Saves the current definitions to dbo.MicroEazyProcBackup first.
     99-rollback.sql restores them.
   * Dry run: installs inside a transaction, proves both compiled and carry
     the marker, then ROLLS BACK. Nothing persists. The job only runs at 01:01,
     so the few milliseconds of schema lock touch nobody.

   RUN: in SSMS against Serviceconnect, whole file (F5). For the real thing,
   change the 1 to 0 on the line marked  <<< DRY RUN  and run it again.
   ==========================================================================*/
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;          -- both procedures were created with these ON
SET QUOTED_IDENTIFIER ON;
SET NOEXEC OFF;
GO

EXEC sys.sp_set_session_context @key = N'penalty.dryrun', @value = 1;   -- <<< DRY RUN (1 = rehearse, 0 = install)
GO

/* -- 1 · preconditions + backup ------------------------------------------ */
DECLARE @DryRun BIT = CAST(SESSION_CONTEXT(N'penalty.dryrun') AS BIT);
DECLARE @Marker NVARCHAR(40) = N'penalty-service/01';

DECLARE @expected TABLE (ProcName SYSNAME PRIMARY KEY, Sha256 VARCHAR(64));
INSERT @expected VALUES
    (N'sp_GeneralRolloverService',                 '57253F2356D2A46EA72ABBD4A50BA7B4C9204AF1B777AA174DC16C8CE23F7847'),
    (N'sp_GeneralRolloverService_InstallmentWise', 'A36FD64115A7123FC579F3912485C743A9F1F21748ED1FA95255017FF669E1F4');

DECLARE @live TABLE (ProcName SYSNAME, Definition NVARCHAR(MAX), Sha256 VARCHAR(64), Installed BIT);
INSERT @live
SELECT e.ProcName, m.definition,
       CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', m.definition), 2),
       CASE WHEN m.definition LIKE N'%' + @Marker + N'%' THEN 1 ELSE 0 END
FROM @expected e
LEFT JOIN sys.sql_modules m ON m.object_id = OBJECT_ID(N'dbo.' + e.ProcName);

SELECT l.ProcName, l.Sha256 AS live_sha256,
       CASE WHEN l.Definition IS NULL THEN 'MISSING'
            WHEN l.Installed = 1 THEN 'already fixed - re-install is harmless'
            WHEN l.Sha256 = e.Sha256 THEN 'matches 17 Sep 2026 - OK'
            ELSE 'CHANGED since 17 Sep 2026 - STOP' END AS status_
FROM @live l JOIN @expected e ON e.ProcName = l.ProcName;

IF EXISTS (SELECT 1 FROM @live l JOIN @expected e ON e.ProcName = l.ProcName
           WHERE l.Definition IS NULL OR (l.Installed = 0 AND l.Sha256 <> e.Sha256))
BEGIN
    RAISERROR('STOPPED: a live procedure is missing or has changed since it was read on 17 Sep 2026. Nothing was changed.', 16, 1);
    SET NOEXEC ON;
    RETURN;
END;

IF OBJECT_ID(N'dbo.MicroEazyProcBackup') IS NULL
BEGIN
    BEGIN TRANSACTION;
    CREATE TABLE dbo.MicroEazyProcBackup (
        Id         INT IDENTITY(1,1) PRIMARY KEY,
        ProcName   SYSNAME        NOT NULL,
        Definition NVARCHAR(MAX)  NOT NULL,
        Sha256     VARCHAR(64)    NOT NULL,
        SavedAt    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
        SavedBy    SYSNAME        NOT NULL DEFAULT SUSER_SNAME(),
        Script     VARCHAR(60)    NOT NULL
    );
END
ELSE
    BEGIN TRANSACTION;

-- Only a pre-fix definition is worth keeping; re-running must not overwrite
-- the original with our own version.
INSERT dbo.MicroEazyProcBackup (ProcName, Definition, Sha256, Script)
SELECT ProcName, Definition, Sha256, '01-fix-rollover-procs'
FROM @live WHERE Installed = 0;

PRINT CASE WHEN @DryRun = 1 THEN 'DRY RUN - installing inside a transaction that will be rolled back.'
           ELSE 'LIVE - installing.' END;
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('STOPPED: the transaction was lost before install. Nothing was changed.', 16, 1); SET NOEXEC ON; END;
GO

/* -- 2 · penalise on loan maturity --------------------------------------- */
CREATE OR ALTER PROCEDURE [dbo].[sp_GeneralRolloverService]
AS
BEGIN
    -- penalty-service/01 (17 Sep 2026): start date limits the backlog, NULL-safe Penalty,
    -- skip products with no value, one transaction, statement line without a savings row,
    -- schedule spread only onto instalments that carry an amount. See the script header.
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LoanTable TABLE (
        LoanId INT,
        BorrowerId INT,
        ProductId INT,
        RolloverValue DECIMAL(18, 2),
        RolloverValueType INT,
        LoanBalance DECIMAL(18, 2),
        PhoneNumber NVARCHAR(15),
        EntityId INT,
        TotalAmount DECIMAL(18, 2),
        PenaltyAmount DECIMAL(18, 2)
    );

    -- Insert eligible loans into @LoanTable
    INSERT INTO @LoanTable (LoanId, BorrowerId, ProductId, RolloverValue, RolloverValueType, LoanBalance, PhoneNumber, EntityId, TotalAmount)
    SELECT
        L.id as LoanId,
        B.ID AS BorrowerId,
        P.ID AS ProductId,
        P.RollOverValue,
        P.RollOverValueType,
        L.LoanBalance,
        B.PhoneNumber,
        B.EntityId,
        SUM(Loanbalance) AS TotalAmount
    FROM loans L
    INNER JOIN Borrowers B ON B.ID = L.BorrowerId
    INNER JOIN Products P ON P.ID = L.ProductId
    WHERE
         P.RollOverApplication = 1
        AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), L.EXPECTEDCLEARDATE) < GETDATE()
        -- the penalty day itself must fall on or after the product's start date
        AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), L.EXPECTEDCLEARDATE) >= P.RollOverStartDate
        AND Loanbalance>0
        AND L.IsRolledOver=0
        AND P.RollOverPenalty = 1
        AND P.RollOverValue > 0
        AND P.RollOverStartDate<=GETDATE()
    GROUP BY L.id, B.ID, P.ID, P.RollOverValue, P.RollOverValueType, L.LoanBalance, B.PhoneNumber, B.EntityId;

    IF NOT EXISTS (SELECT 1 FROM @LoanTable) RETURN;

    -- Calculate Penalty Amount for each loan
    UPDATE @LoanTable
    SET PenaltyAmount = CASE
        WHEN RolloverValueType = 1 THEN (RolloverValue / 100) * TotalAmount
        ELSE RolloverValue
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Update LoanBalances in Loans table
        UPDATE L
        SET L.LoanBalance = L.LoanBalance + T.PenaltyAmount,Penalty=ISNULL(L.Penalty, 0) + t.PenaltyAmount,IsRolledOver=1,
            L.LoanCleared = 0
        FROM Loans L
        INNER JOIN @LoanTable T ON L.ID = T.LoanId;

        -- Update existing LoanChargesSchedule in bulk
        UPDATE LCS
        SET LCS.AmountToPay = LCS.AmountToPay + T.PenaltyAmount
        FROM LoanChargesSchedule LCS
        INNER JOIN @LoanTable T ON LCS.LoanId = T.LoanId;

        -- Insert into LoanChargesSchedule in bulk
        INSERT INTO LoanChargesSchedule (EntryId, LoanId, AmountToPay, ExpectedDueDate, ProductId, Status, EntityId, ItemId)
        SELECT 1, LoanId, PenaltyAmount, GETDATE(), ProductId, 0,L.EntityId, P.RolloverJlAccount
        FROM @LoanTable l inner join Products p on p.id=l.ProductId
        WHERE NOT EXISTS (SELECT 1 FROM LoanChargesSchedule LCS WHERE LCS.LoanId = l.LoanId);

        -- Insert into CustomerStatement in bulk
        INSERT INTO CustomerStatement (UserId, LoanId, Amount, TransType, Narration, EntityId, LoanBalance, AccountBalance, TransactedDate)
        SELECT L.BorrowerId, LoanId, PenaltyAmount, 1, 'Late Payment Penalty', EntityId, LoanBalance + PenaltyAmount, ISNULL(S.Amount, 0), GETDATE()
        FROM @LoanTable L LEFT JOIN Transactions.DBO.AccountSavings S ON S.BorrowerId=L.BorrowerId;

        -- Insert into ManagedLoans in bulk
        INSERT INTO ManagedLoans (LoanId, InitialOlb, EffectedAmount, NewOlb, DoneBy, DateDone, TransType, isApproved, ApprovedBy, ApprovedDate, EntityId)
        SELECT LoanId, LoanBalance, PenaltyAmount, LoanBalance + PenaltyAmount, 101, GETDATE(), 6, 1, 101, GETDATE(), EntityId
        FROM @LoanTable;

        -- Update LoanSchedule AmountToPay in bulk
        UPDATE LS
        SET LS.AmountToPay = LS.AmountToPay + (T.PenaltyAmount / SubQ.NumRows)
        FROM LoanSchedule LS
        INNER JOIN (
            SELECT LoanId, COUNT(*) AS NumRows
            FROM LoanSchedule
            WHERE STATUS = 0 AND AmountToPay > 0
            GROUP BY LoanId
        ) AS SubQ ON LS.LoanId = SubQ.LoanId
        INNER JOIN @LoanTable T ON LS.LoanId = T.LoanId
        WHERE LS.STATUS = 0 AND LS.AmountToPay > 0;

        -- Insert SMS notifications in bulk
        INSERT INTO Notifications.DBO.SMS (SmsMessage, SmsTo, EntityId, CreateDate, CreatedBy, IsSent, SmsProviderId)
        SELECT 'Dear '+R.firstName+', a penalty of KES '+CONVERT(VARCHAR,l.PenaltyAmount)+' has been applied to your loan due to late payment. Your new outstanding loan balance is KES '+CONVERT(varchar,LoanBalance + PenaltyAmount)+'. Kindly make payment to avoid further penalties. For inquiries, contact your Agent. Thank you.', l.PhoneNumber, l.EntityId, GETDATE(), 101, 0, B.SmsProviderId
        FROM @LoanTable L INNER JOIN BsEntity B ON B.ID=L.EntityId INNER JOIN Borrowers R ON R.ID=L.BorrowerId;

        -- Update LoanSchedule to mark Penalty as Applied in bulk
        UPDATE LS
        SET LS.IsPenaltyAppled = 1
        FROM LoanSchedule LS
        INNER JOIN Loans L ON LS.LoanId = L.ID
        INNER JOIN Products P ON P.ID = L.ProductId
        WHERE LS.LoanId IN (SELECT LoanId FROM @LoanTable)
            AND LS.IsPenaltyAppled = 0
            AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), LS.ExpectedDueDate) < GETDATE()
            AND (LS.PrincipleToPay > 1 OR LS.InterestToPay > 1)
            AND P.RollOverPenalty = 1
            AND P.RollOverApplication=1
            AND P.RollOverStartDate<=GETDATE();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        DECLARE @err NVARCHAR(2048) = N'sp_GeneralRolloverService rolled back, nobody was charged: ' + ERROR_MESSAGE();
        RAISERROR('%s', 16, 1, @err);
    END CATCH
END;
GO

IF @@TRANCOUNT = 0
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_GeneralRolloverService')) NOT LIKE N'%penalty-service/01%'
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('STOPPED: sp_GeneralRolloverService did not install. Everything was rolled back.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* -- 3 · penalise per instalment ----------------------------------------- */
CREATE OR ALTER PROCEDURE [dbo].[sp_GeneralRolloverService_InstallmentWise]
AS
BEGIN
    -- penalty-service/01 (17 Sep 2026): start date limits the backlog, NULL-safe Penalty,
    -- skip products with no value, one transaction, statement line without a savings row.
    -- The schedule spread and IsPenaltyAppled flagging are deliberately unchanged here.
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LoanTable TABLE (
        LoanId INT,
        BorrowerId INT,
        ProductId INT,
        RolloverValue DECIMAL(18, 2),
        RolloverValueType INT,
        LoanBalance DECIMAL(18, 2),
        PhoneNumber NVARCHAR(15),
        EntityId INT,
        TotalAmount DECIMAL(18, 2),
        PenaltyAmount DECIMAL(18, 2)
    );

    -- Insert eligible loans into @LoanTable
    INSERT INTO @LoanTable (LoanId, BorrowerId, ProductId, RolloverValue, RolloverValueType, LoanBalance, PhoneNumber, EntityId, TotalAmount)
    SELECT
        LS.LoanId,
        B.ID AS BorrowerId,
        P.ID AS ProductId,
        P.RollOverValue,
        P.RollOverValueType,
        L.LoanBalance,
        B.PhoneNumber,
        B.EntityId,
        SUM(LS.InterestToPay + LS.PrincipleToPay) AS TotalAmount
    FROM LoanSchedule LS
    INNER JOIN Loans L ON L.ID = LS.LoanId
    INNER JOIN Borrowers B ON B.ID = L.BorrowerId
    INNER JOIN Products P ON P.ID = L.ProductId
    WHERE
         P.RollOverApplication = 2
         AND LS.IsPenaltyAppled=0
        AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), LS.ExpectedDueDate) < GETDATE()
        -- the instalment's penalty day must fall on or after the product's start date
        AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), LS.ExpectedDueDate) >= P.RollOverStartDate
        AND (LS.PrincipleToPay > 1 OR LS.InterestToPay > 1)
        AND P.RollOverPenalty = 1
        AND P.RollOverValue > 0
        AND P.RollOverStartDate<=GETDATE()
    GROUP BY LS.LoanId, B.ID, P.ID, P.RollOverValue, P.RollOverValueType, L.LoanBalance, B.PhoneNumber, B.EntityId;

    IF NOT EXISTS (SELECT 1 FROM @LoanTable) RETURN;

    -- Calculate Penalty Amount for each loan
    UPDATE @LoanTable
    SET PenaltyAmount = CASE
        WHEN RolloverValueType = 1 THEN (RolloverValue / 100) * TotalAmount
        ELSE RolloverValue
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Update LoanBalances in Loans table
        UPDATE L
        SET L.LoanBalance = L.LoanBalance + T.PenaltyAmount,Penalty=ISNULL(L.Penalty, 0) + t.PenaltyAmount,
            L.LoanCleared = 0
        FROM Loans L
        INNER JOIN @LoanTable T ON L.ID = T.LoanId;

        -- Update existing LoanChargesSchedule in bulk
        UPDATE LCS
        SET LCS.AmountToPay = LCS.AmountToPay + T.PenaltyAmount
        FROM LoanChargesSchedule LCS
        INNER JOIN @LoanTable T ON LCS.LoanId = T.LoanId;

        -- Insert into LoanChargesSchedule in bulk
        INSERT INTO LoanChargesSchedule (EntryId, LoanId, AmountToPay, ExpectedDueDate, ProductId, Status, EntityId, ItemId)
        SELECT 1, LoanId, PenaltyAmount, GETDATE(), ProductId, 0,L.EntityId, P.RolloverJlAccount
        FROM @LoanTable l inner join Products p on p.id=l.ProductId
        WHERE NOT EXISTS (SELECT 1 FROM LoanChargesSchedule LCS WHERE LCS.LoanId = l.LoanId);

        -- Insert into CustomerStatement in bulk
        INSERT INTO CustomerStatement (UserId, LoanId, Amount, TransType, Narration, EntityId, LoanBalance, AccountBalance, TransactedDate)
        SELECT L.BorrowerId, LoanId, PenaltyAmount, 1, 'Late Payment Penalty', EntityId, LoanBalance + PenaltyAmount, ISNULL(S.Amount, 0), GETDATE()
        FROM @LoanTable L LEFT JOIN Transactions.DBO.AccountSavings S ON S.BorrowerId=L.BorrowerId;

        -- Insert into ManagedLoans in bulk
        INSERT INTO ManagedLoans (LoanId, InitialOlb, EffectedAmount, NewOlb, DoneBy, DateDone, TransType, isApproved, ApprovedBy, ApprovedDate, EntityId)
        SELECT LoanId, LoanBalance, PenaltyAmount, LoanBalance + PenaltyAmount, 101, GETDATE(), 6, 1, 101, GETDATE(), EntityId
        FROM @LoanTable;

        -- Update LoanSchedule AmountToPay in bulk
        UPDATE LS
        SET LS.AmountToPay = LS.AmountToPay + (T.PenaltyAmount / SubQ.NumRows),IsPenaltyAppled=1
        FROM LoanSchedule LS
        INNER JOIN (
            SELECT LoanId, COUNT(*) AS NumRows
            FROM LoanSchedule
            WHERE STATUS = 0 AND AmountToPay > 0
            GROUP BY LoanId
        ) AS SubQ ON LS.LoanId = SubQ.LoanId
        INNER JOIN @LoanTable T ON LS.LoanId = T.LoanId
        WHERE LS.STATUS = 0;

        -- Insert SMS notifications in bulk
        INSERT INTO Notifications.DBO.SMS (SmsMessage, SmsTo, EntityId, CreateDate, CreatedBy, IsSent, SmsProviderId)
        SELECT 'Dear '+R.firstName+', a penalty of KES '+CONVERT(VARCHAR,l.PenaltyAmount)+' has been applied to your loan due to late payment. Your new outstanding loan balance is KES '+CONVERT(varchar,LoanBalance + PenaltyAmount)+'. Kindly make payment to avoid further penalties. For inquiries, contact your Agent. Thank you.', l.PhoneNumber, l.EntityId, GETDATE(), 101, 0, B.SmsProviderId
        FROM @LoanTable L INNER JOIN BsEntity B ON B.ID=L.EntityId INNER JOIN Borrowers R ON R.ID=L.BorrowerId;

        -- Update LoanSchedule to mark Penalty as Applied in bulk
        UPDATE LS
        SET LS.IsPenaltyAppled = 1
        FROM LoanSchedule LS
        INNER JOIN Loans L ON LS.LoanId = L.ID
        INNER JOIN Products P ON P.ID = L.ProductId
        WHERE LS.LoanId IN (SELECT LoanId FROM @LoanTable)
            AND LS.IsPenaltyAppled = 0
            AND DATEADD(DAY, ISNULL(P.RollOverGracePeriod + 1, 0), LS.ExpectedDueDate) < GETDATE()
            AND (LS.PrincipleToPay > 1 OR LS.InterestToPay > 1)
            AND P.RollOverPenalty = 1
            AND P.RollOverApplication=2
            AND P.RollOverStartDate<=GETDATE();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        DECLARE @err NVARCHAR(2048) = N'sp_GeneralRolloverService_InstallmentWise rolled back, nobody was charged: ' + ERROR_MESSAGE();
        RAISERROR('%s', 16, 1, @err);
    END CATCH
END;
GO

IF @@TRANCOUNT = 0
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_GeneralRolloverService_InstallmentWise')) NOT LIKE N'%penalty-service/01%'
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('STOPPED: sp_GeneralRolloverService_InstallmentWise did not install. Everything was rolled back.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* -- 4 · proof, then commit or roll back --------------------------------- */
SELECT o.name AS procedure_,
       CASE WHEN m.definition LIKE N'%penalty-service/01%' THEN 'fixed' ELSE 'OLD' END AS version_,
       CASE WHEN m.definition LIKE N'%ISNULL(L.Penalty, 0)%' THEN 'yes' ELSE 'NO' END AS null_safe_penalty,
       CASE WHEN m.definition LIKE N'%>= P.RollOverStartDate%' THEN 'yes' ELSE 'NO' END AS start_date_limits_backlog,
       CASE WHEN m.definition LIKE N'%P.RollOverValue > 0%' THEN 'yes' ELSE 'NO' END AS skips_valueless_products
FROM sys.sql_modules m JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.name IN (N'sp_GeneralRolloverService', N'sp_GeneralRolloverService_InstallmentWise');

IF CAST(SESSION_CONTEXT(N'penalty.dryrun') AS BIT) = 1
BEGIN
    ROLLBACK TRANSACTION;
    PRINT 'DRY RUN complete: both procedures compiled and passed the checks above, then were ROLLED BACK. Nothing changed.';
END
ELSE
BEGIN
    COMMIT TRANSACTION;
    PRINT 'INSTALLED. The 01:01 job picks this up on its next run. Originals are in dbo.MicroEazyProcBackup.';
END;
GO
SET NOEXEC OFF;
GO
