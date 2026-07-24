"""
Saved report templates — persisted to a SQL Server table (dbo.report_templates).

Run backend/sql/create_templates_table.sql once to create the table and grant
the app user SELECT, INSERT, UPDATE on it.

Table shape:
    id          INT IDENTITY PK
    name        NVARCHAR(255) UNIQUE NOT NULL
    config      NVARCHAR(MAX) NOT NULL  -- JSON blob
    created_at  DATETIME2
    updated_at  DATETIME2
"""
import json
from datetime import datetime
from typing import List, Optional

from .database import execute, execute_returning_scalar, run_select
from .models import TemplateConfig, TemplateDetail, TemplateSummary


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _iso(value) -> Optional[str]:
    """Convert a datetime (or string) to an ISO-8601 string."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%dT%H:%M:%SZ")
    return str(value)


def _row_to_detail(row: list) -> TemplateDetail:
    # row: [id, name, config_json, created_at, updated_at, created_by, last_run_by, last_run_at]
    return TemplateDetail(
        id=row[0],
        name=row[1],
        config=TemplateConfig(**json.loads(row[2])),
        created_at=_iso(row[3]),
        updated_at=_iso(row[4]),
        created_by=row[5] if len(row) > 5 else None,
        last_run_by=row[6] if len(row) > 6 else None,
        last_run_at=_iso(row[7]) if len(row) > 7 else None,
    )


# ---------------------------------------------------------------------------
# Public API (same interface as the old JSON-backed store)
# ---------------------------------------------------------------------------

def list_templates() -> List[TemplateSummary]:
    _, rows = run_select(
        "SELECT id, name, created_at, updated_at, "
        "JSON_VALUE(config, '$.model') AS model, "
        "created_by, last_run_by, last_run_at "
        "FROM dbo.report_templates "
        "ORDER BY name",
        [],
    )
    return [
        TemplateSummary(
            id=r[0],
            name=r[1],
            created_at=_iso(r[2]),
            updated_at=_iso(r[3]),
            model=r[4],
            created_by=r[5],
            last_run_by=r[6],
            last_run_at=_iso(r[7]),
        )
        for r in rows
    ]


def get_template(template_id: int) -> Optional[TemplateDetail]:
    _, rows = run_select(
        "SELECT id, name, config, created_at, updated_at, created_by, last_run_by, last_run_at "
        "FROM dbo.report_templates "
        "WHERE id = ?",
        [template_id],
    )
    return _row_to_detail(rows[0]) if rows else None


def get_template_by_name(name: str) -> Optional[TemplateDetail]:
    _, rows = run_select(
        "SELECT id, name, config, created_at, updated_at, created_by, last_run_by, last_run_at "
        "FROM dbo.report_templates "
        "WHERE name = ?",
        [name],
    )
    return _row_to_detail(rows[0]) if rows else None


def save_template(name: str, config: TemplateConfig, created_by: Optional[str] = None) -> TemplateDetail:
    """
    Upsert by name: update the existing template if one with this name exists,
    otherwise insert a new one. Returns the full TemplateDetail.
    created_by is only stored on INSERT; updates preserve the original creator.
    """
    config_json = json.dumps(config.model_dump())

    # Check for an existing template with this name.
    _, rows = run_select(
        "SELECT id FROM dbo.report_templates WHERE name = ?",
        [name],
    )

    if rows:
        template_id = rows[0][0]
        execute(
            "UPDATE dbo.report_templates "
            "SET config = ?, updated_at = SYSUTCDATETIME() "
            "WHERE id = ?",
            [config_json, template_id],
        )
    else:
        template_id = execute_returning_scalar(
            "INSERT INTO dbo.report_templates (name, config, created_by) "
            "OUTPUT INSERTED.id "
            "VALUES (?, ?, ?)",
            [name, config_json, created_by],
        )

    result = get_template(template_id)
    if result is None:  # pragma: no cover
        raise RuntimeError(f"Template {template_id} not found after save.")
    return result


def record_run(template_id: int, user: Optional[str]) -> None:
    """Record that a user executed this template (last_run_by, last_run_at)."""
    execute(
        "UPDATE dbo.report_templates "
        "SET last_run_by = ?, last_run_at = SYSUTCDATETIME() "
        "WHERE id = ?",
        [user, template_id],
    )


def delete_template(template_id: int) -> bool:
    """Delete a template by ID. Returns True if a row was deleted, False if not found."""
    from .database import execute_returning_scalar as _scalar
    # rowcount-based delete
    _, rows = run_select(
        "SELECT id FROM dbo.report_templates WHERE id = ?",
        [template_id],
    )
    if not rows:
        return False
    execute(
        "DELETE FROM dbo.report_templates WHERE id = ?",
        [template_id],
    )
    return True
