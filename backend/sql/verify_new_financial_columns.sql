-- =============================================================================
-- Read-only check: do the financial-model columns added on 2026-10-14 exist in
-- dbo.FinancialQueryBuilder_MasterTable with compatible data types?
--
-- metadata_config.json is a hand-maintained whitelist, so a typo surfaces as
-- "Invalid column name" the first time a user picks the field. Run this on
-- QA_Main (and production) before restarting the app.
--
-- Expected: 3 rows, all with status = 'OK'.
-- Nothing is modified.
-- =============================================================================

DECLARE @expected TABLE (column_name NVARCHAR(128), expected_kind NVARCHAR(20));
INSERT INTO @expected (column_name, expected_kind) VALUES
    (N'NetDomesticAmount', N'number'),
    (N'NetForeignAmount',  N'number'),
    (N'CreateDate',        N'date');

SELECT  e.column_name,
        e.expected_kind,
        c.DATA_TYPE AS actual_sql_type,
        CASE
            WHEN c.COLUMN_NAME IS NULL THEN 'MISSING - column not found'
            WHEN e.expected_kind = 'number'
                 AND c.DATA_TYPE IN ('decimal','numeric','money','smallmoney','float','real','int','bigint','smallint')
                THEN 'OK'
            WHEN e.expected_kind = 'date'
                 AND c.DATA_TYPE IN ('date','datetime','datetime2','smalldatetime','datetimeoffset')
                THEN 'OK'
            ELSE 'CHECK - unexpected type for ' + e.expected_kind
        END AS status
FROM    @expected e
LEFT JOIN INFORMATION_SCHEMA.COLUMNS c
       ON  c.TABLE_SCHEMA = 'dbo'
       AND c.TABLE_NAME   = 'FinancialQueryBuilder_MasterTable'
       AND c.COLUMN_NAME  = e.column_name;

-- Optional sanity check (scans the table): net should equal debit - credit.
-- SELECT COUNT(*)                                            AS total_rows,
--        SUM(CASE WHEN CreateDate IS NULL THEN 1 ELSE 0 END)  AS null_create_date,
--        SUM(CASE WHEN ABS(ISNULL(NetDomesticAmount,0) - (ISNULL(DebitDomestic,0) - ISNULL(CreditDomestic,0))) > 0.01
--                 THEN 1 ELSE 0 END)                          AS net_domestic_mismatch,
--        SUM(CASE WHEN ABS(ISNULL(NetForeignAmount,0)  - (ISNULL(DebitForeign,0)  - ISNULL(CreditForeign,0)))  > 0.01
--                 THEN 1 ELSE 0 END)                          AS net_foreign_mismatch
-- FROM dbo.FinancialQueryBuilder_MasterTable;
