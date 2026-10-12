/*==========================================================================
  16 · MICROMART FINTECH (3005) INTO THE COLLECTION TRACKER, EVERY RUN

  WHY THIS EXISTS
  CallBox shows a case only when its CollectionTracker row carries an
  amount: every list Micromart's agents work (sp_Prepaymentlist,
  sp_Loansduelist, sp_Watch1list ... sp_Npllist) requires Amounttopay > 100.
  That amount is written by ONE procedure, sp_GeneralCollectionTrackerbooks,
  which runs Micromart's six generators -- and it passes them 3002, while
  three of the six hardcode 3002 inside as well. So no Fintech loan is ever
  given an amount.

  It is worse than "not fed". Every generator opens with a reset that is NOT
  scoped to an entity (UPDATE CollectionTracker SET Watch1 = 0 WHERE
  Watch1 > 0, and so on for every band). The run that does it fires every
  few minutes. So anything written into a Fintech row from outside -- the
  ConnectDesk Fintech bridge pulled 188 cases on 4 Oct 2026 at 19:41 -- is
  zeroed by the next run. Read live on 6 Oct 2026 03:16: 1,690 Fintech rows
  on the tracker, every one at Amounttopay 0, none visible in CallBox.

  And calling the generators a second time with 3005 does NOT work: the
  second call's reset zeroes everything the 3002 call just wrote, and the
  main book's floor goes blank. Never do that.

  WHAT THIS DOES
  Feeds 3005 INSIDE Micromart's own run, straight after their six 3002
  generators and before their post-steps, with their arithmetic, so a
  Fintech loan enters, ages, changes band and leaves the tracker exactly as
  a main-book loan does -- same windows, same thresholds, same 01:30 sort
  into categories, same agent lists, same Amounttopay rule. Nothing about
  the main book changes.

  WHAT IT INSTALLS
    16.0  preflight                 read-only; keep the output
    16.1  two small tables          the run log and a backup of what 16.4 alters
    16.2  dbo.sp_MicroEazy_FeedFintechToCollectBox   new procedure, dry run default
    16.3  the dry run               read-only: what tonight's floor would hold
    16.4  the hook                  the ONE change to Micromart's code: four lines
                                    inside sp_GeneralCollectionTrackerbooks.
                                    Off until you set @Install = 1.
    16.5  optional: feed now        so the cases show this morning, not tonight
    16.6  verify                    read-only

  Run in SSMS against Serviceconnect, ONE SECTION AT A TIME, reading the
  messages pane between each. Every section is safe to re-run. Undo with
  16-17-ROLLBACK-collectbox-feed.sql.

  What the feed gives the floor, measured 6 Oct 2026 03:20 with this rule:
  about 164 Fintech cases with an amount (20 Prepayment, 9 Due, 74 Watch 1,
  34 Watch 2, 27 Watch 1 Matured; KES ~0.73M to collect). 1,672 of the
  1,881 open 3005 loans have no schedule rows at all -- the migration stubs
  with nothing to collect -- and stay out, exactly as they should.
  ==========================================================================*/


