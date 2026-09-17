/* ============================================================================
   05 · A PRODUCT SAVE MUST NOT SWITCH THE PENALTY OFF          DRY RUN BY DEFAULT

   How penalties died in June and August: the portal's edit screen never
   loaded RollOverApplication, so it reopened with neither "On Loan Maturity"
   nor "On Installments" ticked, posted nothing, and UpdateProduct wrote
   RollOverApplication = NULL. The engine then skipped the product. Proof:
   8 WEEKS (30114) was penalised at 01:01 on 25 Aug, edited at 09:29, and never
   penalised again. The portal fix is in ServiceSuite-Portal (ProductManager,
   ProductController, the two product views). This is the database half, and
   it protects against whichever portal build is live today.

   UpdateProduct
     * RollOverApplication and RolloverJlAccount keep their stored value when
       the caller sends NULL or nothing. The screen has no way to mean "erase
       this", and every erase so far was an accident. (RollOverStartDate is not
       written by either procedure; the fixed portal saves it separately.)
     * Accepts @RolloverJlAccount. The current ServiceSuite-Portal build sends
       it and Micromart's procedure did not declare it, so that build could
       not save a product here at all ("too many arguments specified").
   NewProduct
     * Accepts @RolloverJlAccount and stores it.

   Nothing else in either procedure changes; the text below is the live
   definition read on 17 Sep 2026 with only those lines added.

   SAFETY: refuses if either live procedure changed since 17 Sep (SHA-256),
   backs the originals up to dbo.MicroEazyProcBackup, and in dry run installs
   inside a transaction and rolls back. 99-rollback.sql restores the originals.

   ORDER: install this BEFORE deploying the fixed portal build to Micromart.
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
DECLARE @Marker NVARCHAR(40) = N'penalty-service/05';

DECLARE @expected TABLE (ProcName SYSNAME PRIMARY KEY, Sha256 VARCHAR(64));
INSERT @expected VALUES
    (N'NewProduct',    '27B5FC33B7683FFC410D5351E6886DA43EA2DFF51C163E358444403F20982C07'),
    (N'UpdateProduct', 'C7255C61200DE28F0A675617804E11E51209AFD426E2CC69F1E0FE5C269A268A');

DECLARE @live TABLE (ProcName SYSNAME, Definition NVARCHAR(MAX), Sha256 VARCHAR(64), Installed BIT);
INSERT @live
SELECT e.ProcName, m.definition,
       CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', m.definition), 2),
       CASE WHEN m.definition LIKE N'%' + @Marker + N'%' THEN 1 ELSE 0 END
FROM @expected e
LEFT JOIN sys.sql_modules m ON m.object_id = OBJECT_ID(N'dbo.' + e.ProcName);

SELECT l.ProcName, l.Sha256 AS live_sha256,
       CASE WHEN l.Definition IS NULL THEN 'MISSING'
            WHEN l.Installed = 1 THEN 'already guarded - re-install is harmless'
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

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.MicroEazyProcBackup') IS NULL
    CREATE TABLE dbo.MicroEazyProcBackup (
        Id         INT IDENTITY(1,1) PRIMARY KEY,
        ProcName   SYSNAME        NOT NULL,
        Definition NVARCHAR(MAX)  NOT NULL,
        Sha256     VARCHAR(64)    NOT NULL,
        SavedAt    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
        SavedBy    SYSNAME        NOT NULL DEFAULT SUSER_SNAME(),
        Script     VARCHAR(60)    NOT NULL
    );

INSERT dbo.MicroEazyProcBackup (ProcName, Definition, Sha256, Script)
SELECT ProcName, Definition, Sha256, '05-product-save-guard'
FROM @live WHERE Installed = 0;

PRINT CASE WHEN @DryRun = 1 THEN 'DRY RUN - installing inside a transaction that will be rolled back.'
           ELSE 'LIVE - installing.' END;
GO

IF @@TRANCOUNT = 0 BEGIN RAISERROR('STOPPED: the transaction was lost before install. Nothing was changed.', 16, 1); SET NOEXEC ON; END;
GO

CREATE OR ALTER PROCEDURE [dbo].[NewProduct]
    @ProductName NVARCHAR(100),
    @ProductDesc NVARCHAR(1000),
    @MinPrincipal DECIMAL(18, 2),
    @MaxPrincipal DECIMAL(18, 2),
    @InterestMethod NVARCHAR(50),
    @InterestType NVARCHAR(50)=null,
    @InterestRate DECIMAL(18, 2),
    @InterestPeriodType NVARCHAR(50),
    @RepaymentPeriodType NVARCHAR(50),
    @RepaymentPeriod INT,
    @RollOverPenalty DECIMAL(18, 2),
    @RollOverGracePeriodType NVARCHAR(50)=null,
    @RollOverGracePeriod INT=null,
    @RollOverApplication INT=NULL,
    @RollOverValueType NVARCHAR(50)=null,
    @RollOverValue DECIMAL(18, 2)=null,
    @RollOverOn NVARCHAR(50)=null,
    @RollOverType NVARCHAR(50)=null,
    @RollOverPeriod INT=null,
    @RollOverPeriodType INT=null,
    @RollOverLimitType INT=Null,
    @RollOverLimit DECIMAL(18, 2)=null,
    @RolloverJlAccount INT=NULL,     -- penalty-service/05: sent by the current portal build
    @newLoanStatus int,
    @newDrtFndLimit DECIMAL(18, 2)=null,
    @repeatLoanStatus int,
    @repeatDrtFndLimit DECIMAL(18, 2)=null,
    @WorkflowId Int=null,
    @repeatWorkflowId Int=null,
    @guarantorRequired Int=null,
    @guarantorReborrow Int=null,
    @securityRequired Int=null,
    @securityDetails Int=null,
    @securityValueColumn Int=null,
    @securityLimitType Int=null,
    @securityLimitValue DECIMAL(18, 2)=null,
    @minLoanLimit DECIMAL(18, 2)=null,
    @MinCreditScore DECIMAL(18, 2)=null,
    @attachments NVARCHAR(MAX)=null,
    @additionalFields NVARCHAR(MAX)=null,
    @EntityId int,
    @EntityUnitsList NVARCHAR(MAX)=null,
    @isActive int,
    @CreatedBy nvarchar(50),
    @ProductCategory INT=null,
    @PrincipalType INT=null,
    @PrincipalReference INT=null,
    @PrincipalCalculation INT=null,
    @ProductDetailsId INT=null,
    @ProductDetailsValueId INT=null,
    @DepositValueId INT=null,
    @PrincipalDerease INT=null,
    @PrincipalIncrease INT=null,
    @BackDate INT=null,
    @PostDate INT=null,
    @SkipDayOfTheWeekOnSchedule INT=null,
    @modeOfDisbursement int=3,
    @EnableEarlyRate INT=0,
    @EarlyPaymentDays INT=null,
    @EarlyPaymentRate DECIMAL(18,2)=null,
    @IsUssdMobileEnabled BIT=1,
    @ProductType INT=0,
    @productId int OUTPUT
AS
BEGIN
    INSERT INTO [dbo].[Products]
           ([ProductName],[ProductDesc],[MinPrincipal],[MaxPrincipal],
            [InterestMethod],[InterestType],[InterestRate],
            [InterestPeriod],[InterestPeriodType],[RepaymentPeriod],[RepaymentPeriodType],
            [RollOverPenalty],[RollOverType],[RollOverGracePeriod],[RollOverGracePeriodType],
            [RollOverApplication],[RollOverValueType],[RollOverValue],[RollOverOn],
            [RollOverPeriod],[RollOverPeriodType],[RollOverLimitType],[RollOverLimit],
            [RolloverJlAccount],
            [newLoanStatus],[newDrtFndLimit],[repeatLoanStatus],[repeatDrtFndLimit],
            [WorkflowId],[repeatWorkflowId],[guarantorRequired],[guarantorReborrow],
            [securityRequired],[securityDetails],[securityValueColumn],[securityLimitType],[securityLimitValue],
            [minLoanLimit],[MinCreditScore],[Attachments],[AdditionalFields],
            [IsActive],[EntityId],[EntityUnits],[CreatedBy],[CreatedDate],
            [ProductCategory],[PrincipalType],[PrincipalReference],[PrincipalCalculation],
            [ProductDetailsId],[ProductDetailsValueId],[DepositValueId],[PrincipalDerease],[PrincipalIncrease],
            [BackDate],[PostDate],[SkipDayOfTheWeekOnSchedule],[DisbursmentMode],
            [EnableEarlyRate],[EarlyPaymentDays],[EarlyPaymentRate],[IsUssdMobileEnabled],[ProductType])
    VALUES
           (@ProductName,@ProductDesc,@MinPrincipal,@MaxPrincipal,
            @InterestMethod,@InterestType,@InterestRate,
            @InterestPeriodType,@InterestPeriodType,@RepaymentPeriod,@RepaymentPeriodType,
            @RollOverPenalty,@RollOverType,@RollOverGracePeriod,@RollOverGracePeriodType,
            @RollOverApplication,@RollOverValueType,@RollOverValue,@RollOverOn,
            @RollOverPeriod,@RollOverPeriodType,@RollOverLimitType,@RollOverLimit,
            @RolloverJlAccount,
            @newLoanStatus,@newDrtFndLimit,@repeatLoanStatus,@repeatDrtFndLimit,
            @WorkflowId,@repeatWorkflowId,@guarantorRequired,@guarantorReborrow,
            @securityRequired,@securityDetails,@securityValueColumn,@securityLimitType,@securityLimitValue,
            @minLoanLimit,@MinCreditScore,@attachments,@additionalFields,
            @isActive,@EntityId,@EntityUnitsList,@CreatedBy,GETDATE(),
            @ProductCategory,@PrincipalType,@PrincipalReference,@PrincipalCalculation,
            @ProductDetailsId,@ProductDetailsValueId,@DepositValueId,@PrincipalDerease,@PrincipalIncrease,
            @BackDate,@PostDate,@SkipDayOfTheWeekOnSchedule,@modeOfDisbursement,
            @EnableEarlyRate,@EarlyPaymentDays,@EarlyPaymentRate,@IsUssdMobileEnabled,@ProductType);

    SET @productId = SCOPE_IDENTITY();
END
GO

IF @@TRANCOUNT = 0
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.NewProduct')) NOT LIKE N'%penalty-service/05%'
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('STOPPED: NewProduct did not install. Everything was rolled back.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[UpdateProduct]
    @ID INT,
    @ProductName NVARCHAR(100),
    @ProductDesc NVARCHAR(1000),
    @MinPrincipal DECIMAL(18, 2),
    @MaxPrincipal DECIMAL(18, 2),
    @InterestMethod NVARCHAR(50),
    @InterestType NVARCHAR(50)=null,
    @InterestRate DECIMAL(18, 2),
    @InterestPeriodType NVARCHAR(50),
    @RepaymentPeriodType NVARCHAR(50),
    @RepaymentPeriod INT,
    @RollOverPenalty DECIMAL(18, 2),
    @RollOverGracePeriodType NVARCHAR(50)=null,
    @RollOverGracePeriod INT=null,
    @RollOverApplication INT=NULL,
    @RollOverValueType NVARCHAR(50)=null,
    @RollOverValue DECIMAL(18, 2)=null,
    @RollOverOn NVARCHAR(50)=null,
    @RollOverType NVARCHAR(50)=null,
    @RollOverPeriod INT=null,
    @RollOverPeriodType INT=null,
    @RollOverLimitType INT=Null,
    @RollOverLimit DECIMAL(18, 2)=null,
    @RolloverJlAccount INT=NULL,     -- penalty-service/05: sent by the current portal build
    @newLoanStatus int,
    @newDrtFndLimit DECIMAL(18, 2)=null,
    @repeatLoanStatus int,
    @repeatDrtFndLimit DECIMAL(18, 2)=null,
    @WorkflowId Int=null,
    @repeatWorkflowId Int=null,
    @guarantorRequired Int=null,
    @guarantorReborrow Int=null,
    @securityRequired Int=null,
    @securityDetails Int=null,
    @securityValueColumn Int=null,
    @securityLimitType Int=null,
    @securityLimitValue DECIMAL(18, 2)=null,
    @minLoanLimit DECIMAL(18, 2)=null,
    @MinCreditScore DECIMAL(18, 2)=null,
    @attachments NVARCHAR(MAX)=null,
    @additionalFields NVARCHAR(MAX)=null,
    @EntityId int,
    @EntityUnitsList NVARCHAR(MAX)=null,
    @isActive int,
    @UpdatedBy int,
    @ProductCategory INT=null,
    @PrincipalType INT=null,
    @PrincipalReference INT=null,
    @PrincipalCalculation INT=null,
    @ProductDetailsId INT=null,
    @ProductDetailsValueId INT=null,
    @DepositValueId INT=null,
    @PrincipalDerease INT=null,
    @PrincipalIncrease INT=null,
    @BackDate INT=null,
    @PostDate INT=null,
    @SkipDayOfTheWeekOnSchedule INT=null,
    @modeOfDisbursement int=3,
    @EnableEarlyRate INT=0,
    @EarlyPaymentDays INT=null,
    @EarlyPaymentRate DECIMAL(18,2)=null,
    @IsUssdMobileEnabled BIT=1,
    @ProductType INT=0,
    @productId int OUTPUT
AS
BEGIN
    UPDATE [dbo].[Products] SET
         [ProductName]                = @ProductName
        ,[ProductDesc]                = @ProductDesc
        ,[MinPrincipal]               = @MinPrincipal
        ,[MaxPrincipal]               = @MaxPrincipal
        ,[InterestMethod]             = @InterestMethod
        ,[InterestType]               = @InterestType
        ,[InterestRate]               = @InterestRate
        ,[InterestPeriodType]         = @InterestPeriodType
        ,[RepaymentPeriod]            = @RepaymentPeriod
        ,[RepaymentPeriodType]        = @RepaymentPeriodType
        ,[RollOverPenalty]            = @RollOverPenalty
        ,[RollOverGracePeriod]        = @RollOverGracePeriod
        ,[RollOverGracePeriodType]    = @RollOverGracePeriodType
        -- penalty-service/05: a save that does not carry these must not erase them.
        -- A NULL here is how 4 WEEKS (June) and 8 WEEKS (25 Aug) silently stopped penalising.
        ,[RollOverApplication]        = COALESCE(@RollOverApplication, [RollOverApplication])
        ,[RolloverJlAccount]          = COALESCE(@RolloverJlAccount, [RolloverJlAccount])
        ,[RollOverOn]                 = @RollOverOn
        ,[RollOverValueType]          = @RollOverValueType
        ,[RollOverValue]              = @RollOverValue
        ,[RollOverType]               = @RollOverType
        ,[RollOverPeriod]             = @RollOverPeriod
        ,[RollOverPeriodType]         = @RollOverPeriodType
        ,[RollOverLimitType]          = @RollOverLimitType
        ,[RollOverLimit]              = @RollOverLimit
        ,[newLoanStatus]              = @newLoanStatus
        ,[newDrtFndLimit]             = @newDrtFndLimit
        ,[repeatLoanStatus]           = @repeatLoanStatus
        ,[repeatDrtFndLimit]          = @repeatDrtFndLimit
        ,[WorkflowId]                 = @WorkflowId
        ,[Attachments]                = @Attachments
        ,[AdditionalFields]           = @AdditionalFields
        ,[IsActive]                   = @IsActive
        ,[EntityId]                   = @EntityId
        ,[EntityUnits]                = @EntityUnitsList
        ,[UpdatedBy]                  = @UpdatedBy
        ,[UpdatedDate]                = GETDATE()
        ,[repeatWorkflowId]           = @repeatWorkflowId
        ,[guarantorRequired]          = @guarantorRequired
        ,[guarantorReborrow]          = @guarantorReborrow
        ,[securityRequired]           = @securityRequired
        ,[securityDetails]            = @securityDetails
        ,[securityValueColumn]        = @securityValueColumn
        ,[securityLimitType]          = @securityLimitType
        ,[securityLimitValue]         = @securityLimitValue
        ,[minLoanLimit]               = @minLoanLimit
        ,[MinCreditScore]             = @MinCreditScore
        ,[DisbursmentMode]            = @modeOfDisbursement
        ,[ProductCategory]            = @ProductCategory
        ,[PrincipalType]              = @PrincipalType
        ,[PrincipalReference]         = @PrincipalReference
        ,[PrincipalCalculation]       = @PrincipalCalculation
        ,[ProductDetailsId]           = @ProductDetailsId
        ,[ProductDetailsValueId]      = @ProductDetailsValueId
        ,[DepositValueId]             = @DepositValueId
        ,[PrincipalDerease]           = @PrincipalDerease
        ,[PrincipalIncrease]          = @PrincipalIncrease
        ,[BackDate]                   = @BackDate
        ,[PostDate]                   = @PostDate
        ,[SkipDayOfTheWeekOnSchedule] = @SkipDayOfTheWeekOnSchedule
        ,[EnableEarlyRate]            = @EnableEarlyRate
        ,[EarlyPaymentDays]           = @EarlyPaymentDays
        ,[EarlyPaymentRate]           = @EarlyPaymentRate
        ,[IsUssdMobileEnabled]        = @IsUssdMobileEnabled
        ,[ProductType]                = @ProductType
    WHERE ID = @ID;

    SET @productId = @ID;
END
GO

IF @@TRANCOUNT = 0
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.UpdateProduct')) NOT LIKE N'%penalty-service/05%'
BEGIN
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    RAISERROR('STOPPED: UpdateProduct did not install. Everything was rolled back.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* -- proof: a save that omits the option keeps it ------------------------- */
DECLARE @probe INT = (SELECT TOP 1 ID FROM dbo.Products WHERE EntityId = 3002 AND RollOverApplication = 1 AND RollOverPenalty = 1 ORDER BY ID);
DECLARE @before TABLE (App INT, JL INT, StartD DATE, Name NVARCHAR(200));
INSERT @before SELECT RollOverApplication, RolloverJlAccount, RollOverStartDate, ProductName FROM dbo.Products WHERE ID = @probe;

