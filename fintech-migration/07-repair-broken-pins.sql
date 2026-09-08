/* ============================================================================
   07 · REPAIR THE 40 TRUNCATED USSD PIN HASHES

   -- WHAT IS WRONG -----------------------------------------------------------
   Borrowers.UssdPin holds a BCrypt hash, which is always 60 characters. Read on
   8 September 2026 across the whole table:

       $2b$  60 chars   12,941 borrowers   valid
       $2a$  60 chars    2,528 borrowers   valid
       $2a$  50 chars       40 borrowers   TRUNCATED

   -- WHY IT MATTERS ----------------------------------------------------------
   ATusersUssdApI/Models/Login.cs calls BCrypt.Verify against whatever is in the
   column. On a 50-character value BCrypt.Net raises SaltParseException.
   ServiceController.cs has no global exception handler, so the throw becomes an
   HTTP 500, and Africa's Talking shows the subscriber its own generic
   "we are experiencing technical problems" text.

   Those 40 customers therefore cannot dial in at all, and the message they get
   blames the service rather than telling them their PIN needs resetting.

   -- THE FIX ----------------------------------------------------------------
   Set the broken value to NULL. A NULL or empty UssdPin is already a supported
   state: Login.UssdPinStatus returns 2 ("no PIN set") and ServiceController
   routes the customer into HandlePinSetup, which asks them to choose a new PIN
   on the spot. So this turns a dead end into the existing self-service flow --
   no SMS to send, no reset to schedule.

   This does NOT excuse leaving the exception handler missing. Wrap the handler
   as well, so the next unexpected throw is a message the customer can act on.

   Rows touched: 40.  Reversible: yes, the old values are recorded.
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.FintechRemediationBackup_20260908') IS NULL
BEGIN RAISERROR('Run 01-fix-destination.sql first -- the backup table is missing.', 16, 1); RETURN; END

/* -- who they are, before -- */
SELECT 'before' AS stage, ID, firstName, otherName, PhoneNumber, EntityId,
       LEN(UssdPin) AS pin_len, LEFT(UssdPin, 4) AS pin_prefix
FROM dbo.Borrowers
WHERE NULLIF(UssdPin, '') IS NOT NULL AND LEN(UssdPin) <> 60
ORDER BY EntityId, ID;

BEGIN TRANSACTION;

    INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
    SELECT '07-pins', 'Borrowers', ID, 'UssdPin', UssdPin, NULL
    FROM dbo.Borrowers
    WHERE NULLIF(UssdPin, '') IS NOT NULL AND LEN(UssdPin) <> 60;

    UPDATE dbo.Borrowers
       SET UssdPin = NULL, UpdatedBy = 9096, UpdatedDate = GETDATE()
     WHERE NULLIF(UssdPin, '') IS NOT NULL AND LEN(UssdPin) <> 60;

    PRINT 'Cleared ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' unusable PIN hashes (expected 40).';

COMMIT TRANSACTION;

/* -- verify: only 60-character hashes should remain -- */
SELECT 'after' AS stage, LEN(UssdPin) AS pin_len, LEFT(UssdPin, 4) AS pin_prefix, COUNT(*) AS n
FROM dbo.Borrowers WHERE NULLIF(UssdPin, '') IS NOT NULL
GROUP BY LEN(UssdPin), LEFT(UssdPin, 4) ORDER BY n DESC;

PRINT '07 complete. Those customers will be asked to set a PIN on their next dial.';
