/* ============================================================================
   02 · RESTAMP THE ORPHANED CHILD ROWS  --  ~3,518,382 rows

   The August migration moved Borrowers.EntityId and Loans.EntityId and stopped.
   Every child table that carries its own EntityId still says 3002. That -- and
   nothing else -- is why Micromart Africa's reports still contain fintech
   customers. Restamp the rows and the reports separate with no report change.

   -- HOW THIS IS SAFE ON A LIVE BOOK ---------------------------------------
   These tables are HEAPS with no usable index (verified 8 Sep 2026: Journals,
   CustomerStatement and loanSchedule have no indexes at all). A batched update
   with no index would rescan the whole heap on every batch, so each table gets
   a temporary NONCLUSTERED index on its identity column, built WITH (ONLINE=ON)
   -- this server is Enterprise -- and dropped again at the end.

   Work is committed per batch of 5,000, so there is no long transaction and no
   lock escalation onto a table the app is reading. Interrupting the script is
   safe: re-running resumes, because the driver tables persist and every update
   filters on EntityId <> 3005.

   -- REVERSIBILITY ---------------------------------------------------------
   Each driver table holds RowId + the ORIGINAL EntityId. ROLLBACK.sql replays
   them. DO NOT DROP the FintechRestamp_* tables until you are satisfied.

   RUN ORDER: smallest table first, so a problem surfaces cheaply.
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @batch INT = 5000, @n INT, @total BIGINT;

/* -------------------------------------------------------------------------
   2.1 · loanChargesSchedule   (link: Loanid -> Loans.id)   expect 1,075
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FintechRestamp_loanChargesSchedule_20260908') IS NULL
BEGIN
    SELECT x.id AS RowId, x.EntityId AS OldEntityId
    INTO dbo.FintechRestamp_loanChargesSchedule_20260908
    FROM dbo.loanChargesSchedule x JOIN dbo.Loans l ON l.id = x.Loanid
    WHERE l.EntityId = 3005 AND x.EntityId <> 3005;
    ALTER TABLE dbo.FintechRestamp_loanChargesSchedule_20260908 ALTER COLUMN RowId INT NOT NULL;
    ALTER TABLE dbo.FintechRestamp_loanChargesSchedule_20260908 ADD CONSTRAINT PK_FR_lcs PRIMARY KEY CLUSTERED (RowId);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tmp_lcs_id' AND object_id = OBJECT_ID('dbo.loanChargesSchedule'))
    CREATE NONCLUSTERED INDEX IX_tmp_lcs_id ON dbo.loanChargesSchedule(id) WITH (ONLINE = ON);
SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = 3005
    FROM dbo.loanChargesSchedule x
    JOIN dbo.FintechRestamp_loanChargesSchedule_20260908 d ON d.RowId = x.id
    WHERE x.EntityId <> 3005;
    SET @n = @@ROWCOUNT; SET @total = @total + @n;
    IF @n = 0 BREAK;
    WAITFOR DELAY '00:00:00.050';
END
DROP INDEX IX_tmp_lcs_id ON dbo.loanChargesSchedule;
PRINT '2.1 loanChargesSchedule restamped: ' + CAST(@total AS VARCHAR(20));

/* -------------------------------------------------------------------------
   2.2 · ManagedLoans   (link: LoanId -> Loans.id)   expect 1,144
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FintechRestamp_ManagedLoans_20260908') IS NULL
BEGIN
    SELECT x.ID AS RowId, x.EntityId AS OldEntityId
    INTO dbo.FintechRestamp_ManagedLoans_20260908
    FROM dbo.ManagedLoans x JOIN dbo.Loans l ON l.id = x.LoanId
    WHERE l.EntityId = 3005 AND x.EntityId <> 3005;
    ALTER TABLE dbo.FintechRestamp_ManagedLoans_20260908 ALTER COLUMN RowId INT NOT NULL;
    ALTER TABLE dbo.FintechRestamp_ManagedLoans_20260908 ADD CONSTRAINT PK_FR_ml PRIMARY KEY CLUSTERED (RowId);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tmp_ml_id' AND object_id = OBJECT_ID('dbo.ManagedLoans'))
    CREATE NONCLUSTERED INDEX IX_tmp_ml_id ON dbo.ManagedLoans(ID) WITH (ONLINE = ON);
SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = 3005
    FROM dbo.ManagedLoans x
    JOIN dbo.FintechRestamp_ManagedLoans_20260908 d ON d.RowId = x.ID
    WHERE x.EntityId <> 3005;
    SET @n = @@ROWCOUNT; SET @total = @total + @n;
    IF @n = 0 BREAK;
    WAITFOR DELAY '00:00:00.050';
END
DROP INDEX IX_tmp_ml_id ON dbo.ManagedLoans;
PRINT '2.2 ManagedLoans restamped: ' + CAST(@total AS VARCHAR(20));

/* -------------------------------------------------------------------------
   2.3 · STKPaymentRequests   (link: BorrowerId)   expect 22
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FintechRestamp_STKPaymentRequests_20260908') IS NULL
BEGIN
    SELECT x.ID AS RowId, x.EntityId AS OldEntityId
    INTO dbo.FintechRestamp_STKPaymentRequests_20260908
    FROM dbo.STKPaymentRequests x JOIN dbo.Borrowers b ON b.ID = x.BorrowerId
    WHERE b.EntityId = 3005 AND x.EntityId <> 3005;
    ALTER TABLE dbo.FintechRestamp_STKPaymentRequests_20260908 ALTER COLUMN RowId INT NOT NULL;
    ALTER TABLE dbo.FintechRestamp_STKPaymentRequests_20260908 ADD CONSTRAINT PK_FR_stk PRIMARY KEY CLUSTERED (RowId);
END
UPDATE x SET x.EntityId = 3005
FROM dbo.STKPaymentRequests x
JOIN dbo.FintechRestamp_STKPaymentRequests_20260908 d ON d.RowId = x.ID
WHERE x.EntityId <> 3005;
PRINT '2.3 STKPaymentRequests restamped: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

/* -------------------------------------------------------------------------
   2.4 · loanSchedule   (link: Loanid -> Loans.id)   expect 298,228
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FintechRestamp_loanSchedule_20260908') IS NULL
BEGIN
    SELECT x.id AS RowId, x.EntityId AS OldEntityId
    INTO dbo.FintechRestamp_loanSchedule_20260908
    FROM dbo.loanSchedule x JOIN dbo.Loans l ON l.id = x.Loanid
    WHERE l.EntityId = 3005 AND x.EntityId <> 3005;
    ALTER TABLE dbo.FintechRestamp_loanSchedule_20260908 ALTER COLUMN RowId INT NOT NULL;
    ALTER TABLE dbo.FintechRestamp_loanSchedule_20260908 ADD CONSTRAINT PK_FR_ls PRIMARY KEY CLUSTERED (RowId);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tmp_ls_id' AND object_id = OBJECT_ID('dbo.loanSchedule'))
    CREATE NONCLUSTERED INDEX IX_tmp_ls_id ON dbo.loanSchedule(id) WITH (ONLINE = ON);
SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = 3005
    FROM dbo.loanSchedule x
    JOIN dbo.FintechRestamp_loanSchedule_20260908 d ON d.RowId = x.id
    WHERE x.EntityId <> 3005;
    SET @n = @@ROWCOUNT; SET @total = @total + @n;
    IF @n = 0 BREAK;
    WAITFOR DELAY '00:00:00.050';
END
DROP INDEX IX_tmp_ls_id ON dbo.loanSchedule;
PRINT '2.4 loanSchedule restamped: ' + CAST(@total AS VARCHAR(20));

/* -------------------------------------------------------------------------
   2.5 · CustomerStatement   (link: LoanId -> Loans.id)   expect 603,408
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FintechRestamp_CustomerStatement_20260908') IS NULL
BEGIN
    SELECT x.id AS RowId, x.EntityId AS OldEntityId
    INTO dbo.FintechRestamp_CustomerStatement_20260908
    FROM dbo.CustomerStatement x JOIN dbo.Loans l ON l.id = x.LoanId
    WHERE l.EntityId = 3005 AND x.EntityId <> 3005;
    ALTER TABLE dbo.FintechRestamp_CustomerStatement_20260908 ALTER COLUMN RowId INT NOT NULL;
    ALTER TABLE dbo.FintechRestamp_CustomerStatement_20260908 ADD CONSTRAINT PK_FR_cs PRIMARY KEY CLUSTERED (RowId);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tmp_cs_id' AND object_id = OBJECT_ID('dbo.CustomerStatement'))
    CREATE NONCLUSTERED INDEX IX_tmp_cs_id ON dbo.CustomerStatement(id) WITH (ONLINE = ON);
SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = 3005
    FROM dbo.CustomerStatement x
    JOIN dbo.FintechRestamp_CustomerStatement_20260908 d ON d.RowId = x.id
    WHERE x.EntityId <> 3005;
    SET @n = @@ROWCOUNT; SET @total = @total + @n;
    IF @n = 0 BREAK;
    WAITFOR DELAY '00:00:00.050';
END
DROP INDEX IX_tmp_cs_id ON dbo.CustomerStatement;
PRINT '2.5 CustomerStatement restamped: ' + CAST(@total AS VARCHAR(20));

/* -------------------------------------------------------------------------
   2.6 · LoanGraduationHistory   (link: BorrowerId)   expect 1,211,692
   This table already has a clustered PK on Id, so it needs no helper index.
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FintechRestamp_LoanGraduationHistory_20260908') IS NULL
BEGIN
    SELECT x.Id AS RowId, x.EntityId AS OldEntityId
    INTO dbo.FintechRestamp_LoanGraduationHistory_20260908
    FROM dbo.LoanGraduationHistory x JOIN dbo.Borrowers b ON b.ID = x.BorrowerId
    WHERE b.EntityId = 3005 AND x.EntityId <> 3005;
    ALTER TABLE dbo.FintechRestamp_LoanGraduationHistory_20260908 ALTER COLUMN RowId INT NOT NULL;
    ALTER TABLE dbo.FintechRestamp_LoanGraduationHistory_20260908 ADD CONSTRAINT PK_FR_lgh PRIMARY KEY CLUSTERED (RowId);
END
SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = 3005
    FROM dbo.LoanGraduationHistory x
    JOIN dbo.FintechRestamp_LoanGraduationHistory_20260908 d ON d.RowId = x.Id
    WHERE x.EntityId <> 3005;
    SET @n = @@ROWCOUNT; SET @total = @total + @n;
    IF @n = 0 BREAK;
    WAITFOR DELAY '00:00:00.050';
END
PRINT '2.6 LoanGraduationHistory restamped: ' + CAST(@total AS VARCHAR(20));

/* -------------------------------------------------------------------------
   2.7 · Journals   (link: BorrowerId)   expect 1,402,813

   Journals is the only child table carrying BOTH a BorrowerId and a LoanId. It
   is driven off the BORROWER, because 289,267 of these rows carry no 3005 loan
   at all -- registration fees and other non-loan postings that still belong to
   the customer. One row (verified) points at a 3005 borrower but a loan that is
   NOT on 3005; it is EXCLUDED and reported below, because moving it would
   silently contradict its own loan. Inspect that one by hand.
   ---------------------------------------------------------------------- */
