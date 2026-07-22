"""Pydantic request/response models for the API."""
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field as PydanticField


# --- Filters & queries --------------------------------------------------------
class Filter(BaseModel):
    """A single filter condition. `column` must be a whitelisted column name."""

    column: str
    operator: str
    # `value` is used by single-value operators (equals, contains, >, <, ...).
    value: Optional[Any] = None
    # `values` is used by multi-value operators: "between" (exactly 2) and
    # "in_list" (1+). "is_blank" / "is_not_blank" use neither.
    values: Optional[List[Any]] = None


class Sort(BaseModel):
    """A single ORDER BY entry. `column` must be whitelisted; direction ASC/DESC."""

    column: str
    direction: str = "ASC"


class QueryRequest(BaseModel):
    """Shared shape for /preview and /export."""

    # Which data model to query (must match a key in metadata_config.json).
    model: str = "sales"
    columns: List[str] = PydanticField(
        default_factory=list,
        description="Whitelisted column names to include in the report.",
    )
    filters: List[Filter] = PydanticField(default_factory=list)
    # Logic that joins the filters together: "AND" or "OR".
    filter_logic: str = "AND"
    # Optional ORDER BY entries.
    sorts: List[Sort] = PydanticField(default_factory=list)
    # Optional per-column header overrides (column_name -> friendly title) used
    # for preview headers and Excel export.
    titles: Dict[str, str] = PydanticField(default_factory=dict)


class PreviewResponse(BaseModel):
    columns: List[str]                 # column_name order
    display_names: List[str]           # friendly headers, parallel to columns
    rows: List[List[Any]]              # row-major values
    row_count: int
    message: Optional[str] = None      # e.g. "No records found."


# --- Analysis -----------------------------------------------------------------
class ColumnStat(BaseModel):
    column: str
    title: str
    aggregate: str = "sum"              # "sum" | "count" | "distinct"
    total: Optional[float] = None       # headline number (sum / count / distinct)
    average: Optional[float] = None     # AVG (sum mode only)
    minimum: Optional[float] = None     # MIN (sum mode only)
    maximum: Optional[float] = None     # MAX (sum mode only)
    count: int = 0                      # non-null COUNT


class AnalysisResponse(BaseModel):
    row_count: int                      # total rows matching the filters
    stats: List[ColumnStat]             # one per selected numeric column


# --- Field metadata response --------------------------------------------------
class FieldOut(BaseModel):
    display_name: str
    column_name: str
    data_type: str
    group: str = "General"


# --- Templates ----------------------------------------------------------------
class TemplateConfig(BaseModel):
    """The saved report definition (columns + titles + filters + logic + sorts)."""

    # Which data model this template targets.
    model: str = "sales"
    columns: List[str] = PydanticField(default_factory=list)
    filters: List[Filter] = PydanticField(default_factory=list)
    filter_logic: str = "AND"
    sorts: List[Sort] = PydanticField(default_factory=list)
    titles: Dict[str, str] = PydanticField(default_factory=dict)


class TemplateCreate(BaseModel):
    name: str
    config: TemplateConfig


class TemplateSummary(BaseModel):
    id: int
    name: str
    model: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class TemplateDetail(TemplateSummary):
    config: TemplateConfig
