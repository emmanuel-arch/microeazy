/* ============================================================================
   06 · FIX sp_restBorrowerPin

   -- THE BUG ---------------------------------------------------------------
   The procedure selects the borrower's entity into @entityId on one line and
   then writes the literal 3002 into the SMS row four lines later:

       insert into Notifications.dbo.SMS(smsMessage,smsto,EntityId,...)
       values(@sms,@Phone,3002,GETDATE(),0,getdate(),5)
                          ^^^^

   So EVERY borrower PIN reset in the database -- Micromart Fintech customers
   included -- is stamped as Micromart Africa. Verified on 8 Sep 2026: SMS row
   2767547 reads "Dear Emmanuel Your MICROMART FINTECH Pin has been reset",
   correct lender name, and carries EntityId 3002.

   -- SECOND BUG -------------------------------------------------------------
   @sms is built by concatenation without ISNULL. A borrower with a NULL
   firstName produces a NULL message, and the row is inserted as NULL rather
   than failing -- a silent no-SMS. The trim also removes the double space seen
   in older messages ("Dear Mr  Your ..."), which came from records whose
   firstName was literally 'Mr '.

   -- WHAT IS NOT CHANGED -----------------------------------------------------
   The signature, the hashing (done by the caller), the BorrowerComments audit
   row, and the target table. Behaviour is identical except for the two fixes.

   Reversible: the original body is at the bottom of this file.
   ==========================================================================*/
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_restBorrowerPin]
    @BorrowerId INT,
    @PlainPin   INT,
    @HashedPin  VARCHAR(MAX),
    @DoneBy     INT,
    @Comment    VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sms        VARCHAR(MAX),
            @FirstName  VARCHAR(100),
            @Phone      VARCHAR(15),
            @entityId   INT,
            @EntityName VARCHAR(100);

    SELECT @FirstName = firstName,
           @Phone     = PhoneNumber,
           @entityId  = EntityId
    FROM dbo.Borrowers
    WHERE ID = @BorrowerId;

    IF @entityId IS NULL
    BEGIN
        RAISERROR('sp_restBorrowerPin: borrower %d does not exist.', 16, 1, @BorrowerId);
        RETURN;
    END

    SET @EntityName = (SELECT EntityName FROM dbo.BsEntity WHERE ID = @entityId);

    -- ISNULL + LTRIM/RTRIM: a NULL or padded first name must not blank or
    -- double-space the whole message.
    SET @sms = 'Dear ' + LTRIM(RTRIM(ISNULL(@FirstName, 'Customer')))
             + ' Your ' + LTRIM(RTRIM(ISNULL(@EntityName, 'Micromart')))
             + ' Pin has been reset.Your new PIN is ' + CONVERT(VARCHAR, @PlainPin)
             + '.Remember PIN yako ni siri Yako.';

    UPDATE dbo.Borrowers SET UssdPin = @HashedPin WHERE ID = @BorrowerId;

    INSERT INTO Notifications.dbo.SMS
        (smsMessage, smsto, EntityId, CreateDate, isSent, ScheduleDate, SmsProviderId)
    VALUES
        (@sms, @Phone, @entityId, GETDATE(), 0, GETDATE(), 5);
    --                ^^^^^^^^^ was the literal 3002

    INSERT INTO dbo.BorrowerComments (borroweId, Comment, CreatedBy, DateCreated)
    VALUES (@BorrowerId, @Comment, @DoneBy, GETDATE());
END
GO

PRINT '06 complete. PIN reset SMS is now stamped with the borrower''s own entity.';
GO

/* ============================================================================
   ROLLBACK -- the original body, exactly as it stood on 8 September 2026.
   Uncomment and run only if you need to put it back.
   ============================================================================
CREATE OR ALTER Procedure [dbo].[sp_restBorrowerPin]
@BorrowerId INT
,@PlainPin INT
,@HashedPin VARCHAR(MAX)
,@DoneBy INT
,@Comment varchar(max)
as
BEGIN
Declare @sms varchar(max),@FirstName varchar(100),@Phone varchar(15),@entityId INT,@EntityName varchar(100)

select @FirstName=firstName,@Phone=PhoneNumber,@entityId=EntityId from Borrowers  WHERE ID=@BorrowerId

SET @EntityName=(SELECT EntityName FROM BsEntity WHERE ID=@entityId)
SET @sms='Dear '+@FirstName+ ' Your '+@EntityName+' Pin has been reset.Your new PIN is '+convert(varchar,@PlainPin)+'.Remember PIN yako ni siri Yako.'

UPDATE Borrowers SET UssdPin=@HashedPin where id=@BorrowerId

insert into Notifications.dbo.SMS(smsMessage,smsto,EntityId,CreateDate,isSent,ScheduleDate,SmsProviderId)
values(@sms,@Phone,3002,GETDATE(),0,getdate(),5)

INSERT INTO BorrowerComments(borroweId,Comment,CreatedBy,DateCreated)VALUES(@BorrowerId,@Comment,@DoneBy,GETDATE())
END
============================================================================ */
