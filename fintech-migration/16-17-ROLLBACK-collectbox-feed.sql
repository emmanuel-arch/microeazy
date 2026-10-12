/*==========================================================================
  ROLLBACK FOR 16 AND 17 — take Micromart Fintech back off the collection tracker feed.

  Each section takes out exactly what 16.4 / 17 put in, from the CURRENT
  text of the procedure -- so any change Micromart make to those procedures
  after the hook survives the rollback. If the inserted text is no longer
  there verbatim, the section refuses and tells you; the original text is in
  Serviceconnect.dbo.MicroEazyCollectBoxHookBackup if you need it by hand.

  What happens to the floor: Micromart's next run zeroes every Fintech
  amount (their resets cover every row) and nothing refills them, so the
  Fintech cases drop out of CallBox's lists -- the state of 6 Oct 2026. The
  tracker rows themselves stay, like the 1,690 that were there before; their
  call logs and promises point at them, so they are not deleted.

  Each section is dry by default: set its switch to 1 to apply.
  ==========================================================================*/


/* -------------------------------------------------------------------------
   R1 · Take the hook out of sp_GeneralCollectionTrackerbooks (undoes 16.4).
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 60000;

DECLARE @Apply BIT = 0;   -- <<< 1 = take the hook out

DECLARE @obj    INT           = OBJECT_ID(N'dbo.sp_GeneralCollectionTrackerbooks');
DECLARE @cur    NVARCHAR(MAX) = OBJECT_DEFINITION(@obj);
DECLARE @anchor NVARCHAR(200) = N'EXEC sp_GenerateCollectionTrackerDueLoansForCollectBox 3002';
DECLARE @crlf   NCHAR(2)      = NCHAR(13) + NCHAR(10);
DECLARE @hook NVARCHAR(MAX), @new NVARCHAR(MAX), @n INT, @at INT, @len INT;

-- Built exactly as 16.4 built it.
SET @hook = @anchor + @crlf + @crlf
    + N'-- Micro Eazy, 6 Oct 2026: Micromart Fintech (3005) is fed here by the same rules, in the same run.' + @crlf
    + N'-- A failure is logged in dbo.MicroEazyCollectBoxFeedLog and never stops the steps below.' + @crlf
    + N'BEGIN TRY' + @crlf
    + N'    EXEC dbo.sp_MicroEazy_FeedFintechToCollectBox @EntityId = 3005, @DryRun = 0, @Source = ''hook'';' + @crlf
    + N'END TRY' + @crlf
    + N'BEGIN CATCH' + @crlf
    + N'    PRINT ''Micro Eazy Fintech feed skipped: '' + ERROR_MESSAGE();' + @crlf
    + N'END CATCH' + @crlf;

IF @cur IS NULL OR CHARINDEX(N'sp_MicroEazy_FeedFintechToCollectBox', @cur) = 0
BEGIN
    PRINT N'R1: there is no Fintech hook in sp_GeneralCollectionTrackerbooks. Nothing to do.';
    RETURN;
END

SET @n = (DATALENGTH(@cur) - DATALENGTH(REPLACE(@cur, @hook, N''))) / DATALENGTH(@hook);
IF @n <> 1
BEGIN
    RAISERROR(N'R1: the hook is there but not as 16.4 wrote it (found %d exact copies). Nothing changed. Edit it out by hand; the pre-hook text is in dbo.MicroEazyCollectBoxHookBackup.', 16, 1, @n);
    RETURN;
END

-- The stored text opens with CREATE or ALTER; that keyword becomes ALTER.
SET @at  = PATINDEX(N'%[^' + NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) + N']%', @cur);
SET @len = CASE WHEN SUBSTRING(@cur, @at, 15) = N'CREATE OR ALTER' THEN 15
                WHEN SUBSTRING(@cur, @at, 6)  = N'CREATE'          THEN 6
                WHEN SUBSTRING(@cur, @at, 5)  = N'ALTER'           THEN 5
                ELSE 0 END;
IF @len = 0
BEGIN
    RAISERROR(N'R1: the master''s text does not open with CREATE or ALTER. Nothing changed.', 16, 1);
    RETURN;
END
SET @new = STUFF(REPLACE(@cur, @hook, @anchor), @at, @len, N'ALTER');

IF @Apply = 0
BEGIN
    PRINT N'R1: checks passed; the hook would come out. NOTHING CHANGED. Set @Apply = 1 to do it.';
    RETURN;
END

BEGIN TRANSACTION;
    EXEC sys.sp_executesql @new;
COMMIT TRANSACTION;

IF CHARINDEX(N'sp_MicroEazy_FeedFintechToCollectBox', OBJECT_DEFINITION(@obj)) = 0
    PRINT N'R1: hook removed. Micromart''s next run zeroes the Fintech amounts and leaves them.';
ELSE
    RAISERROR(N'R1: the ALTER ran but the hook is still there. Look before going further.', 16, 1);
GO


/* -------------------------------------------------------------------------
   R2 · Narrow the CallBox procedures 17 widened back to the user's own entity.
   ---------------------------------------------------------------------- */
