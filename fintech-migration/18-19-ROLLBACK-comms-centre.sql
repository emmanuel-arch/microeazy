/*==========================================================================
  ROLLBACK for 18 (disbursement paybill) and 19 (comms centre).

  Each section restores a procedure from the text saved in
  dbo.MicroEazyProcBackup by the script that changed it. Run only the
  sections you need, in SSMS against Serviceconnect. Each one is off until
  its @Apply flag is set, and prints what it would do first.

    R1  sp_DisbursmentNotifications  -> as it was before 19's hook
                                        (18's correct paybill stays)
    R1b sp_DisbursmentNotifications  -> as it was before 18
                                        (PUTS THE WRONG PAYBILL BACK -- only
                                         if 18 itself has to be undone)
    R2  sp_FintechSmsReminders       -> the 28 Aug 2026 version (fixed wording)
    R3  drop dbo.sp_MicroEazy_DisbursementSms   (after R1 only)
    R4  drop the four tables         (loses the console's edits and the
                                      reminder history; normally keep them)
  ==========================================================================*/


/* -------------------------------------------------------------------------
   The restore routine, used by R1, R1b and R2: converts the saved
   "CREATE PROCEDURE" text to ALTER and runs it.
   ---------------------------------------------------------------------- */
USE Serviceconnect;
GO
CREATE OR ALTER PROCEDURE dbo.sp_MicroEazy_RestoreProc
    @ObjectName SYSNAME,
    @Script     VARCHAR(20),
    @Apply      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @def NVARCHAR(MAX), @savedAt DATETIME2(0), @at INT, @len INT, @new NVARCHAR(MAX);

    SELECT TOP 1 @def = Definition, @savedAt = SavedAt
      FROM dbo.MicroEazyProcBackup
     WHERE ProcName = @ObjectName AND Script = @Script
     ORDER BY Id;   -- the FIRST save by that script is the state before it

    IF @def IS NULL
    BEGIN
        RAISERROR(N'No text of %s saved by script %s. Nothing changed.', 16, 1, @ObjectName, @Script);
        RETURN;
    END

    SET @at  = PATINDEX(N'%[^' + NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) + N']%', @def);
    SET @len = CASE WHEN SUBSTRING(@def, @at, 15) = N'CREATE OR ALTER' THEN 15
                    WHEN SUBSTRING(@def, @at, 6)  = N'CREATE'          THEN 6
                    WHEN SUBSTRING(@def, @at, 5)  = N'ALTER'           THEN 5
                    ELSE 0 END;
    IF @len = 0
    BEGIN
        RAISERROR(N'The saved text does not open with CREATE or ALTER. Nothing changed.', 16, 1);
        RETURN;
    END
    SET @new = STUFF(@def, @at, @len, N'ALTER');

    IF @Apply = 0
    BEGIN
        PRINT CONCAT(N'Would restore ', @ObjectName, N' to the text saved by script ', @Script, N' at ', CONVERT(NVARCHAR(30), @savedAt, 120), N':');
        PRINT N'------------------------------------------------------------------';
        PRINT @new;
        PRINT N'------------------------------------------------------------------';
        PRINT N'NOTHING CHANGED. Set @Apply = 1 to restore it.';
        RETURN;
    END

    EXEC sys.sp_executesql @new;
    PRINT CONCAT(N'Restored ', @ObjectName, N' to the text saved by script ', @Script, N'.');
END
GO


/* R1 · sp_DisbursmentNotifications without 19's hook (18's paybill fix kept,
        because 19 saved the text AFTER 18). */
USE Serviceconnect;
GO
DECLARE @Apply BIT = 0;   -- <<< 1 to restore
EXEC dbo.sp_MicroEazy_RestoreProc @ObjectName = N'dbo.sp_DisbursmentNotifications', @Script = '19', @Apply = @Apply;
GO


/* R1b · sp_DisbursmentNotifications as it was before 18 -- the WRONG paybill
         (4038021) comes back with it. Only to undo 18 itself. */
USE Serviceconnect;
GO
DECLARE @Apply BIT = 0;   -- <<< 1 to restore
EXEC dbo.sp_MicroEazy_RestoreProc @ObjectName = N'dbo.sp_DisbursmentNotifications', @Script = '18', @Apply = @Apply;
GO


/* R2 · sp_FintechSmsReminders as it was before 19 (the fixed five messages). */
USE Serviceconnect;
GO
DECLARE @Apply BIT = 0;   -- <<< 1 to restore
EXEC dbo.sp_MicroEazy_RestoreProc @ObjectName = N'dbo.sp_FintechSmsReminders', @Script = '19', @Apply = @Apply;
GO


/* R3 · drop the renderer -- only once R1 has removed the call to it (the hook
        checks OBJECT_ID first, so dropping it early is harmless, merely
        pointless). */
USE Serviceconnect;
GO
DECLARE @Apply BIT = 0;   -- <<< 1 to drop
IF CHARINDEX(N'sp_MicroEazy_DisbursementSms', ISNULL(OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_DisbursmentNotifications')), N'')) > 0
    PRINT N'sp_DisbursmentNotifications still calls it -- run R1 first. Nothing changed.';
ELSE IF @Apply = 0
    PRINT N'Would drop dbo.sp_MicroEazy_DisbursementSms. NOTHING CHANGED. Set @Apply = 1.';
ELSE IF OBJECT_ID(N'dbo.sp_MicroEazy_DisbursementSms') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.sp_MicroEazy_DisbursementSms;
    PRINT N'Dropped dbo.sp_MicroEazy_DisbursementSms.';
END
GO


/* R4 · drop the tables. The console's edits and the reminder history go with
        them. Keep dbo.MicroEazyProcBackup until every restore above is done. */
USE Serviceconnect;
GO
DECLARE @Apply BIT = 0;   -- <<< 1 to drop
IF CHARINDEX(N'MicroEazySmsTemplate', ISNULL(OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_FintechSmsReminders')), N'')) > 0
    PRINT N'sp_FintechSmsReminders still reads the templates -- run R2 first. Nothing changed.';
ELSE IF @Apply = 0
    PRINT N'Would drop MicroEazySmsTemplate, MicroEazySmsSetting and MicroEazySmsReminderLog. NOTHING CHANGED. Set @Apply = 1.';
ELSE
BEGIN
    IF OBJECT_ID(N'dbo.MicroEazySmsTemplate')    IS NOT NULL DROP TABLE dbo.MicroEazySmsTemplate;
    IF OBJECT_ID(N'dbo.MicroEazySmsSetting')     IS NOT NULL DROP TABLE dbo.MicroEazySmsSetting;
    IF OBJECT_ID(N'dbo.MicroEazySmsReminderLog') IS NOT NULL DROP TABLE dbo.MicroEazySmsReminderLog;
    PRINT N'Dropped the comms-centre tables.';
END
GO
