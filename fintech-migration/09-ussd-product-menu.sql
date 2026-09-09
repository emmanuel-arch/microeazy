/* ============================================================================
   09 · MAKE MICRO CHAP CHAP REACHABLE FROM USSD

   -- WHAT IS WRONG -----------------------------------------------------------
   Read live on 9 September 2026, the three Micromart Fintech products:

     ID     Product              CategoryId  UssdOrder  EntityUnits
     30219  Micro Eazy           2           1          0,129
     30220  Micro Eazy Monthly   3           1          0,129
     30221  Micro Chap Chap      NULL        NULL       129

   Micro Chap Chap can never appear on the USSD menu, for two independent
   reasons, and both are data:

     1. sp_ussdGetproducts filters `WHERE ... CategoryId = @CategoryId`.
        In SQL, NULL = anything is UNKNOWN, never TRUE. A product with no
        category matches no category — including the one the customer picked.

     2. The menu is rendered as `{UssdOrder}) {ProductName}`, and the customer's
        next keypress is matched against UssdOrder. A NULL there prints an empty
        selector — ") Micro Chap Chap" — which nothing can be typed to choose.

   So the smallest product on the fintech shelf, the KES 5,000-10,900 one that
   a new app customer is most likely to want, is invisible on the channel most
   of them use. No code change fixes this; the row is simply incomplete.

   -- THE CATEGORY IS A BUSINESS CALL ------------------------------------------
   This script puts it in 2 (BUSINESS LOAN-WEEKLY) because its term is 10 weeks,
   the same as Micro Eazy, which is already in 2. If Micromart would rather it
   sat in its own category, change @CategoryId below — but it must not stay NULL.

   Rows touched: 1.  Reversible: yes, at the bottom.
   ==========================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ProductId  INT = 30221;   -- Micro Chap Chap
DECLARE @CategoryId INT = 2;       -- BUSINESS LOAN-WEEKLY
DECLARE @UssdOrder  INT = 2;       -- Micro Eazy is 1 in this category

/* -- before -- */
SELECT 'before' AS stage, p.ID, p.ProductName, p.CategoryId, c.CategoryName,
       p.UssdOrder, p.EntityUnits, p.IsActive, p.IsUssdMobileEnabled
FROM dbo.Products p LEFT JOIN dbo.ProductCategories c ON c.ID = p.CategoryId
WHERE p.EntityId = 3005 ORDER BY p.ID;

IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE ID = @ProductId AND EntityId = 3005)
BEGIN RAISERROR('Product %d is not on entity 3005. Check the id before running.', 16, 1, @ProductId); RETURN; END

/* -- no two products in one category may share a selector, or the second is
      unreachable in exactly the same way -- */
IF EXISTS (SELECT 1 FROM dbo.Products
           WHERE EntityId = 3005 AND CategoryId = @CategoryId
             AND UssdOrder = @UssdOrder AND ID <> @ProductId)
BEGIN
    RAISERROR('UssdOrder %d is already used in category %d on entity 3005. Pick another.', 16, 1, @UssdOrder, @CategoryId);
    RETURN;
END

BEGIN TRANSACTION;

    IF OBJECT_ID('dbo.FintechRemediationBackup_20260908') IS NOT NULL
    BEGIN
        INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
        SELECT '09-ussd-menu', 'Products', ID, 'CategoryId',
               CAST(CategoryId AS NVARCHAR(200)), CAST(@CategoryId AS NVARCHAR(200))
        FROM dbo.Products WHERE ID = @ProductId;

        INSERT dbo.FintechRemediationBackup_20260908 (Phase, TableName, KeyValue, ColumnName, OldValue, NewValue)
        SELECT '09-ussd-menu', 'Products', ID, 'UssdOrder',
               CAST(UssdOrder AS NVARCHAR(200)), CAST(@UssdOrder AS NVARCHAR(200))
        FROM dbo.Products WHERE ID = @ProductId;
    END

    UPDATE dbo.Products
       SET CategoryId  = @CategoryId,
           UssdOrder   = @UssdOrder,
           UpdatedBy   = 9096,
           UpdatedDate = GETDATE()
     WHERE ID = @ProductId AND EntityId = 3005;

COMMIT TRANSACTION;

/* -- after: all three products should now carry a category and a selector -- */
SELECT 'after' AS stage, p.ID, p.ProductName, p.CategoryId, c.CategoryName,
       p.UssdOrder, p.EntityUnits, p.IsActive, p.IsUssdMobileEnabled
FROM dbo.Products p LEFT JOIN dbo.ProductCategories c ON c.ID = p.CategoryId
WHERE p.EntityId = 3005 ORDER BY p.ID;

PRINT '09 complete. Micro Chap Chap is now reachable from the USSD menu.';

/* ============================================================================
   ROLLBACK
   ============================================================================
UPDATE dbo.Products SET CategoryId = NULL, UssdOrder = NULL WHERE ID = 30221;
============================================================================ */
