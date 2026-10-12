/*==========================================================================
  17 · OPTIONAL — FINTECH IN CALLBOX'S "NOT REACHABLE" LIST AND OVERALL DASHBOARD

  Run 16 first. This is a separate decision for Micromart, and both parts
  are OFF until you switch them on below.

  WHY
  Every CollectBox login is stamped EntityId 3002 (all 32 on 6 Oct 2026:
  4 supervisors, 28 agents). Most CallBox lists ignore that stamp -- the
  band lists (Prepayment, Due, Watch 1-3, NPL) and the RNR, Negotiation,
  Hung up, PTP, Callback and Other lists all show a Fintech case once 16 has
  given it an amount. Three procedures filter on it instead:

    sp_NotReachable_CallsList   L.EntityId = @EntityId, twice. When an agent
                                marks a Fintech customer "Not reachable" the
                                case leaves the Watch list (it is actioned)
                                and this list hides it -- it disappears from
                                CallBox altogether.
    OverallDashboard            L.EntityId = @EntityId, 14 times: contract
                                OLB, all/received/failed calls, kept PTPs.
                                Fintech would never count.
    FilterDashboard             counts from the Arrears table, which Fintech
                                is not in. Changing it would change nothing,
                                so it is left alone.

  WHAT IT CHANGES
  Each L.EntityId = @EntityId becomes
      (L.EntityId = @EntityId OR (@EntityId = 3002 AND L.EntityId = 3005))
  -- a Micromart login sees Micromart Fintech too; nothing else moves. Like
  16.4 it edits the CURRENT text, refuses if the number of predicates is not
  what was read on 6 Oct 2026, and saves the original text to
  Serviceconnect.dbo.MicroEazyCollectBoxHookBackup in the same transaction.

  Merging the books on the dashboard is Micromart's call: their management
  would then read one combined figure. The Not reachable list is the one
  that loses cases, so it is the one worth doing first.

  Run in SSMS, once with @Apply = 0 (prints what it would do), then 1.
  Undo with 16-17-ROLLBACK-collectbox-feed.sql.
  ==========================================================================*/
USE CollectBox;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 60000;

DECLARE @NotReachable BIT = 0;   -- <<< 1 = patch sp_NotReachable_CallsList
DECLARE @Dashboard    BIT = 0;   -- <<< 1 = patch OverallDashboard
DECLARE @Apply        BIT = 0;   -- <<< 0 = check and report only

DECLARE @tight  NVARCHAR(60)  = N'L.EntityId=@EntityId';
DECLARE @spaced NVARCHAR(60)  = N'L.EntityId = @EntityId';
DECLARE @rTight NVARCHAR(200) = N'(L.EntityId=@EntityId OR (@EntityId = 3002 AND L.EntityId = 3005))';
DECLARE @rSpace NVARCHAR(200) = N'(L.EntityId = @EntityId OR (@EntityId = 3002 AND L.EntityId = 3005))';
DECLARE @marker NVARCHAR(60)  = N'@EntityId = 3002 AND L.EntityId = 3005';

IF OBJECT_ID(N'Serviceconnect.dbo.MicroEazyCollectBoxHookBackup') IS NULL
BEGIN
    RAISERROR(N'Run 16.1 first: Serviceconnect.dbo.MicroEazyCollectBoxHookBackup does not exist. Nothing changed.', 16, 1);
    RETURN;
END

-- What was read on 6 Oct 2026: how many of each spelling each procedure holds.
DECLARE @targets TABLE (ObjectName SYSNAME, Wanted BIT, Tight INT, Spaced INT);
INSERT INTO @targets VALUES (N'dbo.sp_NotReachable_CallsList', @NotReachable, 2, 0),
                            (N'dbo.OverallDashboard',          @Dashboard,    2, 12);

DECLARE @name SYSNAME, @wanted BIT, @wantTight INT, @wantSpaced INT,
        @def NVARCHAR(MAX), @new NVARCHAR(MAX), @at INT, @len INT, @nTight INT, @nSpaced INT;

DECLARE targets CURSOR LOCAL FAST_FORWARD FOR SELECT ObjectName, Wanted, Tight, Spaced FROM @targets;
OPEN targets;
FETCH NEXT FROM targets INTO @name, @wanted, @wantTight, @wantSpaced;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @def = OBJECT_DEFINITION(OBJECT_ID(@name));

    IF @wanted = 0
        PRINT CONCAT(@name, ': not switched on, left alone.');
    ELSE IF @def IS NULL
        PRINT CONCAT(@name, ': not found. Left alone.');
    ELSE IF CHARINDEX(@marker, @def) > 0
        PRINT CONCAT(@name, ': already shows Fintech. Nothing to do.');
    ELSE IF EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id = OBJECT_ID(@name)
                       AND (uses_ansi_nulls = 0 OR uses_quoted_identifier = 0))
        PRINT CONCAT(@name, ': created with ANSI_NULLS or QUOTED_IDENTIFIER off. Left alone -- ask before changing it.');
    ELSE
    BEGIN
        SET @nTight  = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @tight,  N''))) / DATALENGTH(@tight);
        SET @nSpaced = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def, @spaced, N''))) / DATALENGTH(@spaced);
        -- The stored text opens with CREATE (or ALTER, once altered); that keyword becomes ALTER.
        SET @at      = PATINDEX(N'%[^' + NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) + N']%', @def);
        SET @len     = CASE WHEN SUBSTRING(@def, @at, 15) = N'CREATE OR ALTER' THEN 15
                            WHEN SUBSTRING(@def, @at, 6)  = N'CREATE'          THEN 6
                            WHEN SUBSTRING(@def, @at, 5)  = N'ALTER'           THEN 5
                            ELSE 0 END;

        IF @nTight <> @wantTight OR @nSpaced <> @wantSpaced
            PRINT CONCAT(@name, ': holds ', @nTight, ' + ', @nSpaced, ' entity predicates, not the ', @wantTight, ' + ', @wantSpaced,
                         ' read on 6 Oct 2026. It has changed. Left alone -- send its current text.');
        ELSE IF @len = 0
            PRINT CONCAT(@name, ': its text does not open with CREATE or ALTER. Left alone.');
        ELSE
        BEGIN
            -- One pass each; REPLACE never re-reads what it has just written. Every
            -- predicate sits after the keyword, so @at still points at it.
            SET @new = STUFF(REPLACE(REPLACE(@def, @tight, @rTight), @spaced, @rSpace), @at, @len, N'ALTER');

            IF @Apply = 0
                PRINT CONCAT(@name, ': checks passed; would widen ', @nTight + @nSpaced, ' predicates. NOTHING CHANGED.');
            ELSE
            BEGIN
                BEGIN TRANSACTION;
                    INSERT INTO Serviceconnect.dbo.MicroEazyCollectBoxHookBackup (DbName, ObjectName, DefinitionHash, Definition)
                    VALUES (DB_NAME(), @name, HASHBYTES('SHA2_256', @def), @def);
                    EXEC sys.sp_executesql @new;
                COMMIT TRANSACTION;

                IF CHARINDEX(@marker, OBJECT_DEFINITION(OBJECT_ID(@name))) > 0
                    PRINT CONCAT(@name, ': now shows Micromart Fintech to Micromart logins (', @nTight + @nSpaced, ' predicates).');
                ELSE
                    RAISERROR(N'%s: the ALTER ran but the change is not in the definition. Look before going further.', 16, 1, @name);
            END
        END
    END

    FETCH NEXT FROM targets INTO @name, @wanted, @wantTight, @wantSpaced;
END
CLOSE targets;
DEALLOCATE targets;
GO
