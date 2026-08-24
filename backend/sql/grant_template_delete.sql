-- =============================================================================
-- Migration: allow the app login to delete saved report templates.
--
-- Symptom this fixes:
--   "Could not delete template: ... The DELETE permission was denied on the
--    object 'report_templates', database 'QA_Main', schema 'dbo'. (229)"
--
-- dbo.report_templates was created with SELECT, INSERT, UPDATE only (see
-- create_templates_table.sql), so the Delete button in the Reports page fails.
--
-- Run once per target database (QA_Main, then production) as a user with
-- permission to grant. Re-running is harmless.
--
-- If your app login is not `sfread`, change the principal name below to match
-- DB_USER from the App Service application settings.
-- =============================================================================

GRANT DELETE ON dbo.report_templates TO sfread;
GO

-- Verify the grant (expected: SELECT, INSERT, UPDATE, DELETE).
SELECT  p.permission_name,
        p.state_desc
FROM    sys.database_permissions AS p
JOIN    sys.database_principals  AS u ON u.principal_id = p.grantee_principal_id
WHERE   p.major_id = OBJECT_ID(N'dbo.report_templates')
  AND   u.name     = N'sfread'
ORDER BY p.permission_name;
GO
