"""
FastAPI application — Sparkflow / Thibaut Query Builder.

This single app serves BOTH the JSON API (under /api/*) and the built React
frontend (static files), so testers only need one URL and one port.

API endpoints (all under /api)
------------------------------
GET  /api/config         -> whether a password is required (public)
POST /api/login          -> validate the shared password (public)
GET  /api/health         -> health check (public)
GET  /api/datasource     -> the single master table used as the data source
GET  /api/fields         -> approved attributes from the master table metadata
POST /api/preview        -> first N rows for the selected columns + filters
POST /api/analyze        -> totals over the full filtered dataset
POST /api/export         -> downloadable .xlsx
POST /api/templates      -> save a report template
GET  /api/templates      -> list saved report templates
GET  /api/templates/{id} -> load a saved template

Access control
--------------
If APP_PASSWORD is set, every /api/* route except /api/config, /api/login and
/api/health requires the header `X-App-Password` to match. The frontend collects
the password on a login screen and sends it with each request. If APP_PASSWORD
is blank, the gate is disabled (handy for local development).

The user never sends SQL. Requests are validated against the metadata whitelist
and executed as parameterized queries (see query_builder.py).
"""
import csv
import io
from datetime import datetime
from pathlib import Path

from typing import Optional

from fastapi import APIRouter, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import excel_export, templates_store
from .config import get_settings
from .database import run_select
from .metadata import get_all_models, get_metadata
from .models import (
    AnalysisResponse,
    ColumnStat,
    FieldOut,
    PreviewResponse,
    QueryRequest,
    TemplateCreate,
    TemplateDetail,
    TemplateSummary,
)
from .query_builder import (
    QueryValidationError,
    build_aggregate_query,
    build_query,
)

settings = get_settings()

# ---------------------------------------------------------------------------
# Application Insights — must be configured BEFORE the FastAPI app is created
# so that the OpenTelemetry ASGI instrumentation wraps every request.
# Disabled automatically when the connection string is blank (local dev).
# ---------------------------------------------------------------------------
if settings.applicationinsights_connection_string:
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor(
        connection_string=settings.applicationinsights_connection_string,
    )

