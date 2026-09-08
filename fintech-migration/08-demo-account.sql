/* ============================================================================
   08 · A DEMO CUSTOMER ON THE FINTECH BOOK

   Creates one borrower on MICROMART FINTECH (3005), in Main Office (129), under
   Emmanuel Birgen (9096) — the console/shelf owner, per the ownership rule in
   script 03 — so you can sign in to the Micro Eazy app, the USSD service and the
   LMS console as a customer and see the fintech shelf.

   -- YOU ALREADY HAVE ONE ----------------------------------------------------
   Borrower 170497 (Emmanuel Birgen, 254758517032, ID 39362808) is already on
   3005 in unit 129. Once the OTP fix ships it signs in to the Micro Eazy app
   with no further work. This script is for a SEPARATE account you can hand to
   someone else, or reset without touching your own.

   -- WHAT YOU MUST SET ------------------------------------------------------
   @DemoPhone must be a handset YOU HOLD. Sign-in sends a real OTP by SMS and
   the USSD flow asks for a PIN on the real handset — a demo account on a number
   nobody answers cannot be signed into by anybody, including you.

   @DemoNationalID must not already exist on 3002 or 3005. The identity lock
   from script 05 will refuse the insert if it does, which is the lock working;
   pick another number rather than disabling it.

   -- CREDENTIALS ------------------------------------------------------------
   None are set, on purpose. BCrypt cannot be computed in T-SQL (see script 10),
   so this leaves UssdPin and MobileAppPassword NULL. The customer dials
   *483*490# once and the USSD service's set-your-PIN screen mints a real hash
   with the code that owns hashing. That PIN then works on both USSD and the app.

   Reversible: yes — the rollback is at the bottom of this file.
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

------------------------------------------------------------------------------
-- SET THESE FOUR, THEN RUN.
------------------------------------------------------------------------------
DECLARE @DemoPhone      VARCHAR(15)  = '2547XXXXXXXX';        -- a handset you hold
DECLARE @DemoNationalID VARCHAR(50)  = '30000001';            -- must be unused on 3002 AND 3005
DECLARE @DemoFirstName  VARCHAR(100) = 'Demo';
DECLARE @DemoOtherName  VARCHAR(100) = 'Customer';
DECLARE @DemoEmail      VARCHAR(200) = NULL;                  -- optional
------------------------------------------------------------------------------

DECLARE @Entity INT = 3005, @Unit INT = 129, @Agent INT = 9096;

IF @DemoPhone LIKE '%X%'
BEGIN
    RAISERROR('Set @DemoPhone to a real handset you control before running this.', 16, 1);
    RETURN;
END

/* -- the destination must exist and be sound -- */
IF NOT EXISTS (SELECT 1 FROM dbo.OrganizationUnits WHERE UnitId = @Unit AND OrganizationId = @Entity)
BEGIN RAISERROR('Unit 129 is not a branch of entity 3005.', 16, 1); RETURN; END

/* -- already there? then nothing to do -- */
IF EXISTS (SELECT 1 FROM dbo.Borrowers
           WHERE EntityId = @Entity
             AND (LTRIM(RTRIM(PhoneNumber)) = @DemoPhone OR LTRIM(RTRIM(NationalID)) = @DemoNationalID))
BEGIN
    PRINT 'A borrower with that phone or ID already exists on 3005 — nothing created.';
    SELECT ID, firstName, otherName, AccountNo, NationalID, PhoneNumber,
           EntityId, EntityUnit, EntityAgent, AccountStatus
    FROM dbo.Borrowers
    WHERE EntityId = @Entity
      AND (LTRIM(RTRIM(PhoneNumber)) = @DemoPhone OR LTRIM(RTRIM(NationalID)) = @DemoNationalID);
    RETURN;
END

/* -- the identity lock will refuse a cross-book duplicate; say so first, in
      words, rather than letting the trigger's message be the explanation -- */
IF EXISTS (SELECT 1 FROM dbo.Borrowers
           WHERE EntityId IN (3002, 3005) AND ISNULL(AccountStatus,1) <> 0
             AND (LTRIM(RTRIM(PhoneNumber)) = @DemoPhone OR LTRIM(RTRIM(NationalID)) = @DemoNationalID))
BEGIN
    PRINT 'That phone or national ID is already registered on Micromart Africa (3002).';
    PRINT 'Pick different values — do not disable the identity lock to get around this.';
    RETURN;
END

BEGIN TRANSACTION;

    INSERT INTO dbo.Borrowers
        (firstName, otherName, AccountNo, NationalID, PhoneNumber, EmailAddress,
         EntityId, EntityUnit, EntityAgent, AccountStatus,
         UssdPin, MobileAppPassword,
         CreatedBy, CreatedDate, IsRegistrationCompleted, Approved, IsROApproved)
    VALUES
        (@DemoFirstName, @DemoOtherName, @DemoPhone, @DemoNationalID, @DemoPhone, @DemoEmail,
         @Entity, @Unit, @Agent, 1,
         NULL, NULL,                    -- set by the customer on their first USSD dial
         @Agent, GETDATE(), 1, 1, 1);

    DECLARE @NewId INT = SCOPE_IDENTITY();

    INSERT INTO dbo.BorrowerComments (borroweId, Comment, CreatedBy, DateCreated)
    VALUES (@NewId, 'Demo account created for Micro Eazy / USSD / LMS console testing on the fintech book.', @Agent, GETDATE());

COMMIT TRANSACTION;

SELECT 'created' AS status, ID, firstName, otherName, AccountNo, NationalID,
       PhoneNumber, EntityId, EntityUnit, EntityAgent, AccountStatus
FROM dbo.Borrowers WHERE ID = @NewId;

PRINT '';
PRINT 'Demo account ready. To use it:';
PRINT '  1. Dial *483*490# from that handset and set a 4-digit PIN when asked.';
PRINT '  2. Micro Eazy app: portal.servicesuitecloud.com -- phone, then the SMS';
PRINT '     code, then the national ID above.';
PRINT '  3. The shelf it will see is products 30219, 30220 and 30221 (unit 129).';

/* ============================================================================
   ROLLBACK -- replace <ID> with the id printed above.
   ============================================================================
DELETE FROM dbo.BorrowerComments WHERE borroweId = <ID>;
DELETE FROM dbo.Borrowers        WHERE ID = <ID> AND EntityId = 3005
                                   AND NOT EXISTS (SELECT 1 FROM dbo.Loans WHERE BorrowerId = <ID>);
============================================================================ */
