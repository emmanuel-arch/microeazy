/* ============================================================================
   00 · PREFLIGHT — READ ONLY. Changes nothing. Run this first, keep the output.

   Every later script asserts against these numbers. If a figure here differs
   materially from the value in the comment beside it, STOP and re-read: the
   book has moved since 8 September 2026 and the plan needs re-checking.

   Target : Serviceconnect on 100.72.35.56,4230   (SQL Server 2022 Enterprise)
   Books  : 3002 Micromart Africa Limited  ->  3005 MICROMART FINTECH
   ==========================================================================*/
SET NOCOUNT ON;
PRINT '=== Preflight @ ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' ===';

/* -- 1. Population -------------------------------------------------------- */
SELECT 'borrowers per entity' AS check_name, EntityId, COUNT(*) AS n
FROM dbo.Borrowers
GROUP BY EntityId
ORDER BY n DESC;
-- expected 2026-09-08: 3002=143558, 3005=17022, 3003=2463, 7=7, 34=1

/* -- 2. The first migration's own record ----------------------------------- */
SELECT 'migration backup' AS check_name, OldEntityId, NewEntityId,
       COUNT(*) AS n, MIN(MigratedDate) AS ran_at
FROM dbo.BorrowerEntityMigrationBackup_20260802
GROUP BY OldEntityId, NewEntityId;
-- expected: 3002 -> 3005, 17016 rows, 2026-08-02 19:43:07

/* -- 3. Orphaned child rows: the report leak, per table -------------------- */
SELECT 'loanSchedule'        AS tbl, COUNT(*) AS rows_stamped_wrong FROM dbo.loanSchedule x        JOIN dbo.Loans l ON l.id = x.Loanid  WHERE l.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'loanChargesSchedule', COUNT(*) FROM dbo.loanChargesSchedule x JOIN dbo.Loans l ON l.id = x.Loanid  WHERE l.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'CustomerStatement',   COUNT(*) FROM dbo.CustomerStatement x   JOIN dbo.Loans l ON l.id = x.LoanId  WHERE l.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'ManagedLoans',        COUNT(*) FROM dbo.ManagedLoans x        JOIN dbo.Loans l ON l.id = x.LoanId  WHERE l.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'Journals',            COUNT(*) FROM dbo.Journals x            JOIN dbo.Borrowers b ON b.ID = x.BorrowerId WHERE b.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'LoanGraduationHistory',COUNT(*) FROM dbo.LoanGraduationHistory x JOIN dbo.Borrowers b ON b.ID = x.BorrowerId WHERE b.EntityId = 3005 AND x.EntityId <> 3005
UNION ALL SELECT 'STKPaymentRequests',  COUNT(*) FROM dbo.STKPaymentRequests x  JOIN dbo.Borrowers b ON b.ID = x.BorrowerId WHERE b.EntityId = 3005 AND x.EntityId <> 3005;
-- expected: 298228 / 1075 / 603408 / 1144 / 1402813 / 1211692 / 22  = 3,518,382

/* -- 4. Where the fintech customers are standing --------------------------- */
SELECT 'fintech posture' AS check_name,
       COUNT(*)                                                  AS total,
       SUM(CASE WHEN EntityUnit  = 129  THEN 1 ELSE 0 END)       AS in_main_office,
       SUM(CASE WHEN EntityUnit <> 129  THEN 1 ELSE 0 END)       AS wrong_unit,
       COUNT(DISTINCT EntityAgent)                               AS distinct_agents,
       SUM(CASE WHEN EntityAgent = 9098 THEN 1 ELSE 0 END)       AS under_geoffrey,
       SUM(CASE WHEN EntityAgent = 9096 THEN 1 ELSE 0 END)       AS under_birgen
FROM dbo.Borrowers WHERE EntityId = 3005;
-- expected: 17022 / 16264 / 758 / 167 / 4 / 1

