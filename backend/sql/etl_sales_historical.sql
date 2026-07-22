-- ETL: Sales Invoices -- HISTORICAL LOAD
-- Scope: inv_date <= '2026-07-01'
-- Run once for the initial backfill. After this, use the incremental query.
--
-- FIX: inv_seq removed from the inv_item_mst join condition.
-- In Syteline, items can exist on inv_seq = 0 even when the header record
-- was later resequenced (credit memo, adjustment). Joining on inv_seq caused
-- those item rows to be silently dropped, producing a lower InvoiceAmount
-- than the source sum.

WITH FiscalPeriods AS (
    SELECT site_ref, fiscal_year, 1  AS fiscalPeriod, CAST(per_start1  AS DATE) AS PeriodStart, CAST(per_end1  AS DATE) AS PeriodEnd FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 2,  CAST(per_start2  AS DATE), CAST(per_end2  AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 3,  CAST(per_start3  AS DATE), CAST(per_end3  AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 4,  CAST(per_start4  AS DATE), CAST(per_end4  AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 5,  CAST(per_start5  AS DATE), CAST(per_end5  AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 6,  CAST(per_start6  AS DATE), CAST(per_end6  AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 7,  CAST(per_start7  AS DATE), CAST(per_end7  AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 8,  CAST(per_start8  AS DATE), CAST(per_end8  AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 9,  CAST(per_start9  AS DATE), CAST(per_end9  AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 10, CAST(per_start10 AS DATE), CAST(per_end10 AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 11, CAST(per_start11 AS DATE), CAST(per_end11 AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 12, CAST(per_start12 AS DATE), CAST(per_end12 AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
    UNION ALL
    SELECT site_ref, fiscal_year, 13, CAST(per_start13 AS DATE), CAST(per_end13 AS DATE) FROM dbo.ODS_CSI_Syteline_Common_periods_mst WHERE isDeleted = 0 AND site_ref = 'TBUS'
),
BaseInvoice AS (
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
        i.co_num     AS item_co_num,
        i.co_line,
        i.co_release,
        i.qty_invoiced,
        i.price,
        i.cost
    FROM dbo.ODS_CSI_Syteline_Common_inv_hdr_mst AS hdr
    INNER JOIN dbo.ODS_CSI_Syteline_Common_inv_item_mst AS i
        ON  i.site_ref = hdr.site_ref
        AND i.inv_num  = hdr.inv_num
        -- inv_seq intentionally excluded: items may be on seq 0 while the header
        -- carries a later sequence (adjustment/credit memo).
    WHERE hdr.inv_date <= '2026-07-01'
)
SELECT
    -- ── Identifiers ──────────────────────────────────────────────────────────
    CONCAT(b.site_ref, '^', b.inv_num, '^', b.inv_seq, '^', b.inv_line, '^', b.co_num, '^', CAST(b.co_line AS VARCHAR(10))) AS TransactionID,
    b.site_ref  AS SiteID,

    -- ── Invoice ───────────────────────────────────────────────────────────────
    b.inv_num   AS InvoiceNumber,
    b.inv_seq   AS InvoiceSequence,
    b.inv_line  AS InvoiceLineNumber,
    b.inv_date  AS InvoiceDate,

    -- ── Invoice Fiscal Calendar ───────────────────────────────────────────────
    fp.fiscal_year AS InvoiceFiscalYear,
    CASE
        WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod IN (5, 6) THEN 5
        WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod >= 7      THEN fp.fiscalPeriod - 1
        ELSE fp.fiscalPeriod
    END AS InvoiceFiscalPeriodNumber,
    CASE
        WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod IN (5, 6) THEN 'May'
        WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod >= 7
            THEN DATENAME(MONTH, DATEFROMPARTS(2000, fp.fiscalPeriod - 1, 1))
        WHEN fp.fiscalPeriod = 13 THEN 'December'
        ELSE DATENAME(MONTH, DATEFROMPARTS(2000, fp.fiscalPeriod, 1))
    END AS InvoiceFiscalPeriod,
    CASE
        WHEN CASE WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod IN (5, 6) THEN 5
                  WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod >= 7      THEN fp.fiscalPeriod - 1
                  ELSE fp.fiscalPeriod END BETWEEN 1 AND 3  THEN 'Q1'
        WHEN CASE WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod IN (5, 6) THEN 5
                  WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod >= 7      THEN fp.fiscalPeriod - 1
                  ELSE fp.fiscalPeriod END BETWEEN 4 AND 6  THEN 'Q2'
        WHEN CASE WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod IN (5, 6) THEN 5
                  WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod >= 7      THEN fp.fiscalPeriod - 1
                  ELSE fp.fiscalPeriod END BETWEEN 7 AND 9  THEN 'Q3'
        WHEN CASE WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod IN (5, 6) THEN 5
                  WHEN fp.fiscal_year = 2026 AND fp.fiscalPeriod >= 7      THEN fp.fiscalPeriod - 1
                  ELSE fp.fiscalPeriod END >= 10             THEN 'Q4'
    END AS InvoiceFiscalQuarter,

    -- ── Sales Order ───────────────────────────────────────────────────────────
    b.co_num         AS SalesOrderNumber,
    b.co_line        AS SalesOrderLine,
    b.co_release     AS SalesOrderRelease,
    co.order_date    AS OrderDate,

    -- ── Customer ──────────────────────────────────────────────────────────────
    b.cust_num                      AS CustomerNumber,
    b.cust_seq                      AS CustomerSequence,
    ca.name                         AS CustomerName,
    ca.curr_code                    AS CurrencyCode,
    ca.country                      AS CustomerCountry,
    cust.customer_email_addr        AS CustomerEmailAddress,
    cust.phone1                     AS CustomerPhone,
    cust.cust_type                  AS CustomerGroup,
    cust.Uf_LocationArea            AS CustomerLocationArea,
    cust.Uf_Ranking                 AS CustomerRanking,
    et.description                  AS CustomerEndType,
    cust.Uf_MasterAccountNumber     AS MasterAccountNumber,
    cust.Uf_MasterAccountName       AS MasterAccountName,

    -- ── Ship To ───────────────────────────────────────────────────────────────
    ca.city                         AS ShiptoCity,
    ca.addr1                        AS ShiptoAddress1,
    ca.addr2                        AS ShiptoAddress2,
    ca.state                        AS ShiptoState,
    ca.zip                          AS ShiptoZipCode,
    ca.county                       AS ShiptoCounty,
    ca.ship_to_email                AS ShipToEmailAddress,

    -- ── Bill To ───────────────────────────────────────────────────────────────
    billto.cust_num                 AS BillToCustomerNumber,
    billto_address.name             AS BillToCustomerName,
    billto_address.addr1            AS BillToAddress1,
    billto_address.addr2            AS BillToAddress2,
    billto_address.city             AS BillToCity,
    billto_address.state            AS BillToState,
    billto_address.zip              AS BillToZIPPostalCode,
    billto_address.county           AS BillToCounty,
    billto_address.country          AS BillToCountry,
    billto_address.external_email_addr AS BillToExternalEmail,
    billto.phone1                   AS BillToPhone,
    billto.pricecode                AS BillToPriceCode,
    price.description               AS BillToPriceCodeDescription,
    billto.terms_code               AS TermsCode,
    billto.Uf_Ranking               AS BillToRanking,
    billto.Uf_CustomerCreateDate    AS BillToCreateDate,
    YEAR(billto.Uf_CustomerCreateDate)  AS BillToCreateYear,
    MONTH(billto.Uf_CustomerCreateDate) AS BilltoCreateMonthNumber,

    -- ── Item & Product ────────────────────────────────────────────────────────
    b.item                          AS ItemNumber,
    it.description                  AS ItemDescription,
    it.alt_item                     AS AlternateItemNumber,
    it.product_code                 AS ProductCode,
    pc.description                  AS ProductCodeDescription,
    it.p_m_t_code                   AS PMTCode,
    it.Uf_AssociatedBook            AS AssociatedBook,
    it.Uf_ReleaseDate               AS LaunchDate,
    YEAR(it.Uf_ReleaseDate)         AS LaunchDateYear,
    it.family_code                  AS FamilyCode,
    fc.description                  AS FamilyCodeDescription,
    it.u_m                          AS UnitOfMeasure,
    um.description                  AS UnitOfMeasureDescription,
    it.reservable                   AS Reservable,
    it.stat                         AS ItemStatus,
    it.uf_itembrand                 AS ItemBrand,
    pc.uf_producttype               AS ProductType,
    it.Uf_ItemColorCode             AS ColorCode,
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
    it.Uf_BookCollection            AS BookCollection,

    -- ── Salesperson & Manager ─────────────────────────────────────────────────
    b.slsman                                                    AS SalespersonNumber,
    COALESCE(em.name,           ve.name)                        AS SalespersonName,
    COALESCE(em.email_addr,     ve.external_email_addr)         AS SalespersonEmail,
    manager.slsman                                              AS SalesManagerNumber,
    COALESCE(manager_employee.name,       manager_vendor.name)               AS SalesManagerName,
    COALESCE(manager_employee.email_addr, manager_vendor.external_email_addr) AS SalesManagerEmail,

    -- ── Invoice Amounts ───────────────────────────────────────────────────────
    b.qty_invoiced                                              AS InvoiceQuantity,
    b.qty_invoiced * b.price / NULLIF(b.exch_rate, 0)          AS InvoiceAmount,
    b.disc_amount  / NULLIF(b.exch_rate, 0)                    AS InvoiceDiscountAmount,

    -- ── Financials ────────────────────────────────────────────────────────────
    b.price                                                     AS UnitPrice,
    b.exch_rate                                                 AS ExchangeRate,
    b.cost                                                      AS UnitCost,
    b.qty_invoiced * b.cost                                     AS CostAmount,
    coi.matl_cost                                               AS MaterialCost,
    (coi.price / NULLIF(b.exch_rate, 0)) - coi.matl_cost       AS ProductMaterialMargin,
    b.misc_charges / NULLIF(b.exch_rate, 0)                    AS MiscellaneousCharges,
    b.freight      / NULLIF(b.exch_rate, 0)                    AS FreightAmount,

    -- ── ETL Metadata ──────────────────────────────────────────────────────────
    'Facts_Invoice' AS OriginID,
    'Act'           AS ScenarioID

FROM BaseInvoice AS b
OUTER APPLY (
    SELECT TOP 1 fp.*
    FROM FiscalPeriods AS fp
    WHERE CAST(b.inv_date AS DATE) BETWEEN fp.PeriodStart AND fp.PeriodEnd
    ORDER BY fp.fiscal_year, fp.fiscalPeriod
) AS fp
LEFT JOIN dbo.ODS_CSI_Syteline_Common_item_mst       AS it      ON it.site_ref      = b.site_ref      AND it.item           = b.item
LEFT JOIN dbo.ODS_CSI_Syteline_Common_prodcode_mst   AS pc      ON pc.site_ref      = it.site_ref     AND pc.product_code   = it.product_code
LEFT JOIN dbo.ODS_CSI_Syteline_Common_famcode_mst    AS fc      ON fc.site_ref      = it.site_ref     AND fc.family_code    = it.family_code
LEFT JOIN dbo.ODS_CSI_Syteline_Common_u_m_mst        AS um      ON um.site_ref      = it.site_ref     AND um.u_m            = it.u_m
LEFT JOIN dbo.ODS_CSI_Syteline_Common_customer_mst   AS cust    ON cust.site_ref    = b.site_ref      AND LTRIM(cust.cust_num)   = LTRIM(b.cust_num) AND cust.cust_seq   = b.cust_seq
LEFT JOIN dbo.ODS_CSI_Syteline_Common_custaddr_mst   AS ca      ON ca.site_ref      = b.site_ref      AND LTRIM(ca.cust_num)     = LTRIM(b.cust_num) AND ca.cust_seq     = b.cust_seq
LEFT JOIN dbo.ODS_CSI_Syteline_Common_customer_mst   AS billto  ON billto.site_ref  = b.site_ref      AND LTRIM(billto.cust_num) = LTRIM(b.cust_num) AND billto.cust_seq = 0
LEFT JOIN dbo.ODS_CSI_Syteline_Common_custaddr_mst   AS billto_address ON billto_address.site_ref = billto.site_ref AND LTRIM(billto_address.cust_num) = LTRIM(billto.cust_num) AND billto_address.cust_seq = 0
LEFT JOIN dbo.ODS_CSI_Syteline_Common_endtype_mst    AS et      ON et.site_ref      = cust.site_ref   AND et.end_user_type  = cust.end_user_type
LEFT JOIN dbo.ODS_CSI_Syteline_Common_pricecode_mst  AS price   ON price.site_ref   = billto.site_ref AND price.pricecode    = billto.pricecode
LEFT JOIN dbo.ODS_CSI_Syteline_Common_coitem_mst     AS coi     ON coi.site_ref     = b.site_ref      AND coi.co_num        = b.item_co_num AND coi.co_line = b.co_line AND coi.co_release = b.co_release
LEFT JOIN dbo.ODS_CSI_Syteline_Common_co_mst         AS co      ON co.site_ref      = b.site_ref      AND co.co_num         = b.co_num
LEFT JOIN dbo.ODS_CSI_Syteline_Common_slsman_mst     AS sl      ON sl.site_ref      = b.site_ref      AND sl.slsman         = b.slsman
LEFT JOIN dbo.ODS_CSI_Syteline_Common_employee_mst   AS em      ON em.site_ref      = sl.site_ref     AND em.emp_num        = sl.ref_num
LEFT JOIN dbo.ODS_CSI_Syteline_Common_vendaddr_mst   AS ve      ON ve.site_ref      = sl.site_ref     AND ve.vend_num       = sl.ref_num
LEFT JOIN dbo.ODS_CSI_Syteline_Common_slsman_mst     AS manager ON manager.site_ref = sl.site_ref     AND manager.slsman    = sl.slsmangr
LEFT JOIN dbo.ODS_CSI_Syteline_Common_employee_mst   AS manager_employee ON manager_employee.site_ref = manager.site_ref AND manager_employee.emp_num = manager.ref_num
LEFT JOIN dbo.ODS_CSI_Syteline_Common_vendaddr_mst   AS manager_vendor   ON manager_vendor.site_ref   = manager.site_ref AND manager_vendor.vend_num   = manager.ref_num
ORDER BY
    b.inv_date ASC,
    b.site_ref,
    b.inv_num,
    b.inv_seq,
    b.inv_line;
