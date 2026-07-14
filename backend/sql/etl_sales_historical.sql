-- ETL: Sales Invoices -- HISTORICAL LOAD
-- Scope: inv_date <= '2026-07-01'
-- Run once for the initial backfill. After this, use the incremental query.

WITH BaseInvoice AS (
    SELECT 
        hdr.site_ref,
        hdr.inv_num,
        hdr.inv_seq,
        hdr.inv_date,
        hdr.co_num,
        hdr.cust_num,
        hdr.cust_seq,
        hdr.slsman,
        hdr.exch_rate,
        hdr.disc_amount,
        hdr.misc_charges,
        hdr.freight,
        i.inv_line,
        i.item,
        i.co_num AS item_co_num,
        i.co_line,
        i.co_release,
        i.qty_invoiced,
        i.price,
        i.cost
    FROM dbo.ODS_CSI_Syteline_Common_inv_hdr_mst AS hdr
    INNER JOIN dbo.ODS_CSI_Syteline_Common_inv_item_mst AS i
        ON  i.site_ref = hdr.site_ref
        AND i.inv_num  = hdr.inv_num
        AND i.inv_seq  = hdr.inv_seq
    WHERE hdr.inv_date <= '2026-07-01'
)
SELECT
    -- ── Identifiers ──────────────────────────────────────────────────────────
    CONCAT(
        b.site_ref, '^',
        b.inv_num,  '^',
        b.inv_seq,  '^',
        b.inv_line
    ) AS TransactionID,
    b.site_ref  AS SiteID,

    -- ── Invoice ───────────────────────────────────────────────────────────────
    b.inv_num   AS InvoiceNumber,
    b.inv_seq   AS InvoiceSequence,      -- [ETL key — not exposed in frontend]
    b.inv_line  AS InvoiceLineNumber,
    b.inv_date  AS InvoiceDate,

    -- ── Sales Order ───────────────────────────────────────────────────────────
    b.co_num    AS SalesOrderNumber,
    b.co_line   AS SalesOrderLine,
    b.co_release AS SalesOrderRelease,

    -- ── Customer ──────────────────────────────────────────────────────────────
    b.cust_num  AS CustomerNumber,
    b.cust_seq  AS CustomerSequence,
    ca.name     AS CustomerName,         -- [ETL reference — not exposed in frontend]
    ca.curr_code AS CurrencyCode,
    ca.country  AS CustomerCountry,
    cust.customer_email_addr AS CustomerEmailAddress,
    cust.phone1 AS CustomerPhone,
    cust.cust_type AS CustomerGroup,
    cust.Uf_LocationArea AS CustomerLocationArea,
    cust.Uf_Ranking AS CustomerRanking,
    et.description AS CustomerEndType,
    cust.Uf_MasterAccountNumber AS MasterAccountNumber,
    cust.Uf_MasterAccountName   AS MasterAccountName,

    -- ── Ship To ───────────────────────────────────────────────────────────────
    ca.city     AS ShiptoCity,
    ca.addr1    AS ShiptoAddress1,
    ca.addr2    AS ShiptoAddress2,
    ca.state    AS ShiptoState,
    ca.zip      AS ShiptoZipCode,
    ca.county   AS ShiptoCounty,
    ca.ship_to_email AS ShipToEmailAddress,

    -- ── Bill To ───────────────────────────────────────────────────────────────
    billto.cust_num             AS BillToCustomerNumber,
    billto_address.name         AS BillToCustomerName,
    billto_address.addr1        AS BillToAddress1,
    billto_address.addr2        AS BillToAddress2,
    billto_address.city         AS BillToCity,
    billto_address.state        AS BillToState,
    billto_address.zip          AS BillToZIPPostalCode,
    billto_address.county       AS BillToCounty,
    billto_address.country      AS BillToCountry,
    billto_address.external_email_addr AS BillToExternalEmail,
    billto.phone1               AS BillToPhone,
    billto.pricecode            AS BillToPriceCode,
    price.description           AS BillToPriceCodeDescription,
    billto.terms_code           AS TermsCode,
    billto.Uf_Ranking           AS BillToRanking,

    -- ── Item & Product ────────────────────────────────────────────────────────
    b.item                      AS ItemNumber,
    it.description              AS ItemDescription,
    it.alt_item                 AS AlternateItemNumber,
    it.product_code             AS ProductCode,
    pc.description              AS ProductCodeDescription,
    it.p_m_t_code               AS PMTCode,
    it.Uf_AssociatedBook        AS AssociatedBook,
    it.Uf_ReleaseDate           AS LaunchDate,
    YEAR(it.Uf_ReleaseDate)     AS LaunchDateYear,
    it.family_code              AS FamilyCode,
    fc.description              AS FamilyCodeDescription,
    it.u_m                      AS UnitOfMeasure,
    um.description              AS UnitOfMeasureDescription,
    it.reservable               AS Reservable,
    it.stat                     AS ItemStatus,
    it.uf_itembrand             AS ItemBrand,
    pc.uf_producttype           AS ProductType,
    it.Uf_ItemColorCode         AS ColorCode,
    CASE
        WHEN it.product_code LIKE '%ARM' THEN 'Armani'
        WHEN it.product_code LIKE '%COR' THEN 'Coraggio'
        WHEN b.site_ref = 'RHUS'         THEN 'RHI'
        ELSE 'Thibaut'
    END AS Brand,
    CASE
        WHEN it.product_code LIKE '%ARM'  THEN 'Armani'
        WHEN it.product_code LIKE '%COR'  THEN 'Coraggio'
        WHEN b.site_ref = 'RHUS'          THEN 'RHI'
        WHEN it.family_code = 'Product'   THEN pc.uf_producttype
        ELSE it.family_code
    END AS Category,

    -- ── Other ─────────────────────────────────────────────────────────────────
    it.Uf_BookCollection        AS BookCollection,

    -- ── Salesperson & Manager ─────────────────────────────────────────────────
    b.slsman AS HistoricalSalespersonNumber,
    COALESCE(em.name,          ve.name)               AS HistoricalSalespersonName,
    COALESCE(em.email_addr,    ve.external_email_addr) AS HistoricalSalespersonEmail,
    manager.slsman AS SalesManagerNumber,
    COALESCE(manager_employee.name,       manager_vendor.name)               AS SalesManagerName,
    COALESCE(manager_employee.email_addr, manager_vendor.external_email_addr) AS SalesManagerEmail,

    -- ── Invoice (amounts) ─────────────────────────────────────────────────────
    b.qty_invoiced                                            AS InvoiceQuantity,
    b.qty_invoiced * b.price / NULLIF(b.exch_rate, 0)        AS InvoiceAmount,
    b.disc_amount   / NULLIF(b.exch_rate, 0)                  AS InvoiceDiscountAmount,

    -- ── Financials ────────────────────────────────────────────────────────────
    b.price                                                   AS UnitPrice,
    b.exch_rate                                               AS ExchangeRate,
    b.cost                                                    AS UnitCost,
    b.qty_invoiced * b.cost                                   AS CostAmount,
    coi.matl_cost                                             AS MaterialCost,
    (coi.price / NULLIF(b.exch_rate, 0)) - coi.matl_cost     AS ProductMaterialMargin,
    b.misc_charges  / NULLIF(b.exch_rate, 0)                  AS MiscellaneousCharges,
    b.freight       / NULLIF(b.exch_rate, 0)                  AS FreightAmount,

    -- ── ETL metadata (not in frontend) ────────────────────────────────────────
    'Facts_Invoice' AS OriginID,
    'Act'           AS ScenarioID
