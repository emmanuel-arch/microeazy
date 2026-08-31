# Build log — 29 Aug 2026 · 4 days to the Micromart demo

Three suites, all green, all against LIVE production databases:
`npm run test:realms` **47/47** · `npm run test:analytics-live` **64/64** ·
`npm run test:reporting` **35/35**. `tsc`, `eslint` and `next build` clean.

## 1. Realm Switch (SME <-> Fintech) — DONE
Segmented control at the top of the console, sliding thumb, veil + spinner, whole
console re-paints. Micromart's mark is two colours, so the two books are the two
colours: gold `#E6B617` (SME, darkened to `#8C6512`) and espresso `#4E4442`
(Fintech, inherits the org brand so today's look is untouched). Axe added:
Boresha `#0403F3`, Stawi `#056639`.

## 2. Analytics on live data — DONE
Postgres held a 199-loan Micromart book; 14 of 15 surfaces were asking it. All
four books now read live through the SQL relay:

| Book | Entity | OLB | Disbursed 90d | Collected 90d | PAR 30 |
| --- | --- | --- | --- | --- | --- |
| Micromart SME | 3002 | KES 350.6M | 282.4M | 180.5M | 79.1% |
| Micromart Fintech | 3005 | KES 0.92M | 1.39M | 0.04M | 0.0% |
| Axe Boresha | 3003 | KES 124.5M | 211.7M | 185.7M | 45.9% |
| Axe Stawi | 3004 | KES 8.75M | 1.31M | 2.29M | 83.2% |

Book selector on all 15 surfaces (one book / combined / side by side).
Side-by-side is DRAWN on the board view; gated elsewhere by `canSplit`.

## 3. Analytics & Reporting — DONE (this session)
- [x] Generic verdict banner removed from the board view
- [x] `analytics.jpg` behind every analytics page, under a scrim
- [x] Rebranded "Analytics Studio" -> "Analytics & Reporting" (16 files)
- [x] `lib/reporting/` — types, 11 report definitions, runner, naming, exports
- [x] `/analytics/reports` — browse, read on screen, then export
- [x] Excel (exceljs), PDF (pdfkit), CSV, chart PNG, copy-link
- [x] File naming: `Lender_Book_Report_Period_When.ext`
- [x] `/console/report`, `/console/report/income` redirect here; console nav points here

Reports live and verified on BOTH servers: Disbursement, OLB, Loans due, M-Pesa
payments, List of customers, Arrears, PAR by branch, NPL, Collection report,
Vintage analysis, Officer book.

## Their reports, checked — what is actually wrong

1. **`sp_arrearsLoans` returned ONE row** for a 30-day window on a book carrying
   64,238 loans more than 30 days past due. It applies the date range to a
   POSITION. Ours is a stock and returns the whole arrears book.
2. **`sp_MpesaReport` joins payments to borrowers on a rebuilt phone string** —
   `'254' + RIGHT(BillRefNumber,9) = PhoneNumber`. 13 numbers exist in BOTH
   Micromart books belonging to DIFFERENT people, so a receipt can attach to the
   wrong human; and any reference that is an account number rather than a phone
   is silently dropped. Ours matches `CustomerStatement.MpesaRef -> Loans`.
   (`payments.LoanId` exists but is NULL on all 193,673 rows, which is *why*
   they join on phone.)
3. **`sp_cpr2` returned AmountPaid, UnpaidAmount and % as NULL** while showing
   Arrears of 155,625.26 — a collection report with no collection in it.
4. **Catalogue defects**: module 1019 is named "NPL Collected" but runs
   `sp_DeclinedLoansReport`; module 1066 "NPL Collected" has ReportQuery
   `"NPL Collected"`, which is not a procedure; module 8 has no name; two
   different "End of Day" entries run different procedures.
5. **Arrears source corrected on our side too.** We were using
   CollectBox.CollectionTracker (3002 only) with a derived fallback — two
   different PARs in one comparison. `Transactions.dbo.LoansInArrears` covers
   every book on both servers, and it revealed the fintech book is NOT clean:
   657 loans over 30 days, not zero. SME PAR30 moved 66.3% -> 79.1% on the
   better source.

## Two constraints worth remembering
- **The relay refuses stored procedures** (403 on every `proc`). Their reports
  cannot be run from production at all — hence rebuilding rather than calling.
- **Their reports cannot be asked for a book.** Every SP reads
  `UserMaster.EntityID` for the caller, so it reports on whichever entity that
  user last switched into. Run as Morris they returned the FINTECH unit.

## Next
- [ ] Pivot Explorer — the build-your-own-chart layer (rebrand done, upgrade not)
- [ ] Port the Riri metric-composer at `/console/intelligence/reports` into it —
      still live at its old URL, NOT yet merged
- [ ] Side-by-side drawing on the remaining 13 surfaces (data + control ready)
- [ ] FINANCE reports (income statement) — category exists, no definitions yet
- [ ] A parity script running theirs beside ours, once the relay allows procs
- [ ] The business-value narrative for Morris