/* -------------------------------------------------------------------------
   16.0 · PREFLIGHT — read-only. Keep the output.

   (a) The hook rides whatever schedule calls sp_GeneralCollectionTrackerbooks.
       If the job steps below call the six generators DIRECTLY instead of the
       master, the hook would never run: stop and send this output.
   (b) The master must contain its last generator line exactly once.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;

SELECT j.name AS job, j.enabled, s.step_id, s.step_name, s.database_name,
       LEFT(REPLACE(REPLACE(s.command, CHAR(13), ' '), CHAR(10), ' '), 400) AS command
  FROM msdb.dbo.sysjobs j
  JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
 WHERE s.command LIKE '%CollectionTracker%' OR s.command LIKE '%ForCollectBox%'
    OR s.command LIKE '%CollectionTrackerbooks%' OR s.command LIKE '%BoooksMigration%'
 ORDER BY j.name, s.step_id;

SELECT j.name AS job, sc.name AS schedule, sc.enabled, sc.freq_type, sc.freq_interval,
       sc.freq_subday_type, sc.freq_subday_interval, sc.active_start_time, sc.active_end_time
  FROM msdb.dbo.sysjobs j
  JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
  JOIN msdb.dbo.sysschedules sc    ON sc.schedule_id = js.schedule_id
 WHERE j.job_id IN (SELECT job_id FROM msdb.dbo.sysjobsteps
                     WHERE command LIKE '%CollectionTracker%' OR command LIKE '%ForCollectBox%'
                        OR command LIKE '%CollectionTrackerbooks%' OR command LIKE '%BoooksMigration%');

SELECT m.uses_ansi_nulls, m.uses_quoted_identifier,
       (DATALENGTH(m.definition)
        - DATALENGTH(REPLACE(m.definition, N'EXEC sp_GenerateCollectionTrackerDueLoansForCollectBox 3002', N'')))
        / DATALENGTH(N'EXEC sp_GenerateCollectionTrackerDueLoansForCollectBox 3002')        AS anchorLines,   -- must be 1
       CASE WHEN m.definition LIKE N'%sp_MicroEazy_FeedFintechToCollectBox%' THEN 1 ELSE 0 END AS hookAlreadyIn
  FROM sys.sql_modules m
 WHERE m.object_id = OBJECT_ID(N'dbo.sp_GeneralCollectionTrackerbooks');

SELECT COUNT(*)                                            AS fintechRowsOnTracker,   -- ~1,690 on 6 Oct
       SUM(CASE WHEN ct.Amounttopay > 100 THEN 1 ELSE 0 END) AS showInCallBoxToday      -- 0 on 6 Oct
  FROM CollectBox.dbo.CollectionTracker ct
  JOIN dbo.Loans l ON l.id = ct.LoanId
 WHERE l.EntityId = 3005;
GO


/* -------------------------------------------------------------------------
   16.1 · Two small tables, both additive.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
IF OBJECT_ID(N'dbo.MicroEazyCollectBoxFeedLog') IS NULL
BEGIN
    -- One row per feed. The hook runs with Micromart's job, every few minutes;
    -- rows older than 30 days are pruned by the feed itself.
    CREATE TABLE dbo.MicroEazyCollectBoxFeedLog (
        Id          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MicroEazyCollectBoxFeedLog PRIMARY KEY,
        RunAt       DATETIME2(0)      NOT NULL CONSTRAINT DF_MECBFL_RunAt DEFAULT SYSDATETIME(),
        EntityId    INT               NOT NULL,
        Source      VARCHAR(20)       NOT NULL,   -- 'hook' = inside Micromart's run; 'manual' = by hand
        Loans       INT               NULL,       -- this book's tracker rows carrying a band amount
        Inserted    INT               NULL,       -- rows this run added to the tracker
        Updated     INT               NULL,       -- rows this run refreshed
        Visible     INT               NULL,       -- Amounttopay > 100: what CallBox's lists can show
        AmountToPay DECIMAL(18,2)     NULL,
        DurationMs  INT               NULL,
        Error       NVARCHAR(2000)    NULL
    );
    PRINT 'Created dbo.MicroEazyCollectBoxFeedLog';
END

IF OBJECT_ID(N'dbo.MicroEazyCollectBoxHookBackup') IS NULL
BEGIN
    -- The exact text of every Micromart procedure 16.4 or 17 alters, taken
    -- in the same transaction as the ALTER. The rollback reads it.
    CREATE TABLE dbo.MicroEazyCollectBoxHookBackup (
        Id             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MicroEazyCollectBoxHookBackup PRIMARY KEY,
        DbName         SYSNAME           NOT NULL,
        ObjectName     SYSNAME           NOT NULL,
        SavedAt        DATETIME2(0)      NOT NULL CONSTRAINT DF_MECBHB_SavedAt DEFAULT SYSDATETIME(),
        SavedBy        SYSNAME           NOT NULL CONSTRAINT DF_MECBHB_SavedBy DEFAULT SUSER_SNAME(),
        DefinitionHash VARBINARY(32)     NOT NULL,
        Definition     NVARCHAR(MAX)     NOT NULL
    );
    PRINT 'Created dbo.MicroEazyCollectBoxHookBackup';
END
GO


/* -------------------------------------------------------------------------
   16.2 · The feed.
          EXEC dbo.sp_MicroEazy_FeedFintechToCollectBox;                 -- dry run
          EXEC dbo.sp_MicroEazy_FeedFintechToCollectBox @DryRun = 0;     -- feed

   Faithful to Micromart's generators on purpose, including the parts that
   look odd (Watch 3 has no amount floor; the Due window has no > 100 floor;
   NPL is days past MATURITY, not past an instalment). The one deliberate
   difference: the Due window is grouped per loan. Theirs is not, so a loan
   with two instalments due the same day would make their MERGE fail
   (error 8672) and take the whole window down with it.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
CREATE OR ALTER PROCEDURE dbo.sp_MicroEazy_FeedFintechToCollectBox
    @EntityId   INT         = 3005,
    @DryRun     BIT         = 1,       -- default is SAFE: report, write nothing
    @Categorise BIT         = 0,       -- 1 = also sort this book's rows into bands now (a hand run);
                                       --     otherwise CollectionTrackerBoooksMigration does it at 01:30
    @Source     VARCHAR(20) = 'manual' -- 'hook' when Micromart's own run calls it
AS
BEGIN
    SET NOCOUNT ON;
    SET LOCK_TIMEOUT 15000;   -- a blocked lock fails THIS feed in 15 s; it never holds up Micromart's run

    DECLARE @t0 DATETIME2(3) = SYSDATETIME();

    IF @EntityId IS NULL OR @EntityId = 3002
    BEGIN
        PRINT 'Entity 3002 is fed by sp_GeneralCollectionTrackerbooks itself. Nothing done.';
        RETURN;
    END

    BEGIN TRY
        /* 1 · This book's unpaid instalments, from 2023 to two days ahead, in
               ONE pass over loanSchedule (a 2M-row heap with no index: their
               six generators already scan it six times a run; this is one
               more). Only status = 0 rows can move any figure the generators
               write, so nothing that matters is filtered out. */
        SELECT LS.Loanid, LS.ExpectedDueDate, LS.amounttopay, LS.status, LS.entryid
          INTO #me_ls
          FROM dbo.loanSchedule LS
          JOIN dbo.Loans L ON L.ID = LS.Loanid
         WHERE L.EntityId = @EntityId
           AND LS.status = 0
           AND LS.ExpectedDueDate >= '20230101'
           AND LS.ExpectedDueDate <  DATEADD(DAY, 3, CAST(GETDATE() AS DATE));
        CREATE CLUSTERED INDEX IX_me_ls ON #me_ls (Loanid);

        /* 2 · The six windows, each one the generator's own arithmetic. */

        -- Prepayment 2 — an instalment falls due in two days (sp_GenerateUpcomingPrepayment2LoansForCollectBox)
        SELECT Loanid,
               MIN(DATEDIFF(DAY, GETDATE(), ExpectedDueDate)) AS days_to_due,
               SUM(amounttopay)                               AS due_amount,
               MIN(entryid)                                   AS Installment
          INTO #me_p2
          FROM #me_ls
         WHERE DATEDIFF(DAY, GETDATE(), ExpectedDueDate) IN (2) AND status = 0 AND amounttopay > 100
         GROUP BY Loanid;

        -- Prepayment 1 — due tomorrow (sp_GenerateUpcomingPrepayment1LoansForCollectBox)
        SELECT Loanid,
               MIN(DATEDIFF(DAY, GETDATE(), ExpectedDueDate)) AS days_to_due,
               SUM(amounttopay)                               AS due_amount,
               MIN(entryid)                                   AS Installment
          INTO #me_p1
          FROM #me_ls
         WHERE DATEDIFF(DAY, GETDATE(), ExpectedDueDate) IN (1) AND status = 0 AND amounttopay > 100
         GROUP BY Loanid;

        -- Watch 1 — 1 to 30 days past an instalment (sp_GenerateWatch1ArrearsForCollectBox)
        SELECT Loanid,
               ISNULL(DATEDIFF(DAY, MIN(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE())
                                              AND status = 0 AND amounttopay > 0 THEN ExpectedDueDate END), GETDATE()), 0) AS days_in_arrears,
               ISNULL(SUM(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE()) AND status = 0
                               THEN amounttopay ELSE 0 END), 0)                                                          AS total_arrears,
               MIN(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE())
                         AND status = 0 AND amounttopay > 0 THEN ExpectedDueDate END)                                    AS FirstDateInArrears
          INTO #me_w1
          FROM #me_ls
         WHERE DATEDIFF(DAY, ExpectedDueDate, GETDATE()) BETWEEN 1 AND 30 AND amounttopay > 100
         GROUP BY Loanid
        HAVING SUM(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE()) AND status = 0
                        THEN amounttopay ELSE 0 END) > 0;

        -- Watch 2 — 31 to 60 days (sp_GenerateWatch2ArrearsForCollectBox)
        SELECT Loanid,
               ISNULL(DATEDIFF(DAY, MIN(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE())
                                              AND status = 0 AND amounttopay > 0 THEN ExpectedDueDate END), GETDATE()), 0) AS days_in_arrears,
               ISNULL(SUM(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE()) AND status = 0
                               THEN amounttopay ELSE 0 END), 0)                                                          AS total_arrears,
               MIN(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE())
                         AND status = 0 AND amounttopay > 0 THEN ExpectedDueDate END)                                    AS FirstDateInArrears
          INTO #me_w2
          FROM #me_ls
         WHERE DATEDIFF(DAY, ExpectedDueDate, GETDATE()) BETWEEN 31 AND 60 AND amounttopay > 100
         GROUP BY Loanid
        HAVING SUM(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE()) AND status = 0
                        THEN amounttopay ELSE 0 END) > 0;

        -- Watch 3 — over 60 days, instalments since 2023, no amount floor (sp_GenerateWatch3ArrearsForCollectBox)
        SELECT Loanid,
               ISNULL(DATEDIFF(DAY, MIN(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE())
                                              AND status = 0 AND amounttopay > 0 THEN ExpectedDueDate END), GETDATE()), 0) AS days_in_arrears,
               ISNULL(SUM(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE()) AND status = 0
                               THEN amounttopay ELSE 0 END), 0)                                                          AS total_arrears,
               MIN(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE())
                         AND status = 0 AND amounttopay > 0 THEN ExpectedDueDate END)                                    AS FirstDateInArrears
          INTO #me_w3
          FROM #me_ls
         WHERE DATEDIFF(DAY, ExpectedDueDate, GETDATE()) > 60 AND YEAR(ExpectedDueDate) > 2022
         GROUP BY Loanid
        HAVING SUM(CASE WHEN CONVERT(DATE, ExpectedDueDate) < CONVERT(DATE, GETDATE()) AND status = 0
                        THEN amounttopay ELSE 0 END) > 0;

        -- Due — an instalment falls due today (sp_GenerateCollectionTrackerDueLoansForCollectBox), one row per loan
        SELECT Loanid,
               MIN(DATEDIFF(DAY, ExpectedDueDate, GETDATE())) AS days_to_due,
               SUM(amounttopay)                               AS due_amount,
               MIN(ExpectedDueDate)                           AS DueDate,
               MIN(entryid)                                   AS Installment
          INTO #me_due
          FROM #me_ls
         WHERE CONVERT(DATE, ExpectedDueDate) = CONVERT(DATE, GETDATE()) AND status = 0 AND amounttopay > 0
         GROUP BY Loanid;

        /* 3 · This book's rows already on the tracker. */
        SELECT CAST(ct.Id AS INT) AS Id, ct.LoanId
          INTO #me_mine
          FROM CollectBox.dbo.CollectionTracker ct
          JOIN dbo.Loans L ON L.ID = ct.LoanId
         WHERE L.EntityId = @EntityId;
        CREATE CLUSTERED INDEX IX_me_mine ON #me_mine (Id);

        /* 4 · A dry run stops here: what the floor would hold after tonight's
               01:30 sort, and nothing written anywhere. */
        IF @DryRun = 1
        BEGIN
            ;WITH k AS (
                SELECT Loanid FROM #me_p2 UNION SELECT Loanid FROM #me_p1
                UNION SELECT Loanid FROM #me_w1 UNION SELECT Loanid FROM #me_w2
                UNION SELECT Loanid FROM #me_w3 UNION SELECT Loanid FROM #me_due
                UNION SELECT LoanId FROM #me_mine
            ), v AS (
                SELECT k.Loanid AS LoanId, L.BorrowerId, ISNULL(L.LoanBalance, 0) AS LoanBalance, L.isApproved, L.ExpectedClearDate,
                       ISNULL(p2.due_amount, 0)    AS Prepayment2,
                       ISNULL(p1.due_amount, 0)    AS Prepayment1,
                       ISNULL(w1.total_arrears, 0) AS Watch1,
                       ISNULL(w2.total_arrears, 0) AS Watch2,
                       -- the master's post-step: past maturity by 90 days, Watch 3 becomes NPL at the full balance
                       CASE WHEN DATEDIFF(DAY, L.ExpectedClearDate, GETDATE()) > 90 THEN 0 ELSE ISNULL(w3.total_arrears, 0) END AS Watch3,
                       CASE WHEN DATEDIFF(DAY, L.ExpectedClearDate, GETDATE()) > 90 THEN ISNULL(L.LoanBalance, 0) ELSE 0 END    AS Npl,
                       ISNULL(d.due_amount, 0)     AS AmountDue,
                       -- the last window to match sets the days, as in the master's order
                       COALESCE(d.days_to_due, w3.days_in_arrears, w2.days_in_arrears, w1.days_in_arrears,
                                p1.days_to_due, p2.days_to_due, ct.DaysInArears) AS DaysInArears,
                       ct.LoanId AS OnTracker, ct.Loantype AS LoantypeNow, ct.AgentAssigned AS AgentNow
                  FROM k
                  JOIN dbo.Loans L ON L.ID = k.Loanid
                  LEFT JOIN #me_p2 p2 ON p2.Loanid = k.Loanid
                  LEFT JOIN #me_p1 p1 ON p1.Loanid = k.Loanid
                  LEFT JOIN #me_w1 w1 ON w1.Loanid = k.Loanid
                  LEFT JOIN #me_w2 w2 ON w2.Loanid = k.Loanid
                  LEFT JOIN #me_w3 w3 ON w3.Loanid = k.Loanid
                  LEFT JOIN #me_due d ON d.Loanid = k.Loanid
                  OUTER APPLY (SELECT TOP 1 c.LoanId, c.Loantype, c.AgentAssigned, c.DaysInArears
                                 FROM CollectBox.dbo.CollectionTracker c
                                WHERE c.LoanId = k.Loanid
                                ORDER BY c.Id) ct
            ), c AS (
                -- CollectionTrackerBoooksMigration's own rule (the 01:30 sort)
                SELECT v.*,
                       CASE WHEN Npl > 0 THEN 6
                            WHEN Watch3 > 0 THEN 5
                            WHEN Watch2 > 0 THEN 4
                            WHEN Watch1 > 0 AND ExpectedClearDate > GETDATE() THEN 3
                            WHEN Watch1 > 0 AND ExpectedClearDate < GETDATE() THEN 7
                            WHEN AmountDue > 0 THEN 2
                            WHEN Prepayment1 > 0 THEN 1
                            WHEN Prepayment2 > 0 THEN 1
                            ELSE LoantypeNow END AS LoantypeTonight
                  FROM v
            )
            SELECT c.*,
                   CASE LoantypeTonight
                        WHEN 6 THEN Npl + Watch1 + Watch2 + Watch3 + Prepayment1 + Prepayment2
                        WHEN 5 THEN Npl + Watch1 + Watch2 + Watch3
                        WHEN 4 THEN Npl + Watch1 + Watch2 + Watch3
                        WHEN 3 THEN Npl + Watch1 + Watch2 + Watch3
                        WHEN 7 THEN Npl + Watch1 + Watch2 + Watch3
                        WHEN 2 THEN AmountDue
                        WHEN 1 THEN CASE WHEN DaysInArears = 1 THEN Prepayment1 ELSE Prepayment2 END
                   END AS AmountToPayTonight
              INTO #me_dry
              FROM c;

            -- By band, as CallBox will show it
            SELECT CASE WHEN ISNULL(d.AmountToPayTonight, 0) > 0 THEN ISNULL(lc.CategotyName, 'No band yet')
                        ELSE 'On the tracker, nothing due' END                                        AS Band,
                   COUNT(*)                                                                           AS Loans,
                   CAST(SUM(ISNULL(d.AmountToPayTonight, 0)) AS DECIMAL(18,2))                        AS AmountToPay,
                   SUM(CASE WHEN d.OnTracker IS NOT NULL THEN 1 ELSE 0 END)                           AS AlreadyOnTracker,
                   SUM(CASE WHEN d.OnTracker IS NULL THEN 1 ELSE 0 END)                               AS NewRows,
                   SUM(CASE WHEN ISNULL(d.AgentNow, 0) > 0 THEN 1 ELSE 0 END)                         AS AgentAssignedNow,
                   SUM(CASE WHEN d.AmountToPayTonight > 100 AND d.LoanBalance > 0 AND d.isApproved = 1
                            THEN 1 ELSE 0 END)                                                        AS ShowsInCallBox
              FROM #me_dry d
              LEFT JOIN CollectBox.dbo.LoanCategories lc ON lc.ID = d.LoantypeTonight
             GROUP BY CASE WHEN ISNULL(d.AmountToPayTonight, 0) > 0 THEN ISNULL(lc.CategotyName, 'No band yet')
                           ELSE 'On the tracker, nothing due' END
             ORDER BY MIN(CASE WHEN ISNULL(d.AmountToPayTonight, 0) > 0 THEN ISNULL(d.LoantypeTonight, 98) ELSE 99 END);

            -- Every case that will carry an amount
            SELECT d.LoanId, d.BorrowerId, lc.CategotyName AS BandTonight, d.DaysInArears,
                   CAST(d.AmountToPayTonight AS DECIMAL(18,2)) AS AmountToPay,
                   CAST(d.LoanBalance AS DECIMAL(18,2))        AS LoanBalance,
                   CASE WHEN d.OnTracker IS NULL THEN 'new row' ELSE 'on tracker' END AS Tracker,
                   lcNow.CategotyName AS BandNow, d.AgentNow
              FROM #me_dry d
              LEFT JOIN CollectBox.dbo.LoanCategories lc    ON lc.ID = d.LoantypeTonight
              LEFT JOIN CollectBox.dbo.LoanCategories lcNow ON lcNow.ID = d.LoantypeNow
             WHERE ISNULL(d.AmountToPayTonight, 0) > 0
             ORDER BY d.LoantypeTonight, d.AmountToPayTonight DESC;

            PRINT 'DRY RUN -- nothing was written.';
            RETURN;
        END

        /* 5 · Zero this book's balances: Micromart's resets, scoped to this
               book's rows ONLY. Inside Micromart's run their own resets have
               already zeroed every row, so this matters only for a hand run. */
        DECLARE @acts TABLE (Id INT NOT NULL, LoanId INT NOT NULL, act NVARCHAR(10) NOT NULL);

        UPDATE ct
           SET Prepayment2 = CASE WHEN ct.Prepayment2 > 0 THEN 0 ELSE ct.Prepayment2 END,
               Prepayment1 = CASE WHEN ct.Prepayment1 > 0 THEN 0 ELSE ct.Prepayment1 END,
               Watch1      = CASE WHEN ct.Watch1      > 0 THEN 0 ELSE ct.Watch1      END,
               Watch2      = CASE WHEN ct.Watch2      > 0 THEN 0 ELSE ct.Watch2      END,
               Watch3      = CASE WHEN ct.Watch3      > 0 THEN 0 ELSE ct.Watch3      END,
               Npl         = CASE WHEN ct.Npl         > 0 THEN 0 ELSE ct.Npl         END,
               AmountDue   = CASE WHEN ct.AmountDue   > 0 THEN 0 ELSE ct.AmountDue   END
          FROM CollectBox.dbo.CollectionTracker ct
          JOIN #me_mine m ON m.Id = ct.Id
         WHERE ct.Prepayment2 > 0 OR ct.Prepayment1 > 0 OR ct.Watch1 > 0 OR ct.Watch2 > 0
            OR ct.Watch3 > 0 OR ct.Npl > 0 OR ct.AmountDue > 0;

        /* 6 · The six MERGEs, in sp_GeneralCollectionTrackerbooks' order, each
               setting exactly the columns the generator sets. A new row
               arrives unassigned (IsAgentAssigned 0) like every main-book row;
               Micromart's own 01:30 run sorts it and gives it an agent. */
        MERGE CollectBox.dbo.CollectionTracker AS target
        USING #me_p2 AS source ON target.LoanId = source.Loanid
        WHEN MATCHED THEN UPDATE SET
            target.DaysInArears = source.days_to_due,
            target.Prepayment2  = source.due_amount,
            target.Last_update  = GETDATE(),
            target.Installment  = source.Installment
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (LoanId, DaysInArears, Prepayment2, Create_date, IsAgentAssigned, Installment)
            VALUES (source.Loanid, source.days_to_due, source.due_amount, GETDATE(), 0, source.Installment)
        OUTPUT inserted.Id, inserted.LoanId, $action INTO @acts (Id, LoanId, act);

        MERGE CollectBox.dbo.CollectionTracker AS target
        USING #me_p1 AS source ON target.LoanId = source.Loanid
        WHEN MATCHED THEN UPDATE SET
            target.DaysInArears = source.days_to_due,
            target.Prepayment1  = source.due_amount,
            target.Last_update  = GETDATE(),
            target.Installment  = source.Installment
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (LoanId, DaysInArears, Prepayment1, Create_date, IsAgentAssigned, Installment)
            VALUES (source.Loanid, source.days_to_due, source.due_amount, GETDATE(), 0, source.Installment)
        OUTPUT inserted.Id, inserted.LoanId, $action INTO @acts (Id, LoanId, act);

        MERGE CollectBox.dbo.CollectionTracker AS target
        USING #me_w1 AS source ON target.LoanId = source.Loanid
        WHEN MATCHED THEN UPDATE SET
            target.DaysInArears       = source.days_in_arrears,
            target.Watch1             = source.total_arrears,
            target.FirstDateInArrears = source.FirstDateInArrears,
            target.Last_update        = GETDATE()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (LoanId, DaysInArears, Watch1, Create_date, FirstDateInArrears, IsAgentAssigned)
            VALUES (source.Loanid, source.days_in_arrears, source.total_arrears, GETDATE(), source.FirstDateInArrears, 0)
        OUTPUT inserted.Id, inserted.LoanId, $action INTO @acts (Id, LoanId, act);

        MERGE CollectBox.dbo.CollectionTracker AS target
        USING #me_w2 AS source ON target.LoanId = source.Loanid
        WHEN MATCHED THEN UPDATE SET
            target.DaysInArears       = source.days_in_arrears,
            target.Watch2             = source.total_arrears,
            target.FirstDateInArrears = source.FirstDateInArrears,
            target.Last_update        = GETDATE()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (LoanId, DaysInArears, Watch2, Create_date, FirstDateInArrears, IsAgentAssigned)
            VALUES (source.Loanid, source.days_in_arrears, source.total_arrears, GETDATE(), source.FirstDateInArrears, 0)
        OUTPUT inserted.Id, inserted.LoanId, $action INTO @acts (Id, LoanId, act);

        MERGE CollectBox.dbo.CollectionTracker AS target
        USING #me_w3 AS source ON target.LoanId = source.Loanid
        WHEN MATCHED THEN UPDATE SET
            target.DaysInArears       = source.days_in_arrears,
            target.Watch3             = source.total_arrears,
            target.FirstDateInArrears = source.FirstDateInArrears,
            target.Last_update        = GETDATE()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (LoanId, DaysInArears, Watch3, Create_date, FirstDateInArrears, IsAgentAssigned)
            VALUES (source.Loanid, source.days_in_arrears, source.total_arrears, GETDATE(), source.FirstDateInArrears, 0)
        OUTPUT inserted.Id, inserted.LoanId, $action INTO @acts (Id, LoanId, act);

        MERGE CollectBox.dbo.CollectionTracker AS target
        USING #me_due AS source ON target.LoanId = source.Loanid
        WHEN MATCHED THEN UPDATE SET
            target.DaysInArears       = source.days_to_due,
            target.FirstDateInArrears = source.DueDate,
            target.AmountDue          = source.due_amount,
            target.Last_update        = GETDATE(),
            target.Installment        = source.Installment
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (LoanId, DaysInArears, AmountDue, Create_date, FirstDateInArrears, IsAgentAssigned, Installment)
            VALUES (source.Loanid, source.days_to_due, source.due_amount, GETDATE(), source.DueDate, 0, source.Installment)
        OUTPUT inserted.Id, inserted.LoanId, $action INTO @acts (Id, LoanId, act);

        /* 7 · Rows this run created join the set the post-steps work on. */
        INSERT INTO #me_mine (Id, LoanId)
        SELECT DISTINCT Id, LoanId FROM @acts WHERE act = N'INSERT';

        /* 8 · The master's post-steps, scoped to this book: NPL by maturity,
               then the amount CallBox's lists read. Inside Micromart's run
               the master repeats both straight after, to the same result. */
        UPDATE ct SET Watch3 = L.LoanBalance
          FROM CollectBox.dbo.CollectionTracker ct
          JOIN #me_mine m ON m.Id = ct.Id
          JOIN dbo.Loans L ON L.ID = ct.LoanId
         WHERE DATEDIFF(DAY, L.Expectedcleardate, GETDATE()) > 90;

        UPDATE ct SET Npl = ct.Watch3, Watch3 = 0
          FROM CollectBox.dbo.CollectionTracker ct
          JOIN #me_mine m ON m.Id = ct.Id
          JOIN dbo.Loans L ON L.ID = ct.LoanId
         WHERE DATEDIFF(DAY, L.Expectedcleardate, GETDATE()) > 90;

        IF @Categorise = 1
            UPDATE ct
               SET Loantype = CASE
                       WHEN ct.Npl > 0 THEN 6
                       WHEN ct.Watch3 > 0 THEN 5
                       WHEN ct.Watch2 > 0 THEN 4
                       WHEN ct.Watch1 > 0 AND L.ExpectedClearDate > GETDATE() THEN 3
                       WHEN ct.Watch1 > 0 AND L.ExpectedClearDate < GETDATE() THEN 7
                       WHEN ct.AmountDue > 0 THEN 2
                       WHEN ct.Prepayment1 > 0 THEN 1
                       WHEN ct.Prepayment2 > 0 THEN 1
                       ELSE ct.Loantype END
              FROM CollectBox.dbo.CollectionTracker ct
              JOIN #me_mine m ON m.Id = ct.Id
              JOIN dbo.Loans L ON L.ID = ct.LoanId;

        UPDATE ct
           SET Amounttopay = CASE
                   WHEN ct.Loantype = 6 THEN ISNULL(ct.Npl, 0) + ISNULL(ct.Watch1, 0) + ISNULL(ct.Watch2, 0) + ISNULL(ct.Watch3, 0)
                                            + ISNULL(ct.Prepayment1, 0) + ISNULL(ct.Prepayment2, 0)
                   WHEN ct.Loantype IN (3, 4, 5, 7) THEN ISNULL(ct.Npl, 0) + ISNULL(ct.Watch1, 0) + ISNULL(ct.Watch2, 0) + ISNULL(ct.Watch3, 0)
                   WHEN ct.Loantype = 2 THEN ISNULL(ct.AmountDue, 0)
                   WHEN ct.Loantype = 1 THEN CASE WHEN ct.DaysInArears = 1 THEN ISNULL(ct.Prepayment1, 0) ELSE ISNULL(ct.Prepayment2, 0) END
               END
          FROM CollectBox.dbo.CollectionTracker ct
          JOIN #me_mine m ON m.Id = ct.Id;

        /* 9 · The record. */
        DECLARE @loans INT, @visible INT, @amount DECIMAL(18,2);
        SELECT @loans   = SUM(CASE WHEN ISNULL(ct.Prepayment1, 0) + ISNULL(ct.Prepayment2, 0) + ISNULL(ct.AmountDue, 0)
                                       + ISNULL(ct.Watch1, 0) + ISNULL(ct.Watch2, 0) + ISNULL(ct.Watch3, 0) + ISNULL(ct.Npl, 0) > 0
                                   THEN 1 ELSE 0 END),
               @visible = SUM(CASE WHEN ct.Amounttopay > 100 THEN 1 ELSE 0 END),
               @amount  = SUM(CASE WHEN ct.Amounttopay > 0 THEN ct.Amounttopay ELSE 0 END)
          FROM CollectBox.dbo.CollectionTracker ct
          JOIN #me_mine m ON m.Id = ct.Id;

        INSERT INTO dbo.MicroEazyCollectBoxFeedLog (EntityId, Source, Loans, Inserted, Updated, Visible, AmountToPay, DurationMs)
        SELECT @EntityId, @Source, ISNULL(@loans, 0),
               (SELECT COUNT(DISTINCT Id) FROM @acts WHERE act = N'INSERT'),
               (SELECT COUNT(DISTINCT Id) FROM @acts WHERE act = N'UPDATE'),
               ISNULL(@visible, 0), ISNULL(@amount, 0), DATEDIFF(MILLISECOND, @t0, SYSDATETIME());

        DELETE FROM dbo.MicroEazyCollectBoxFeedLog WHERE RunAt < DATEADD(DAY, -30, SYSDATETIME());

        IF @Source <> 'hook'
            PRINT CONCAT('Fed entity ', @EntityId, ': ', ISNULL(@loans, 0), ' loans carry a band amount; ',
                         ISNULL(@visible, 0), ' have Amounttopay > 100, which is what CallBox''s lists show.');
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(2000) = LEFT(CONCAT('Error ', ERROR_NUMBER(), ' at line ', ERROR_LINE(), ': ', ERROR_MESSAGE()), 2000);
        BEGIN TRY
            INSERT INTO dbo.MicroEazyCollectBoxFeedLog (EntityId, Source, DurationMs, Error)
            VALUES (@EntityId, @Source, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), @err);
        END TRY
        BEGIN CATCH
            PRINT 'The feed log could not be written either.';
        END CATCH;
        PRINT CONCAT('Micro Eazy Fintech feed failed: ', @err);
        -- A person running it by hand should see the error. Micromart's run must not:
        -- the hook swallows it and their post-steps carry on.
        IF @Source <> 'hook' THROW;
    END CATCH
