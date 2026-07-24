-- Migration: add created_by, last_run_by, last_run_at to report_templates
-- Run once on QA_Main (and any other target databases).

ALTER TABLE dbo.report_templates
ADD created_by  NVARCHAR(255) NULL,
    last_run_by NVARCHAR(255) NULL,
    last_run_at DATETIME2     NULL;