FROM BaseInvoice AS b
LEFT JOIN dbo.ODS_CSI_Syteline_Common_item_mst       AS it      ON it.site_ref      = b.site_ref      AND it.item          = b.item
LEFT JOIN dbo.ODS_CSI_Syteline_Common_prodcode_mst   AS pc      ON pc.site_ref      = it.site_ref     AND pc.product_code  = it.product_code
LEFT JOIN dbo.ODS_CSI_Syteline_Common_famcode_mst    AS fc      ON fc.site_ref      = it.site_ref     AND fc.family_code   = it.family_code
LEFT JOIN dbo.ODS_CSI_Syteline_Common_u_m_mst        AS um      ON um.site_ref      = it.site_ref     AND um.u_m           = it.u_m
LEFT JOIN dbo.ODS_CSI_Syteline_Common_customer_mst   AS cust    ON cust.site_ref    = b.site_ref      AND LTRIM(cust.cust_num)    = LTRIM(b.cust_num)    AND cust.cust_seq    = b.cust_seq
LEFT JOIN dbo.ODS_CSI_Syteline_Common_custaddr_mst   AS ca      ON ca.site_ref      = b.site_ref      AND LTRIM(ca.cust_num)      = LTRIM(b.cust_num)    AND ca.cust_seq      = b.cust_seq
LEFT JOIN dbo.ODS_CSI_Syteline_Common_customer_mst   AS billto  ON billto.site_ref  = b.site_ref      AND LTRIM(billto.cust_num)  = LTRIM(b.cust_num)    AND billto.cust_seq  = 0
LEFT JOIN dbo.ODS_CSI_Syteline_Common_custaddr_mst   AS billto_address ON billto_address.site_ref = billto.site_ref AND LTRIM(billto_address.cust_num) = LTRIM(billto.cust_num) AND billto_address.cust_seq = 0
LEFT JOIN dbo.ODS_CSI_Syteline_Common_endtype_mst    AS et      ON et.site_ref      = cust.site_ref   AND et.end_user_type = cust.end_user_type
LEFT JOIN dbo.ODS_CSI_Syteline_Common_pricecode_mst  AS price   ON price.site_ref   = billto.site_ref AND price.pricecode   = billto.pricecode
LEFT JOIN dbo.ODS_CSI_Syteline_Common_coitem_mst     AS coi     ON coi.site_ref     = b.site_ref      AND coi.co_num       = b.item_co_num AND coi.co_line = b.co_line AND coi.co_release = b.co_release
LEFT JOIN dbo.ODS_CSI_Syteline_Common_slsman_mst     AS sl      ON sl.site_ref      = b.site_ref      AND sl.slsman        = b.slsman
LEFT JOIN dbo.ODS_CSI_Syteline_Common_employee_mst   AS em      ON em.site_ref      = sl.site_ref     AND em.emp_num       = sl.ref_num
LEFT JOIN dbo.ODS_CSI_Syteline_Common_vendaddr_mst   AS ve      ON ve.site_ref      = sl.site_ref     AND ve.vend_num      = sl.ref_num
LEFT JOIN dbo.ODS_CSI_Syteline_Common_slsman_mst     AS manager ON manager.site_ref = sl.site_ref     AND manager.slsman   = sl.slsmangr
LEFT JOIN dbo.ODS_CSI_Syteline_Common_employee_mst   AS manager_employee ON manager_employee.site_ref = manager.site_ref AND manager_employee.emp_num = manager.ref_num
LEFT JOIN dbo.ODS_CSI_Syteline_Common_vendaddr_mst   AS manager_vendor   ON manager_vendor.site_ref   = manager.site_ref AND manager_vendor.vend_num   = manager.ref_num
ORDER BY
    b.inv_date ASC,
    b.site_ref,
    b.inv_num,
    b.inv_seq,
    b.inv_line;
