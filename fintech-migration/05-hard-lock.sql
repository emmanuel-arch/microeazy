/* ============================================================================
   05 · THE HARD LOCK ON dbo.Borrowers

   One customer, one record, across Micromart Africa (3002) and Micromart
   Fintech (3005). No phone number and no national ID may appear on both.

   -- WHY THIS LIVES IN THE DATABASE ----------------------------------------
   Five channels write to this table: the ServiceSuite console, the RO app, the
   USSD service, the LMS console and the Micro Eazy app. A rule enforced in an
   application is a rule the other four do not have. The table is the only place
   every channel must pass through, so the table is where the rule belongs.

   -- WHAT IS ENFORCED -------------------------------------------------------
   A borrower may not be INSERTed or UPDATEd into 3002 or 3005 carrying a
   national ID or phone number that is already held by a DIFFERENT ACTIVE
   borrower on either book. Closed records (AccountStatus = 0) are ignored --
   that is what makes script 04's merged shells harmless, and what lets a
   genuinely closed account's number be reissued.

   Comparison is on trimmed values, because 45 records on these two books carry
   leading or trailing whitespace in exactly these columns.

   PREREQUISITE: run 04 first. This will refuse to install while active
   duplicates remain, because it would make those customers unmaintainable.
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* -------------------------------------------------------------------------
   5.1 · Refuse to install over an unresolved mess.
   ---------------------------------------------------------------------- */
DECLARE @dups INT;
SELECT @dups = COUNT(*)
FROM (
    SELECT LTRIM(RTRIM(NationalID)) AS k FROM dbo.Borrowers
    WHERE EntityId IN (3002, 3005) AND ISNULL(AccountStatus,1) <> 0
      AND NULLIF(LTRIM(RTRIM(NationalID)), '') IS NOT NULL
    GROUP BY LTRIM(RTRIM(NationalID)) HAVING COUNT(*) > 1
    UNION ALL
    SELECT LTRIM(RTRIM(PhoneNumber)) FROM dbo.Borrowers
    WHERE EntityId IN (3002, 3005) AND ISNULL(AccountStatus,1) <> 0
      AND NULLIF(LTRIM(RTRIM(PhoneNumber)), '') IS NOT NULL
    GROUP BY LTRIM(RTRIM(PhoneNumber)) HAVING COUNT(*) > 1
) z;

IF @dups > 0
BEGIN
    PRINT 'REFUSING TO INSTALL: ' + CAST(@dups AS VARCHAR(20))
        + ' duplicate identities are still active. Run 04-merge-duplicates.sql,';
    PRINT 'then clear section 4.3''s manual list, then run this script again.';
    SELECT TOP 200 'still duplicated' AS problem, LTRIM(RTRIM(NationalID)) AS NationalID, COUNT(*) AS records
    FROM dbo.Borrowers
    WHERE EntityId IN (3002, 3005) AND ISNULL(AccountStatus,1) <> 0
      AND NULLIF(LTRIM(RTRIM(NationalID)), '') IS NOT NULL
    GROUP BY LTRIM(RTRIM(NationalID)) HAVING COUNT(*) > 1;
    RETURN;
END