USE CollectBox;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET LOCK_TIMEOUT 60000;

DECLARE @Apply BIT = 0;   -- <<< 1 = narrow them back

DECLARE @tight  NVARCHAR(60)  = N'L.EntityId=@EntityId';
DECLARE @spaced NVARCHAR(60)  = N'L.EntityId = @EntityId';
DECLARE @rTight NVARCHAR(200) = N'(L.EntityId=@EntityId OR (@EntityId = 3002 AND L.EntityId = 3005))';
DECLARE @rSpace NVARCHAR(200) = N'(L.EntityId = @EntityId OR (@EntityId = 3002 AND L.EntityId = 3005))';
DECLARE @marker NVARCHAR(60)  = N'@EntityId = 3002 AND L.EntityId = 3005';

DECLARE @name SYSNAME, @cur NVARCHAR(MAX), @new NVARCHAR(MAX), @at INT, @len INT;
DECLARE targets CURSOR LOCAL FAST_FORWARD FOR
    SELECT N'dbo.sp_NotReachable_CallsList' UNION ALL SELECT N'dbo.OverallDashboard';
OPEN targets;
FETCH NEXT FROM targets INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @cur = OBJECT_DEFINITION(OBJECT_ID(@name));
    IF @cur IS NULL OR CHARINDEX(@marker, @cur) = 0
        PRINT CONCAT(N'R2 ', @name, N': not widened. Nothing to do.');
    ELSE
    BEGIN
        SET @at  = PATINDEX(N'%[^' + NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) + N']%', @cur);
        SET @len = CASE WHEN SUBSTRING(@cur, @at, 15) = N'CREATE OR ALTER' THEN 15
                        WHEN SUBSTRING(@cur, @at, 6)  = N'CREATE'          THEN 6
                        WHEN SUBSTRING(@cur, @at, 5)  = N'ALTER'           THEN 5
                        ELSE 0 END;
        SET @new = STUFF(REPLACE(REPLACE(@cur, @rTight, @tight), @rSpace, @spaced), @at, @len, N'ALTER');

        IF @len = 0
            PRINT CONCAT(N'R2 ', @name, N': its text does not open with CREATE or ALTER. Left alone.');
        ELSE IF CHARINDEX(@marker, @new) > 0
            PRINT CONCAT(N'R2 ', @name, N': the widened predicates are not all as 17 wrote them. Left alone -- the original is in Serviceconnect.dbo.MicroEazyCollectBoxHookBackup.');
        ELSE IF @Apply = 0
            PRINT CONCAT(N'R2 ', @name, N': checks passed; would narrow it back. NOTHING CHANGED.');
        ELSE
        BEGIN
            BEGIN TRANSACTION;
                EXEC sys.sp_executesql @new;
            COMMIT TRANSACTION;
            PRINT CONCAT(N'R2 ', @name, N': back to the user''s own entity.');
        END
    END
    FETCH NEXT FROM targets INTO @name;
END
CLOSE targets;
DEALLOCATE targets;
GO


/* -------------------------------------------------------------------------
   R3 · OPTIONAL, after R1 — remove the feed procedure. The log and the
        backup tables are kept: they are the record of what ran and what was
        changed. Uncomment to run.
   ---------------------------------------------------------------------- */
-- USE Serviceconnect;
-- IF CHARINDEX(N'sp_MicroEazy_FeedFintechToCollectBox', OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_GeneralCollectionTrackerbooks'))) = 0
--     DROP PROCEDURE IF EXISTS dbo.sp_MicroEazy_FeedFintechToCollectBox;
-- ELSE
--     PRINT 'R3: the hook is still in the master. Run R1 first.';
GO
