/* ============================================================================
   14 · RETURN THE TWO CUSTOMERS WHO BORROWED MID-ROLLBACK

   Both were in the 175 that 12-rollback-wrong-dormancy.sql returned to Micromart
   Africa. Both had received the 02:34 SMS telling them they could now borrow from
   home, and both acted on it during the day -- before the 15:45 rollback pulled
   them back to 3002 together with the loan they had just taken.

   Each now holds a MICRO EAZY PRODUCT ON THE MICROMART AFRICA BOOK:

     132369  loan 450567  Micro Chap Chap (product 30221, entity 3005)
                          DISBURSED 11 Sep 13:02, KES 7,000 outstanding,
                          due 2026-10-09. Real money, live exposure.
     116744  loan 450461  Micro Eazy (product 30219, entity 3005)
                          KES 9,125, approval stage 2058, NOT disbursed.
                          No money has moved yet.

   Neither loan will report correctly where it is: the product belongs to 3005,
   the loan is stamped 3002, and the product's rollover configuration does not
   match the book it is sitting on. These two customers demonstrated by their own
   action that they are fintech customers, so the cleaner correction is to let the
   original move stand for them rather than to unwind their borrowing.

   Tonight's 02:30 job will NOT pick either of them up in any case -- both now have
   an open loan, and the corrected rule requires every loan settled. So this is not
   urgent, but it should be done before either loan is worked by a branch officer.

   -- WHY THE FLAGS ARE SET THE WAY THEY ARE ---------------------------------
   @AllowOpenLoans = 1   Required. The procedure refuses an open loan by default
                         precisely because moving a live balance between books is
                         an accounting event. Here that is the intent: the loan is
                         a 3005 product and belongs on the 3005 book. Geoffrey
                         should know it is happening.
   @SendSms   = 0        They already received the move SMS at 02:34 this morning,
   @SendEmail = 0        and for these two it was correct -- they are going to
                         fintech. A second identical message would only confuse.

   -- ONE SIDE EFFECT TO EXPECT ----------------------------------------------
   Like the nightly job, this NULLs UssdPin and MobileAppPassword.
     132369 is already NULL -- no change.
     116744 HAS A PIN SET. They set it after this morning's move and used it to
            apply for their loan; this will wipe it and they will be asked to
            choose a new one on their next dial. Unavoidable -- BCrypt cannot be
            computed in T-SQL -- but they should not be surprised by it.

   Preflight checked live 11 Sep 2026: neither customer collides with an existing
   identity on 3005, so script 05's lock will not reject either move.

   RUN THE DRY RUNS FIRST. Both default to @DryRun = 1.
   ==========================================================================*/
USE Serviceconnect;
GO

/* -------------------------------------------------------------------------
   STEP 1 · DRY RUN -- reports, changes nothing. Read both before going on.
   ---------------------------------------------------------------------- */
EXEC dbo.sp_MicroEazy_MoveCustomerToFintech
     @BorrowerId     = 132369,
     @AllowOpenLoans = 1;
GO

EXEC dbo.sp_MicroEazy_MoveCustomerToFintech
     @BorrowerId     = 116744,
     @AllowOpenLoans = 1;
GO


/* -------------------------------------------------------------------------
   STEP 2 · THE REAL MOVES. Run these only after the dry runs look right.
   ---------------------------------------------------------------------- */

/* 132369 -- Micro Chap Chap loan 450567, KES 7,000 disbursed and live */
EXEC dbo.sp_MicroEazy_MoveCustomerToFintech
     @BorrowerId     = 132369,
     @DryRun         = 0,
     @AllowOpenLoans = 1,
     @SendSms        = 0,
     @SendEmail      = 0,
     @Reason         = N'Borrowed on the fintech book (Micro Chap Chap 450567, KES 7,000 disbursed 11 Sep) before the dormancy rollback returned them to 3002. Returning the customer to the book their live product belongs to.';
GO

/* 116744 -- Micro Eazy loan 450461, applied for, not yet disbursed */
EXEC dbo.sp_MicroEazy_MoveCustomerToFintech
     @BorrowerId     = 116744,
     @DryRun         = 0,
     @AllowOpenLoans = 1,
     @SendSms        = 0,
     @SendEmail      = 0,
     @Reason         = N'Applied for a fintech product (Micro Eazy 450461, not yet disbursed) before the dormancy rollback returned them to 3002. Returning the customer so the application is worked by the fintech desk.';
GO


/* -------------------------------------------------------------------------
   STEP 3 · PROOF. Both rows should read 3005 / 3005 / ok.
   ---------------------------------------------------------------------- */
SELECT b.ID AS BorrowerId, b.PhoneNumber,
       b.EntityId AS BorrowerBook, b.EntityUnit, b.EntityAgent,
       l.id AS LoanId, l.EntityId AS LoanBook,
       p.ProductName, p.EntityId AS ProductBook,
       l.LoanBalance, l.LoanCleared,
       CASE WHEN p.EntityId = l.EntityId AND l.EntityId = b.EntityId
            THEN 'ok' ELSE 'MISMATCH' END AS Alignment
FROM dbo.Borrowers b
JOIN dbo.Loans l    ON l.BorrowerId = b.ID
LEFT JOIN dbo.Products p ON p.ID = l.ProductId
WHERE b.ID IN (132369, 116744)
  AND (l.LoanCleared = 0 OR ISNULL(l.LoanBalance,0) > 0)
ORDER BY b.ID;

/* and nothing of theirs should be left behind on 3002 */
SELECT 'rows still on 3002 for these two (should be 0)' AS check_,
 (SELECT COUNT(*) FROM dbo.Loans l WHERE l.BorrowerId IN (132369,116744) AND l.EntityId <> 3005) AS Loans_,
 (SELECT COUNT(*) FROM dbo.Loans l JOIN dbo.CustomerStatement cs ON cs.LoanId = l.id
   WHERE l.BorrowerId IN (132369,116744) AND cs.EntityId <> 3005)                                AS Statement_,
 (SELECT COUNT(*) FROM dbo.Loans l JOIN dbo.loanSchedule s ON s.Loanid = l.id
   WHERE l.BorrowerId IN (132369,116744) AND s.EntityId <> 3005)                                 AS Schedule_;
GO