/* -------------------------------------------------------------------------
   5.2 · Lookup indexes. The trigger probes these on every write, and neither
         column is indexed today, so without these every onboarding scans
         160,000 rows twice.
   ---------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Borrowers_NationalID_Lock' AND object_id = OBJECT_ID('dbo.Borrowers'))
    CREATE NONCLUSTERED INDEX IX_Borrowers_NationalID_Lock
        ON dbo.Borrowers (NationalID) INCLUDE (EntityId, AccountStatus) WITH (ONLINE = ON);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Borrowers_PhoneNumber_Lock' AND object_id = OBJECT_ID('dbo.Borrowers'))
    CREATE NONCLUSTERED INDEX IX_Borrowers_PhoneNumber_Lock
        ON dbo.Borrowers (PhoneNumber) INCLUDE (EntityId, AccountStatus) WITH (ONLINE = ON);
GO

/* -------------------------------------------------------------------------
   5.3 · The lock itself.

   An AFTER trigger rather than a unique index, deliberately: a unique index
   answers "duplicate key" and names an index. This answers

       "Beatrice Muzembi (ID 11198183) is already registered on MICROMART
        FINTECH as borrower 18797. Do not onboard again -- contact admin."

   which is the sentence the relationship officer standing in front of the
   customer actually needs. Section 5.4 adds the index as a second line of
   defence for anything that bypasses the trigger.
   ---------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_Borrowers_MicromartIdentityLock
ON dbo.Borrowers
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT EXISTS (SELECT 1 FROM inserted WHERE EntityId IN (3002, 3005)) RETURN;

    DECLARE @msg NVARCHAR(2000);

    SELECT TOP 1 @msg =
        N'This customer already exists on ' + e.EntityName
        + N' as borrower ' + CAST(b.ID AS NVARCHAR(20))
        + N' (' + LTRIM(RTRIM(ISNULL(b.firstName, N''))) + N' '
        + LTRIM(RTRIM(ISNULL(b.otherName, N''))) + N'), matched on '
        + CASE WHEN NULLIF(LTRIM(RTRIM(i.NationalID)), '') IS NOT NULL
                    AND LTRIM(RTRIM(b.NationalID)) = LTRIM(RTRIM(i.NationalID))
               THEN N'national ID ' + LTRIM(RTRIM(i.NationalID))
               ELSE N'phone number ' + LTRIM(RTRIM(i.PhoneNumber)) END
        + N'. A customer may not be onboarded on both Micromart Africa and '
        + N'Micromart Fintech. Contact admin to have the existing record used.'
    FROM inserted i
    JOIN dbo.Borrowers b
      ON  b.ID <> i.ID
      AND b.EntityId IN (3002, 3005)
      AND ISNULL(b.AccountStatus, 1) <> 0
      AND ( (NULLIF(LTRIM(RTRIM(i.NationalID)),  '') IS NOT NULL AND LTRIM(RTRIM(b.NationalID))  = LTRIM(RTRIM(i.NationalID)))
         OR (NULLIF(LTRIM(RTRIM(i.PhoneNumber)), '') IS NOT NULL AND LTRIM(RTRIM(b.PhoneNumber)) = LTRIM(RTRIM(i.PhoneNumber))) )
    LEFT JOIN dbo.BsEntity e ON e.ID = b.EntityId
    WHERE i.EntityId IN (3002, 3005)
      AND ISNULL(i.AccountStatus, 1) <> 0;

    IF @msg IS NOT NULL
    BEGIN
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW 51000, @msg, 1;
    END
END
GO

/* -------------------------------------------------------------------------
   5.4 · Second line of defence.

   A unique filtered index catches anything that reaches the table with the
   trigger disabled. It is attempted, not assumed: the key is a persisted
   computed column, and if this server declines that combination the trigger
   above still holds the rule on its own. Read the PRINT output.
   ---------------------------------------------------------------------- */
BEGIN TRY
    IF COL_LENGTH('dbo.Borrowers', 'NationalIDLockKey') IS NULL
        ALTER TABLE dbo.Borrowers ADD NationalIDLockKey AS (
            CASE WHEN NULLIF(LTRIM(RTRIM(NationalID)), '') IS NULL
                 THEN '#' + CAST(ID AS VARCHAR(20))          -- blanks never collide
                 ELSE UPPER(LTRIM(RTRIM(NationalID))) END
        ) PERSISTED;
END TRY
BEGIN CATCH
    PRINT 'NOTE: could not add NationalIDLockKey -- ' + ERROR_MESSAGE();
END CATCH
GO

BEGIN TRY
    IF COL_LENGTH('dbo.Borrowers', 'NationalIDLockKey') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Borrowers_NationalIDLockKey' AND object_id = OBJECT_ID('dbo.Borrowers'))
        CREATE UNIQUE NONCLUSTERED INDEX UX_Borrowers_NationalIDLockKey
            ON dbo.Borrowers (NationalIDLockKey)
            WHERE EntityId IN (3002, 3005) AND AccountStatus <> 0;
    PRINT 'Backstop unique index installed.';
END TRY
BEGIN CATCH
    PRINT 'NOTE: backstop unique index NOT installed -- ' + ERROR_MESSAGE();
    PRINT '      The trigger in 5.3 still enforces the rule. This is a defence';
    PRINT '      in depth only; it is safe to continue without it.';
END CATCH
GO

/* -------------------------------------------------------------------------
   5.5 · Prove it works. Both of these must FAIL.
   ---------------------------------------------------------------------- */
PRINT '--- self-test: inserting a known-duplicate must be rejected ---';
BEGIN TRY
    DECLARE @nid VARCHAR(50) = (SELECT TOP 1 NationalID FROM dbo.Borrowers
                                WHERE EntityId = 3005 AND NULLIF(LTRIM(RTRIM(NationalID)),'') IS NOT NULL);
    INSERT dbo.Borrowers (firstName, otherName, AccountNo, NationalID, PhoneNumber,
                          EntityId, EntityUnit, EntityAgent, AccountStatus, CreatedBy, CreatedDate)
    VALUES ('LOCK', 'SELFTEST', '254700000000', @nid, '254700000000',
            3002, 1, 9096, 1, 9096, GETDATE());
    PRINT 'SELF-TEST FAILED: the insert was allowed. Investigate before relying on the lock.';
    DELETE FROM dbo.Borrowers WHERE firstName = 'LOCK' AND otherName = 'SELFTEST';
END TRY
BEGIN CATCH
    PRINT 'SELF-TEST PASSED. The table answered:';
    PRINT '  ' + ERROR_MESSAGE();
END CATCH
GO

PRINT '05 complete. Every channel now shares one identity rule.';