-- DRY RUN ONLY: re-save one product the way the broken screen did, without the
-- option or the account, then prove both survived. The probe passes NULL for
-- most other fields too, which is why it only ever runs inside the transaction
-- that is about to be rolled back.
DECLARE @out INT, @u INT;
SELECT @u = ISNULL(UpdatedBy, CreatedBy) FROM dbo.Products WHERE ID = @probe;

IF CAST(SESSION_CONTEXT(N'penalty.dryrun') AS BIT) = 1
BEGIN
    DECLARE @n NVARCHAR(100), @d NVARCHAR(1000), @mi DECIMAL(18,2), @ma DECIMAL(18,2), @im NVARCHAR(50), @it NVARCHAR(50),
            @ir DECIMAL(18,2), @ipt NVARCHAR(50), @rpt NVARCHAR(50), @rp INT, @pen DECIMAL(18,2), @nls INT, @rls INT, @ent INT, @act INT;
    SELECT @n = ProductName, @d = ProductDesc, @mi = MinPrincipal, @ma = MaxPrincipal, @im = InterestMethod, @it = InterestType,
           @ir = InterestRate, @ipt = InterestPeriodType, @rpt = RepaymentPeriodType, @rp = RepaymentPeriod, @pen = RollOverPenalty,
           @nls = newLoanStatus, @rls = repeatLoanStatus, @ent = EntityId, @act = IsActive
    FROM dbo.Products WHERE ID = @probe;

    EXEC dbo.UpdateProduct @ID = @probe, @ProductName = @n, @ProductDesc = @d, @MinPrincipal = @mi, @MaxPrincipal = @ma,
         @InterestMethod = @im, @InterestType = @it, @InterestRate = @ir, @InterestPeriodType = @ipt,
         @RepaymentPeriodType = @rpt, @RepaymentPeriod = @rp, @RollOverPenalty = @pen,
         @newLoanStatus = @nls, @repeatLoanStatus = @rls, @EntityId = @ent, @isActive = @act, @UpdatedBy = @u, @productId = @out OUTPUT;

    SELECT 'dry-run probe on product ' + CAST(@probe AS VARCHAR(10)) AS check_,
           b.App AS option_before, P.RollOverApplication AS option_after_save_without_it,
           b.JL AS account_before, P.RolloverJlAccount AS account_after,
           b.StartD AS start_before, P.RollOverStartDate AS start_after,
           CASE WHEN P.RollOverApplication = b.App AND ISNULL(P.RolloverJlAccount, -1) = ISNULL(b.JL, -1)
                     AND ISNULL(P.RollOverStartDate, '19000101') = ISNULL(b.StartD, '19000101')
                THEN 'PASS - kept' ELSE 'FAIL' END AS result_
    FROM dbo.Products P CROSS JOIN @before b WHERE P.ID = @probe;
END;

IF CAST(SESSION_CONTEXT(N'penalty.dryrun') AS BIT) = 1
BEGIN
    ROLLBACK TRANSACTION;
    PRINT 'DRY RUN complete: both procedures compiled, the probe save ran, and everything was ROLLED BACK. Nothing changed.';
END
ELSE
BEGIN
    COMMIT TRANSACTION;
    PRINT 'INSTALLED. Originals are in dbo.MicroEazyProcBackup.';
END;
GO
SET NOEXEC OFF;
GO