END
GO


/* -------------------------------------------------------------------------
   16.3 · THE DRY RUN — read-only. Two result sets: the floor by band, and
          every Fintech case that will carry an amount. Read them before 16.4.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
EXEC dbo.sp_MicroEazy_FeedFintechToCollectBox @EntityId = 3005, @DryRun = 1;
GO


/* -------------------------------------------------------------------------
   16.4 · THE HOOK — the one change to Micromart's own code.

   Inserts four lines into sp_GeneralCollectionTrackerbooks, straight after
   its last generator (the Due window) and before its post-steps:

       BEGIN TRY
           EXEC dbo.sp_MicroEazy_FeedFintechToCollectBox @EntityId = 3005, @DryRun = 0, @Source = 'hook';
       END TRY
       BEGIN CATCH ... END CATCH

   Everything else in their procedure stays byte for byte as it is: the
   script edits the CURRENT definition, it does not paste an old copy over
   it. Their text is saved to dbo.MicroEazyCollectBoxHookBackup in the same
   transaction as the ALTER. A Fintech failure is caught, logged, and the
   main book's post-steps run regardless.

   Run it once with @Install = 0 (the default): it checks everything and
   prints the procedure as it would read. Then set @Install = 1.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 60000;   -- Micromart's run holds the procedure for a few seconds every few minutes

DECLARE @Install BIT = 0;   -- <<< set to 1 once 16.3 reads right

DECLARE @obj    INT           = OBJECT_ID(N'dbo.sp_GeneralCollectionTrackerbooks');
DECLARE @def    NVARCHAR(MAX) = OBJECT_DEFINITION(@obj);
DECLARE @anchor NVARCHAR(200) = N'EXEC sp_GenerateCollectionTrackerDueLoansForCollectBox 3002';
DECLARE @crlf   NCHAR(2)      = NCHAR(13) + NCHAR(10);
DECLARE @n INT, @at INT, @len INT, @hook NVARCHAR(MAX), @new NVARCHAR(MAX);

IF @def IS NULL
BEGIN
    RAISERROR(N'dbo.sp_GeneralCollectionTrackerbooks was not found. Nothing changed.', 16, 1);
    RETURN;
END
IF CHARINDEX(N'sp_MicroEazy_FeedFintechToCollectBox', @def) > 0
BEGIN
    PRINT N'The Fintech hook is already in sp_GeneralCollectionTrackerbooks. Nothing to do.';
    RETURN;
END
IF OBJECT_ID(N'dbo.sp_MicroEazy_FeedFintechToCollectBox') IS NULL OR OBJECT_ID(N'dbo.MicroEazyCollectBoxHookBackup') IS NULL
BEGIN
    RAISERROR(N'Run 16.1 and 16.2 first. Nothing changed.', 16, 1);
    RETURN;
END

SET @n = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @anchor, N''))) / DATALENGTH(@anchor);
IF @n <> 1
BEGIN
    RAISERROR(N'The line "%s" appears %d times in the master, not once: it has changed since 6 Oct 2026. Nothing changed. Send its current text.', 16, 1, @anchor, @n);
    RETURN;
END

IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = @obj AND (uses_ansi_nulls = 0 OR uses_quoted_identifier = 0))
BEGIN
    RAISERROR(N'The master was created with ANSI_NULLS or QUOTED_IDENTIFIER off, and this session would change that. Nothing changed.', 16, 1);
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
    RAISERROR(N'The master''s text does not open with CREATE or ALTER. Nothing changed.', 16, 1);
    RETURN;
END

SET @hook = @anchor + @crlf + @crlf
    + N'-- Micro Eazy, 6 Oct 2026: Micromart Fintech (3005) is fed here by the same rules, in the same run.' + @crlf
    + N'-- A failure is logged in dbo.MicroEazyCollectBoxFeedLog and never stops the steps below.' + @crlf
    + N'BEGIN TRY' + @crlf
    + N'    EXEC dbo.sp_MicroEazy_FeedFintechToCollectBox @EntityId = 3005, @DryRun = 0, @Source = ''hook'';' + @crlf
    + N'END TRY' + @crlf
    + N'BEGIN CATCH' + @crlf
    + N'    PRINT ''Micro Eazy Fintech feed skipped: '' + ERROR_MESSAGE();' + @crlf
    + N'END CATCH' + @crlf;

-- The anchor sits after the keyword, so inserting the hook leaves @at where it was.
SET @new = STUFF(REPLACE(@def, @anchor, @hook), @at, @len, N'ALTER');

IF @Install = 0
BEGIN
    PRINT N'All checks passed. NOTHING CHANGED. After the hook the procedure would read:';
    PRINT N'------------------------------------------------------------------';
    PRINT @new;
    PRINT N'------------------------------------------------------------------';
    PRINT N'Set @Install = 1 and run 16.4 again to apply it.';
    RETURN;
END

BEGIN TRANSACTION;
    INSERT INTO dbo.MicroEazyCollectBoxHookBackup (DbName, ObjectName, DefinitionHash, Definition)
    VALUES (DB_NAME(), N'dbo.sp_GeneralCollectionTrackerbooks', HASHBYTES('SHA2_256', @def), @def);
    EXEC sys.sp_executesql @new;
COMMIT TRANSACTION;

IF CHARINDEX(N'sp_MicroEazy_FeedFintechToCollectBox', OBJECT_DEFINITION(@obj)) > 0
    PRINT N'Hook installed. Micromart''s next run feeds Fintech -- read dbo.MicroEazyCollectBoxFeedLog after it (16.6).';
ELSE
    RAISERROR(N'The ALTER ran but the hook is not in the definition. Look before going further.', 16, 1);
GO


/* -------------------------------------------------------------------------
   16.5 · OPTIONAL — feed and sort now, so today's Fintech cases are on the
          CallBox screens this morning instead of after tonight's 01:30 run.
          Cases that are NEW to the tracker still get their agent at 01:30,
          exactly as main-book cases do. Uncomment to run.
   ---------------------------------------------------------------------- */
