/* ============================================================================
   03 · RE-PARENT THE FINTECH CUSTOMERS

   Every borrower on 3005 moves to branch 129 (Main Office) and off the
   relationship officer who onboarded them. Ownership rule, as specified:

     * default            -> EntityAgent 9098  (Geoffrey Njane, head office)
     * origin is the LMS
       console or our own
       shelf              -> EntityAgent 9096  (Emmanuel Birgen)

   "Origin is the console or the shelf" is read from CreatedBy: a borrower
   created BY 9096, or by a user whose own EntityID is already 3005, did not
   come from a field RO. Everything else is a migrated field customer.

   Rows touched: ~17,022.  Reversible: yes (script ROLLBACK.sql).
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.FintechRemediationBackup_20260908') IS NULL
BEGIN RAISERROR('Run 01-fix-destination.sql first -- the backup table is missing.', 16, 1); RETURN; END

IF EXISTS (SELECT 1 FROM dbo.UserMaster WHERE ID = 9098 AND (ISNULL(UserStatus,0) <> 1 OR ISNULL(OrganizationUnit,0) <> 129))
BEGIN RAISERROR('Geoffrey (9098) is not yet enabled in unit 129. Run 01 first.', 16, 1); RETURN; END

BEGIN TRANSACTION;

    /* -- who belongs to whom -- */
    IF OBJECT_ID('tempdb..#target') IS NOT NULL DROP TABLE #target;
    SELECT b.ID,
           b.EntityUnit  AS OldUnit,
           b.EntityAgent AS OldAgent,
           CASE WHEN b.CreatedBy = 9096
                  OR b.CreatedBy IN (SELECT ID FROM dbo.UserMaster WHERE EntityID = 3005)
                THEN 9096 ELSE 9098 END AS NewAgent
    INTO #target
    FROM dbo.Borrowers b
    WHERE b.EntityId = 3005;

    CREATE CLUSTERED INDEX IX_target ON #target(ID);

    /* -- record before -- */
    INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
    SELECT '03-reparent', 'Borrowers', t.ID, 'EntityUnit', CAST(t.OldUnit AS NVARCHAR(200)), N'129'
    FROM #target t WHERE ISNULL(t.OldUnit, 0) <> 129;

    INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
    SELECT '03-reparent', 'Borrowers', t.ID, 'EntityAgent', CAST(t.OldAgent AS NVARCHAR(200)), CAST(t.NewAgent AS NVARCHAR(200))
    FROM #target t WHERE ISNULL(t.OldAgent, 0) <> t.NewAgent;

    /* -- apply -- */
    UPDATE b
       SET b.EntityUnit  = 129,
           b.EntityAgent = t.NewAgent,
           b.UpdatedBy   = 9096,
           b.UpdatedDate = GETDATE()
    FROM dbo.Borrowers b JOIN #target t ON t.ID = b.ID;

    PRINT 'Re-parented ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' borrowers.';

COMMIT TRANSACTION;

SELECT EntityAgent, EntityUnit, COUNT(*) AS n
FROM dbo.Borrowers WHERE EntityId = 3005
GROUP BY EntityAgent, EntityUnit ORDER BY n DESC;
-- expected: two rows only -- (9098,129) and (9096,129)
PRINT '03 complete.';
