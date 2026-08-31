-- =============================================================================
-- Read-only check: does the sales-model column added on 2026-08-31 actually
-- exist in the master table, and with a string-compatible data type?
--
-- metadata_config.json is a hand-maintained whitelist, so a typo here surfaces
-- as "Invalid column name" the first time a user picks the field. Run this on
-- QA_Main (and production) before restarting the app.
--
-- Expected: 1 row with status = 'OK'.
-- Nothing is modified.
-- =============================================================================

DECLARE @expected TABLE (column_name NVARCHAR(128), expected_kind NVARCHAR(20));
INSERT INTO @expected (column_name, expected_kind) VALUES
    (N'CustomerPO', N'string');   -- customer's PO on the order (Syteline co_mst.cust_po)

SELECT  e.column_name,
        e.expected_kind,
        c.DATA_TYPE                     AS actual_sql_type,
        c.CHARACTER_MAXIMUM_LENGTH      AS max_length,
        CASE
            WHEN c.COLUMN_NAME IS NULL THEN 'MISSING - column not found'
            WHEN e.expected_kind = 'string'
                 AND c.DATA_TYPE IN ('char','nchar','varchar','nvarchar','text','ntext')
                THEN 'OK'
            ELSE 'TYPE MISMATCH - update data_type in metadata_config.json'
        END                             AS status
FROM    @expected AS e
LEFT JOIN INFORMATION_SCHEMA.COLUMNS AS c
       ON c.TABLE_SCHEMA = 'dbo'
      AND c.TABLE_NAME   = 'SalesQueryBuilder_MasterTable'
      AND c.COLUMN_NAME  = e.column_name
ORDER BY e.column_name;

-- Optional data sanity check: how much of the column is actually populated?
-- Uncomment to run (reads the master table).
-- SELECT COUNT(*)                                                   AS total_rows,
--        SUM(CASE WHEN NULLIF(LTRIM(RTRIM(CustomerPO)), '') IS NULL
--                 THEN 0 ELSE 1 END)                                AS rows_with_po
-- FROM   dbo.SalesQueryBuilder_MasterTable;