-- USE Serviceconnect;
-- EXEC dbo.sp_MicroEazy_FeedFintechToCollectBox @EntityId = 3005, @DryRun = 0, @Categorise = 1;
GO


/* -------------------------------------------------------------------------
   16.6 · VERIFY — read-only. Run a few minutes after 16.4.
          Expect a 'hook' row every few minutes with Error NULL, and Fintech
          cases with amounts in the band list below.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SELECT TOP 12 * FROM dbo.MicroEazyCollectBoxFeedLog ORDER BY Id DESC;

SELECT lc.CategotyName AS Band, COUNT(*) AS Cases,
       SUM(CASE WHEN ct.Amounttopay > 100 THEN 1 ELSE 0 END)                        AS ShowInCallBox,
       CAST(SUM(ct.Amounttopay) AS DECIMAL(18,2))                                   AS AmountToPay,
       SUM(CASE WHEN ct.IsAgentAssigned = 1 AND ct.AgentAssigned > 0 THEN 1 ELSE 0 END) AS WithAnAgent
  FROM CollectBox.dbo.CollectionTracker ct
  JOIN dbo.Loans l ON l.id = ct.LoanId
  LEFT JOIN CollectBox.dbo.LoanCategories lc ON lc.ID = ct.Loantype
 WHERE l.EntityId = 3005 AND ct.Amounttopay > 0
 GROUP BY lc.CategotyName, ct.Loantype
 ORDER BY ct.Loantype;
GO