app = FastAPI(
    title="Thibaut Query Builder",
    description="Self-service reporting over a single approved master table.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Paths under /api that are always public (no auth required).
_PUBLIC_API_PATHS = {"/api/config", "/api/login", "/api/health"}


@app.middleware("http")
async def auth_gate(request: Request, call_next):
    """
    Three auth modes (set via AUTH_MODE env var):

    - "azure_ad"  Production: Azure App Service EasyAuth authenticates users
                  before requests reach this app. Every authenticated request
                  arrives with an X-MS-CLIENT-PRINCIPAL header injected by Azure.
                  We verify the header is present.

    - "password"  Staging / dev sharing: shared password sent as X-App-Password.
                  Set APP_PASSWORD to enable.

    - "open"      Local development: no auth check at all.
    """
    path = request.url.path
    if not path.startswith("/api") or path in _PUBLIC_API_PATHS:
        return await call_next(request)

    mode = settings.auth_mode

    if mode == "azure_ad":
        # EasyAuth injects this header for every authenticated request.
        if not request.headers.get("X-MS-CLIENT-PRINCIPAL"):
            return JSONResponse(
                status_code=401,
                content={"detail": "Authentication required. Please sign in."},
            )
        return await call_next(request)

    if mode == "password":
        if request.headers.get("X-App-Password", "") != settings.app_password:
            return JSONResponse(
                status_code=401, content={"detail": "Invalid or missing password."}
            )
        return await call_next(request)

    # "open" — no auth (local dev)
    return await call_next(request)


# All API routes live under /api so they don't collide with the static frontend.
api = APIRouter(prefix="/api")


class LoginRequest(BaseModel):
    password: str


@api.get("/config")
def get_config() -> dict:
    """Public: tells the frontend the auth mode and app title."""
    return {
        "auth_required": settings.auth_mode == "password",
        "auth_mode": settings.auth_mode,  # "open" | "password" | "azure_ad"
        "app_title": "Thibaut Query Builder",
    }


@api.get("/me")
def get_me(request: Request) -> dict:
    """Return the current user's identity.

    In azure_ad mode, EasyAuth injects the user's UPN/email via
    X-MS-CLIENT-PRINCIPAL-NAME. In password/open mode, no identity is available.
    """
    principal_name = request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME")
    return {
        "email": principal_name,
        "auth_mode": settings.auth_mode,
    }


@api.post("/login")
def login(payload: LoginRequest) -> dict:
    """Public: validate the shared password (password mode only)."""
    if settings.auth_mode != "password" or not settings.app_password:
        return {"ok": True}  # auth disabled
    if payload.password != settings.app_password:
        raise HTTPException(status_code=401, detail="Incorrect password.")
    return {"ok": True}


@api.get("/health")
def health() -> dict:
    return {"status": "ok"}


@api.get("/datasource")
def get_datasource() -> list:
    """Return all available data models as [{key, label}]."""
    models = get_all_models()
    return [
        {"key": key, "label": meta.display_name or key.title()}
        for key, meta in models.items()
    ]


@api.get("/fields", response_model=list[FieldOut])
def get_fields(model: str = Query(default="sales")) -> list[FieldOut]:
    """Return the whitelisted attributes for the given model (default: sales)."""
    try:
        metadata = get_metadata(model)
    except KeyError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return [
        FieldOut(
            display_name=f.display_name,
            column_name=f.column_name,
            data_type=f.data_type,
            group=f.group,
        )
        for f in metadata.fields
    ]


@api.get("/distinct")
def get_distinct(model: str = Query(default="sales"), column: str = Query(...)) -> list:
    """Return distinct values for a column (max 40). Empty list means too many values."""
    try:
        metadata = get_metadata(model)
    except KeyError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if not metadata.is_allowed_column(column):
        raise HTTPException(status_code=400, detail=f"Column not allowed: {column!r}")
    quoted_col = metadata.quoted_column(column)
    quoted_table = metadata.quoted_table()
    sql = (
        f"SELECT DISTINCT TOP 41 {quoted_col} "
        f"FROM {quoted_table} "
        f"WHERE {quoted_col} IS NOT NULL "
        f"ORDER BY {quoted_col}"
    )
    try:
        _, rows = run_select(sql, [])
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Database error: {exc}") from exc
    if len(rows) > 40:
        return []   # too many distinct values — tell frontend to use text input
    return [row[0] for row in rows]


def _run_query(request: QueryRequest, row_limit: int):
    """Shared validation + execution for /preview and /export."""
    try:
        metadata = get_metadata(request.model)
    except KeyError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        built = build_query(metadata, request, row_limit=row_limit)
    except QueryValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        result_columns, rows = run_select(built.sql, built.params)
    except Exception as exc:  # pragma: no cover - surfaced to the client
        raise HTTPException(
            status_code=502, detail=f"Database error: {exc}"
        ) from exc

    # Header labels: use the per-column Title override if supplied, else the
    # friendly display name from metadata.
    display_names = [
        request.titles.get(c) or metadata.get_field(c).display_name
        for c in request.columns
    ]
    return request.columns, display_names, rows


@api.post("/preview", response_model=PreviewResponse)
def preview(request: QueryRequest) -> PreviewResponse:
    """Return the first PREVIEW_ROW_LIMIT rows for the report."""
    columns, display_names, rows = _run_query(request, settings.preview_row_limit)
    return PreviewResponse(
        columns=columns,
        display_names=display_names,
        rows=rows,
        row_count=len(rows),
        message=None if rows else "No records found.",
    )


def _to_float(value) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


@api.post("/analyze", response_model=AnalysisResponse)
def analyze(request: QueryRequest) -> AnalysisResponse:
    """
    Aggregate the full filtered dataset: total row count plus per-column totals
    (sum / count / unique) — e.g. total Invoice Amount, total Invoice Quantity,
    unique Invoice Numbers.
    """
    try:
        metadata = get_metadata(request.model)
    except KeyError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        built = build_aggregate_query(metadata, request)
    except QueryValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        result_columns, rows = run_select(built.sql, built.params)
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=502, detail=f"Database error: {exc}"
        ) from exc

    # The aggregate query returns exactly one row; map alias -> value.
    row = rows[0] if rows else []
    by_alias = dict(zip(result_columns, row))

    stats = []
    for i, agg in enumerate(built.aggregations):
        col, mode = agg["column"], agg["mode"]
        field = metadata.get_field(col)
        title = request.titles.get(col) or field.display_name
        count = int(by_alias.get(f"cnt_{i}") or 0)

        if mode == "sum":
            total = _to_float(by_alias.get(f"sum_{i}"))
            average = _to_float(by_alias.get(f"avg_{i}"))
            minimum = _to_float(by_alias.get(f"min_{i}"))
            maximum = _to_float(by_alias.get(f"max_{i}"))
        elif mode == "distinct":
            total = float(_to_float(by_alias.get(f"dct_{i}")) or 0)
            average = minimum = maximum = None
        else:  # count
            total = float(count)
            average = minimum = maximum = None

        stats.append(
            ColumnStat(
                column=col,
                title=title,
                aggregate=mode,
                total=total,
                average=average,
                minimum=minimum,
                maximum=maximum,
                count=count,
            )
        )

    return AnalysisResponse(
        row_count=int(by_alias.get("row_count") or 0),
        stats=stats,
    )


