-- =============================================================================
-- Read-only check: which saved templates still reference columns that were
-- removed from the sales model in metadata_config.json?
--
-- app/query_builder.py validates every column against the model whitelist, so a
-- template that still lists a removed column fails with "Column not allowed"
-- when it is run or re-saved. This query finds those templates so they can be
-- opened and re-saved without the dropped columns.
--
-- Nothing is modified. Run on QA_Main first, then production.
-- =============================================================================

DECLARE @removed TABLE (column_name NVARCHAR(128));
INSERT INTO @removed (column_name) VALUES
    (N'SalesOrderRelease'),
    (N'PMTCode'),
    (N'Category'),
    (N'FamilyCodeDescription');

SELECT  t.id,
        t.name,
        JSON_VALUE(t.config, '$.model') AS model,
        t.created_by,
        t.updated_at,
        r.column_name                   AS stale_column
FROM    dbo.report_templates AS t
CROSS APPLY (
    SELECT column_name
    FROM   @removed
    WHERE  t.config LIKE N'%"' + column_name + N'"%'
) AS r
ORDER BY t.name, r.column_name;
