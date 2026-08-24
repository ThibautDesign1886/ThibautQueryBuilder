-- =============================================================================
-- Read-only check: do the sales-model columns added on 2026-08-24 actually
-- exist in the master table, and with the expected data type?
--
-- metadata_config.json is a hand-maintained whitelist, so a typo here surfaces
-- as "Invalid column name" the first time a user picks the field. Run this on
-- QA_Main after the ETL/table change and before restarting the app.
--
-- Expected: 4 rows, all with status = 'OK'.
-- Nothing is modified.
-- =============================================================================

DECLARE @expected TABLE (column_name NVARCHAR(128), expected_kind NVARCHAR(20));
INSERT INTO @expected (column_name, expected_kind) VALUES
    (N'TotalCostAmount',     N'number'),   -- renamed from CostAmount
    (N'NativeAmount',        N'number'),
    (N'TotalMaterialMargin', N'number'),
    (N'ContractOrderFlag',   N'boolean');  -- 0/1 flag (bit, or any int type)

SELECT  e.column_name,
        e.expected_kind,
        c.DATA_TYPE                     AS actual_sql_type,
        CASE
            WHEN c.COLUMN_NAME IS NULL THEN 'MISSING — column not found'
            WHEN e.expected_kind = 'number'
                 AND c.DATA_TYPE IN ('decimal','numeric','money','smallmoney',
                                     'float','real','int','bigint','smallint','tinyint')
                THEN 'OK'
            WHEN e.expected_kind = 'boolean'
                 AND c.DATA_TYPE IN ('bit','int','smallint','tinyint')
                THEN 'OK'
            ELSE 'TYPE MISMATCH — update data_type in metadata_config.json'
        END                             AS status
FROM    @expected AS e
LEFT JOIN INFORMATION_SCHEMA.COLUMNS AS c
       ON c.TABLE_SCHEMA = 'dbo'
      AND c.TABLE_NAME   = 'SalesQueryBuilder_MasterTable'
      AND c.COLUMN_NAME  = e.column_name
ORDER BY e.column_name;

-- If the old name is still present, the rename did not happen (or both exist).
SELECT  COLUMN_NAME, DATA_TYPE
FROM    INFORMATION_SCHEMA.COLUMNS
WHERE   TABLE_SCHEMA = 'dbo'
  AND   TABLE_NAME   = 'SalesQueryBuilder_MasterTable'
  AND   COLUMN_NAME  = 'CostAmount';
