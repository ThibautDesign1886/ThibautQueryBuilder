-- =============================================================================
-- BACKFILL: Financial Ledger rows dated on/before 2025-07-01
-- Target: dbo.FinancialQueryBuilder_MasterTable
-- Source: dbo.ODS_CSI_Syteline_Financial_ledger_mst
-- Why:    The load that built the master table used WHERE trans_date > '2025-07-01',
--         so nothing before 2 Jul 2025 was ever loaded (e.g. TBUS 81000 Jan-Jul 2025).
-- Joins are scoped by site_ref (unscoped joins return every line 2x).
-- Step 1 is read-only. Run Step 2 only after Step 1 looks right.
-- =============================================================================

-- ── Step 1: preview (read-only) ─────────────────────────────────────────────
SELECT l.site_ref, COUNT(*) AS rows_to_load, SUM(l.dom_amount) AS net_domestic,
       MIN(l.trans_date) AS first_date, MAX(l.trans_date) AS last_date
FROM dbo.ODS_CSI_Syteline_Financial_ledger_mst AS l
WHERE l.trans_date <= '2025-07-01'
  AND NOT EXISTS (SELECT 1 FROM dbo.FinancialQueryBuilder_MasterTable AS m
                  WHERE m.Sequence = CAST(l.trans_num AS NVARCHAR(50)) AND m.Site = l.site_ref)
GROUP BY l.site_ref;

-- ── Step 2: load (uncomment to run) ─────────────────────────────────────────
/*
BEGIN TRAN;

INSERT INTO dbo.FinancialQueryBuilder_MasterTable (
    Sequence, Account, AccountUnit1, AccountUnit2, AccountUnit3, AccountUnit4, AccountDescription,
    TxnDate, Site, AllocationTransaction, Reference,
    DebitDomestic, CreditDomestic, ExchangeRate, DebitForeign, CreditForeign,
    PostedFrom, PostedFromSite, CustVendor, Name,
    InvoiceVoucher, Cancellation, InvoiceVchSeq, Hierarchy,
    ControlPrefix, ControlSite, ControlYear, ControlPeriod, ControlNumber,
    RefControlPrefix, RefControlSite, RefControlYear, RefControlPeriod, RefControlNumber,
    CheckNumber, CheckDate, Currency, BankCode, Consolidated
)
SELECT
    l.trans_num, l.acct, l.acct_unit1, l.acct_unit2, l.acct_unit3, l.acct_unit4, ch.description,
    l.trans_date, l.site_ref, CAST(NULL AS NVARCHAR(50)), l.ref,
    CASE WHEN l.dom_amount > 0 THEN  l.dom_amount ELSE 0 END,
    CASE WHEN l.dom_amount < 0 THEN -l.dom_amount ELSE 0 END,
    l.exch_rate,
    CASE WHEN l.for_amount > 0 THEN  l.for_amount ELSE 0 END,
    CASE WHEN l.for_amount < 0 THEN -l.for_amount ELSE 0 END,
    l.from_id, l.from_site, l.vend_num, COALESCE(c.name, v.name),
    l.voucher, l.cancellation, l.vouch_seq, l.hierarchy,
    l.control_prefix, l.control_site, l.control_year, l.control_period, l.control_number,
    l.ref_control_prefix, l.ref_control_site, l.ref_control_year, l.ref_control_period, l.ref_control_number,
    l.check_num, CAST(l.check_date AS DATE), l.curr_code, l.bank_code, l.consolidated
FROM dbo.ODS_CSI_Syteline_Financial_ledger_mst AS l
LEFT JOIN dbo.ODS_CSI_Syteline_Common_custaddr_mst AS c
    ON  c.site_ref = l.site_ref
    AND LTRIM(RTRIM(l.vend_num)) = LTRIM(RTRIM(c.cust_num))
    AND c.cust_seq = 0
LEFT JOIN dbo.ODS_CSI_Syteline_Common_vendaddr_mst AS v
    ON  v.site_ref = l.site_ref
    AND LTRIM(RTRIM(l.vend_num)) = LTRIM(RTRIM(v.vend_num))
LEFT JOIN dbo.ODS_CSI_Syteline_Common_chart_mst AS ch
    ON  ch.site_ref = l.site_ref
    AND ch.acct = l.acct
WHERE l.trans_date <= '2025-07-01'
  AND NOT EXISTS (SELECT 1 FROM dbo.FinancialQueryBuilder_MasterTable AS m
                  WHERE m.Sequence = CAST(l.trans_num AS NVARCHAR(50)) AND m.Site = l.site_ref);

-- Rows inserted should equal SUM(rows_to_load) from Step 1. If not: ROLLBACK;
SELECT @@ROWCOUNT AS rows_inserted;
-- COMMIT;  -- or ROLLBACK;
*/

-- ── Step 3: check the master table has no duplicate lines (read-only) ──────
SELECT Site, Sequence, COUNT(*) AS copies
FROM dbo.FinancialQueryBuilder_MasterTable
GROUP BY Site, Sequence
HAVING COUNT(*) > 1;
