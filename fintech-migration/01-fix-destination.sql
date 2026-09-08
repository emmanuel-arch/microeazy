/* ============================================================================
   01 · FIX THE DESTINATION — before anything is parked on it.

   Geoffrey Njane (9098) is the intended owner of every fintech customer, but
   his account is DISABLED (UserStatus = 0), and both he and Emmanuel Birgen
   (9096) sit in OrganizationUnit 1 -- which is entity 3002's "Head Office",
   not entity 3005's "Main Office" (129). Parking 17,022 customers under a
   disabled user in another entity's branch would hide the problem, not fix it.

   Rows touched: 2.  Reversible: yes (values recorded in the backup table).
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.FintechRemediationBackup_20260908') IS NULL
BEGIN
    CREATE TABLE dbo.FintechRemediationBackup_20260908 (
        BackupId    BIGINT IDENTITY(1,1) PRIMARY KEY,
        Phase       VARCHAR(40)    NOT NULL,
        TableName   SYSNAME        NOT NULL,
        KeyValue    BIGINT         NOT NULL,
        ColumnName  SYSNAME        NOT NULL,
        OldValue    NVARCHAR(200)  NULL,
        NewValue    NVARCHAR(200)  NULL,
        CapturedAt  DATETIME2      NOT NULL CONSTRAINT DF_FRB_CapturedAt DEFAULT SYSDATETIME()
    );
    PRINT 'Created dbo.FintechRemediationBackup_20260908';
END

BEGIN TRANSACTION;

    /* -- record before -- */
    INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
    SELECT '01-destination', 'UserMaster', ID, 'UserStatus',
           CAST(UserStatus AS NVARCHAR(200)), N'1'
    FROM dbo.UserMaster WHERE ID = 9098 AND ISNULL(UserStatus, 0) <> 1;

    INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
    SELECT '01-destination', 'UserMaster', ID, 'OrganizationUnit',
           CAST(OrganizationUnit AS NVARCHAR(200)), N'129'
    FROM dbo.UserMaster WHERE ID IN (9096, 9098) AND ISNULL(OrganizationUnit, 0) <> 129;

    /* -- apply -- */
    UPDATE dbo.UserMaster SET UserStatus = 1        WHERE ID = 9098;
    UPDATE dbo.UserMaster SET OrganizationUnit = 129 WHERE ID IN (9096, 9098);

    /* -- assert: Main Office really is 3005's branch, and the only one -- */
    IF NOT EXISTS (SELECT 1 FROM dbo.OrganizationUnits WHERE UnitId = 129 AND OrganizationId = 3005)
    BEGIN
        RAISERROR('Unit 129 is not a branch of entity 3005. Aborting.', 16, 1);
        ROLLBACK TRANSACTION; RETURN;
    END

COMMIT TRANSACTION;

SELECT ID, Username, FirstName, OtherName, EntityID, OrganizationUnit, UserStatus
FROM dbo.UserMaster WHERE ID IN (9096, 9098);
PRINT '01 complete. Geoffrey enabled, both users in Main Office (129).';
