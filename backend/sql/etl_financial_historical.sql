-- =============================================================================
-- ETL: Financial Ledger -- HISTORICAL LOAD
-- Target: dbo.FinancialQueryBuilder_MasterTable
-- Source: dbo.ODS_CSI_Syteline_Financial_ledger_mst
-- Scope:  trans_date <= '2026-07-01'
-- Run once for the initial backfill. After this, use the incremental query.
-- =============================================================================

SELECT
    -- ── Account ───────────────────────────────────────────────────────────────
    l.trans_num                                     AS Sequence,
    l.acct                                          AS Account,
    l.acct_unit1                                    AS AccountUnit1,
    l.acct_unit2                                    AS AccountUnit2,
    l.acct_unit3                                    AS AccountUnit3,
    l.acct_unit4                                    AS AccountUnit4,
    ch.description                                  AS AccountDescription,

    -- ── Transaction ───────────────────────────────────────────────────────────
    l.trans_date                                    AS TxnDate,
    l.site_ref                                      AS Site,
    CAST(NULL AS NVARCHAR(50))                      AS AllocationTransaction,  -- no source column; reserved for future mapping
    l.ref                                           AS Reference,

    -- ── Amounts ───────────────────────────────────────────────────────────────
    CASE WHEN l.dom_amount > 0 THEN  l.dom_amount ELSE 0 END  AS DebitDomestic,
    CASE WHEN l.dom_amount < 0 THEN -l.dom_amount ELSE 0 END  AS CreditDomestic,
    l.exch_rate                                     AS ExchangeRate,
    CASE WHEN l.for_amount > 0 THEN  l.for_amount ELSE 0 END  AS DebitForeign,
    CASE WHEN l.for_amount < 0 THEN -l.for_amount ELSE 0 END  AS CreditForeign,

    -- ── Posting ───────────────────────────────────────────────────────────────
    l.from_id                                       AS PostedFrom,
    l.from_site                                     AS PostedFromSite,

    -- ── Vendor & Customer ─────────────────────────────────────────────────────
    l.vend_num                                      AS CustVendor,
    COALESCE(c.name, v.name)                        AS Name,

    -- ── Invoice ───────────────────────────────────────────────────────────────
    l.voucher                                       AS InvoiceVoucher,
    l.cancellation                                  AS Cancellation,
    l.vouch_seq                                     AS InvoiceVchSeq,

    -- ── Hierarchy ─────────────────────────────────────────────────────────────
    l.hierarchy                                     AS Hierarchy,

    -- ── Control ───────────────────────────────────────────────────────────────
    l.control_prefix                                AS ControlPrefix,
    l.control_site                                  AS ControlSite,
    l.control_year                                  AS ControlYear,
    l.control_period                                AS ControlPeriod,
    l.control_number                                AS ControlNumber,

    -- ── Ref Control ───────────────────────────────────────────────────────────
    l.ref_control_prefix                            AS RefControlPrefix,
    l.ref_control_site                              AS RefControlSite,
    l.ref_control_year                              AS RefControlYear,
    l.ref_control_period                            AS RefControlPeriod,
    l.ref_control_number                            AS RefControlNumber,

    -- ── Payment ───────────────────────────────────────────────────────────────
    l.check_num                                     AS CheckNumber,
    CAST(l.check_date AS DATE)                      AS CheckDate,
    l.curr_code                                     AS Currency,
    l.bank_code                                     AS BankCode,
    l.consolidated                                  AS Consolidated

FROM dbo.ODS_CSI_Syteline_Financial_ledger_mst AS l
LEFT JOIN dbo.ODS_CSI_Syteline_Common_custaddr_mst AS c
    ON  LTRIM(RTRIM(l.vend_num)) = LTRIM(RTRIM(c.cust_num))
    AND c.cust_seq = 0
LEFT JOIN dbo.ODS_CSI_Syteline_Common_vendaddr_mst AS v
    ON  LTRIM(RTRIM(l.vend_num)) = LTRIM(RTRIM(v.vend_num))
LEFT JOIN dbo.ODS_CSI_Syteline_Common_chart_mst AS ch
    ON  ch.acct = l.acct
WHERE l.trans_date <= '2026-07-01'
ORDER BY
    l.trans_date ASC,
    l.site_ref,
    l.control_number,
    l.acct;