@api.post("/export")
def export(request: QueryRequest) -> StreamingResponse:
    """Return a downloadable .xlsx for the report (capped at EXPORT_ROW_LIMIT)."""
    columns, display_names, rows = _run_query(request, settings.export_row_limit)
    content = excel_export.build_workbook(display_names, rows)

    filename = f"report_{datetime.utcnow():%Y%m%d_%H%M%S}.xlsx"
    return StreamingResponse(
        iter([content]),
        media_type=(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        ),
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@api.post("/export/csv")
def export_csv(request: QueryRequest) -> StreamingResponse:
    """Return a downloadable .csv for the report (capped at EXPORT_ROW_LIMIT)."""
    columns, display_names, rows = _run_query(request, settings.export_row_limit)
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(display_names)
    writer.writerows(rows)
    filename = f"report_{datetime.utcnow():%Y%m%d_%H%M%S}.csv"
    return StreamingResponse(
        iter([buffer.getvalue()]),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _current_user(request: Request) -> Optional[str]:
    """Extract the authenticated user's email from Azure EasyAuth headers."""
    return request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME") or None


@api.post("/templates", response_model=TemplateDetail)
def create_template(payload: TemplateCreate, request: Request) -> TemplateDetail:
    """Save (or update by name) a report template."""
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Template name is required.")

    # Validate the saved config references only approved columns/operators by
    # building (but not running) the query first.
    try:
        metadata = get_metadata(payload.config.model)
    except KeyError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        build_query(
            metadata,
            QueryRequest(
                model=payload.config.model,
                columns=payload.config.columns,
                filters=payload.config.filters,
                filter_logic=payload.config.filter_logic,
                sorts=payload.config.sorts,
                titles=payload.config.titles,
            ),
            row_limit=settings.preview_row_limit,
        )
    except QueryValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        return templates_store.save_template(name, payload.config, created_by=_current_user(request))
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=502, detail=f"Could not save template: {exc}"
        ) from exc


@api.get("/templates", response_model=list[TemplateSummary])
def list_templates() -> list[TemplateSummary]:
    try:
        return templates_store.list_templates()
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=502, detail=f"Could not list templates: {exc}"
        ) from exc


@api.get("/templates/{template_id}", response_model=TemplateDetail)
def load_template(template_id: int) -> TemplateDetail:
    try:
        template = templates_store.get_template(template_id)
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=502, detail=f"Could not load template: {exc}"
        ) from exc
    if template is None:
        raise HTTPException(status_code=404, detail="Template not found.")
    return template


@api.post("/templates/{template_id}/run", status_code=204)
def record_template_run(template_id: int, request: Request) -> None:
    """Record that the current user executed this template."""
    try:
        templates_store.record_run(template_id, _current_user(request))
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=502, detail=f"Could not record run: {exc}"
        ) from exc


@api.delete("/templates/{template_id}", status_code=204)
def delete_template(template_id: int) -> None:
    try:
        deleted = templates_store.delete_template(template_id)
    except Exception as exc:  # pragma: no cover
        raise HTTPException(
            status_code=502, detail=f"Could not delete template: {exc}"
        ) from exc
    if not deleted:
        raise HTTPException(status_code=404, detail="Template not found.")


app.include_router(api)


# --- Serve the built frontend (if present) ---------------------------------
# After `npm run build`, the static site lives in frontend/dist. Mounting it at
# "/" lets the same server deliver the UI. API routes above take precedence
# because they're registered before this mount.
_DIST_DIR = Path(__file__).resolve().parents[2] / "frontend" / "dist"
if _DIST_DIR.is_dir():
    app.mount("/", StaticFiles(directory=str(_DIST_DIR), html=True), name="frontend")
else:
    @app.get("/")
    def _no_build() -> dict:
        return {
            "service": "Thibaut Query Builder API",
            "status": "running",
            "note": "Frontend not built yet. Run `npm run build` in frontend/, "
                    "or use the Vite dev server at http://localhost:5173.",
            "docs": "/docs",
        }