IF OBJECT_ID('dbo.FintechRestamp_Journals_20260908') IS NULL
BEGIN
    SELECT x.Id AS RowId, x.EntityId AS OldEntityId
    INTO dbo.FintechRestamp_Journals_20260908
    FROM dbo.Journals x
    JOIN dbo.Borrowers b ON b.ID = x.BorrowerId
    LEFT JOIN dbo.Loans l ON l.id = x.LoanId
    WHERE b.EntityId = 3005 AND x.EntityId <> 3005
      AND (l.id IS NULL OR l.EntityId = 3005);
    ALTER TABLE dbo.FintechRestamp_Journals_20260908 ALTER COLUMN RowId INT NOT NULL;
    ALTER TABLE dbo.FintechRestamp_Journals_20260908 ADD CONSTRAINT PK_FR_j PRIMARY KEY CLUSTERED (RowId);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tmp_j_id' AND object_id = OBJECT_ID('dbo.Journals'))
    CREATE NONCLUSTERED INDEX IX_tmp_j_id ON dbo.Journals(Id) WITH (ONLINE = ON);
SET @total = 0;
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) x SET x.EntityId = 3005
    FROM dbo.Journals x
    JOIN dbo.FintechRestamp_Journals_20260908 d ON d.RowId = x.Id
    WHERE x.EntityId <> 3005;
    SET @n = @@ROWCOUNT; SET @total = @total + @n;
    IF @n = 0 BREAK;
    WAITFOR DELAY '00:00:00.050';