/* -- 5. The destination itself -------------------------------------------- */
SELECT 'destination users' AS check_name, ID, Username, FirstName, OtherName,
       EntityID, OrganizationUnit, UserStatus
FROM dbo.UserMaster WHERE ID IN (9096, 9098);
-- 9098 Geoffrey MUST end up UserStatus=1, OrganizationUnit=129 (script 01)
-- 9096 Birgen   MUST end up               OrganizationUnit=129

SELECT 'fintech branches' AS check_name, UnitId, UnitTitle, OrganizationId
FROM dbo.OrganizationUnits WHERE OrganizationId = 3005;
-- expected: exactly one row -- 129 'Main Office'

/* -- 6. Duplicate identities across the two books -------------------------- */
SELECT 'dup national ids' AS check_name,
       COUNT(*) AS ids_on_both_books
FROM (SELECT NationalID FROM dbo.Borrowers WHERE EntityId = 3005 AND NULLIF(LTRIM(RTRIM(NationalID)),'') IS NOT NULL
      INTERSECT
      SELECT NationalID FROM dbo.Borrowers WHERE EntityId = 3002 AND NULLIF(LTRIM(RTRIM(NationalID)),'') IS NOT NULL) z;
-- expected: 200

SELECT 'dup phones' AS check_name, COUNT(*) AS phones_on_both_books
FROM (SELECT PhoneNumber FROM dbo.Borrowers WHERE EntityId = 3005 AND NULLIF(LTRIM(RTRIM(PhoneNumber)),'') IS NOT NULL
      INTERSECT
      SELECT PhoneNumber FROM dbo.Borrowers WHERE EntityId = 3002 AND NULLIF(LTRIM(RTRIM(PhoneNumber)),'') IS NOT NULL) z;
-- expected: 52

SELECT 're-onboarded after 2 Aug' AS check_name, COUNT(*) AS n
FROM dbo.Borrowers b
WHERE b.EntityId = 3002 AND b.CreatedDate >= '2026-08-02'
  AND (b.NationalID  IN (SELECT NationalID  FROM dbo.Borrowers WHERE EntityId = 3005 AND NULLIF(LTRIM(RTRIM(NationalID)),'')  IS NOT NULL)
    OR b.PhoneNumber IN (SELECT PhoneNumber FROM dbo.Borrowers WHERE EntityId = 3005 AND NULLIF(LTRIM(RTRIM(PhoneNumber)),'') IS NOT NULL));
-- expected: 76

/* -- 7. Today's dormancy backlog (ExpectedClearDate clock, per your ruling) - */
SELECT 'dormant 60d on 3002' AS check_name, COUNT(*) AS n
FROM (SELECT l.BorrowerId,
             MAX(CASE WHEN l.LoanCleared = 1 THEN 0 ELSE 1 END) AS any_open,
             MAX(CAST(l.ExpectedClearDate AS DATETIME))         AS last_maturity
      FROM dbo.Loans l WHERE l.EntityId = 3002 GROUP BY l.BorrowerId) x
JOIN dbo.Borrowers b ON b.ID = x.BorrowerId AND b.EntityId = 3002
WHERE x.any_open = 0 AND x.last_maturity < DATEADD(DAY, -60, GETDATE());
-- expected: ~568 (grows daily -- this is the backlog script 10 clears on run 1)

/* -- 8. Credential hygiene ------------------------------------------------- */
SELECT 'ussd pin shapes' AS check_name, LEFT(UssdPin,4) AS prefix, LEN(UssdPin) AS len, COUNT(*) AS n
FROM dbo.Borrowers WHERE NULLIF(UssdPin,'') IS NOT NULL
GROUP BY LEFT(UssdPin,4), LEN(UssdPin) ORDER BY n DESC;
-- expected: $2b$/60 = 12941, $2a$/60 = 2528, $2a$/50 = 40  <- the 40 are broken

PRINT '=== Preflight complete. Nothing was written. ===';
