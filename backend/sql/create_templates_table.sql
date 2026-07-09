-- =============================================================================
-- report_templates table
-- Run this once against your production (and dev) SQL Server database.
--
-- The DB user used by the app needs:
--   SELECT, INSERT, UPDATE on dbo.report_templates
--
-- If your app user is currently read-only on the master table, grant write
-- access to this table only:
--   GRANT SELECT, INSERT, UPDATE ON dbo.report_templates TO <app_user>;
-- =============================================================================

IF NOT EXISTS (
    SELECT 1
    FROM   sys.objects
    WHERE  object_id = OBJECT_ID(N'dbo.report_templates')
      AND  type      = N'U'
)
BEGIN
    CREATE TABLE dbo.report_templates (
        id          INT            IDENTITY(1,1) NOT NULL,
        name        NVARCHAR(255)  NOT NULL,
        config      NVARCHAR(MAX)  NOT NULL,   -- JSON blob
        created_at  DATETIME2(0)   NOT NULL CONSTRAINT DF_report_templates_created_at DEFAULT SYSUTCDATETIME(),
        updated_at  DATETIME2(0)   NOT NULL CONSTRAINT DF_report_templates_updated_at DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_report_templates PRIMARY KEY (id),
        CONSTRAINT UQ_report_templates_name UNIQUE (name)
    );

    PRINT 'report_templates table created.';
END
ELSE
BEGIN
    PRINT 'report_templates table already exists — skipping.';
END
GO

-- =============================================================================
-- Optional: migrate existing templates from the JSON file.
-- Replace the VALUES rows below with your actual templates if needed.
-- =============================================================================
-- INSERT INTO dbo.report_templates (name, config) VALUES
--   ('My Saved Report', '{"columns": [...], "filters": [], "filter_logic": "AND", "sorts": [], "titles": {}}');
-- GO