END
DROP INDEX IX_tmp_j_id ON dbo.Journals;
PRINT '2.7 Journals restamped: ' + CAST(@total AS VARCHAR(20));

/* -- the excluded conflict rows, for inspection -- */
SELECT 'JOURNALS CONFLICT -- inspect by hand' AS note,
       x.Id, x.BorrowerId, x.LoanId, x.EntityId AS JournalEntity, l.EntityId AS LoanEntity
FROM dbo.Journals x
JOIN dbo.Borrowers b ON b.ID = x.BorrowerId
JOIN dbo.Loans l ON l.id = x.LoanId
WHERE b.EntityId = 3005 AND l.EntityId <> 3005;

/* -------------------------------------------------------------------------
   VERIFY -- every still_wrong below must be 0.
   ---------------------------------------------------------------------- */
SELECT 'loanSchedule' AS tbl, COUNT(*) AS still_wrong
  FROM dbo.loanSchedule x JOIN dbo.Loans l ON l.id = x.Loanid
  WHERE l.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'loanChargesSchedule', COUNT(*)
  FROM dbo.loanChargesSchedule x JOIN dbo.Loans l ON l.id = x.Loanid
  WHERE l.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'CustomerStatement', COUNT(*)
  FROM dbo.CustomerStatement x JOIN dbo.Loans l ON l.id = x.LoanId
  WHERE l.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'ManagedLoans', COUNT(*)
  FROM dbo.ManagedLoans x JOIN dbo.Loans l ON l.id = x.LoanId
  WHERE l.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'LoanGraduationHistory', COUNT(*)
  FROM dbo.LoanGraduationHistory x JOIN dbo.Borrowers b ON b.ID = x.BorrowerId
  WHERE b.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'STKPaymentRequests', COUNT(*)
  FROM dbo.STKPaymentRequests x JOIN dbo.Borrowers b ON b.ID = x.BorrowerId
  WHERE b.EntityId = 3005 AND x.EntityId <> 3005;

PRINT '02 complete. Reports will now separate on entity.';
