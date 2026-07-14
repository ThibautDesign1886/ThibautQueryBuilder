"""
Metadata registry.

Loads one or more model definitions from the JSON config file. Each model maps
a friendly name to a SQL table + a whitelist of approved columns.

The config supports two formats:

  Single-model (legacy):
    { "table_name": "dbo.Foo", "fields": [...] }
    treated as model key "sales"

  Multi-model:
    {
      "sales":     { "display_name": "Sales",     "table_name": "dbo.Foo", "fields": [...] },
      "financial": { "display_name": "Financial", "table_name": "dbo.Bar", "fields": [...] }
    }

The metadata config is the *only* source of truth for which tables and columns
may ever appear in a generated query. Nothing the user sends can add a column
or change the table.
"""
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

from .config import get_settings

# A safe SQL identifier: letters, digits, underscore only.
_SAFE_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# A fully-qualified table name: optional [schema].[table] using only safe parts.
_SAFE_TABLE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$")

DATA_TYPES = {"string", "number", "date", "boolean"}
AGGREGATE_MODES = {"sum", "count", "distinct", "none"}


@dataclass(frozen=True)
class Field:
    display_name: str
    column_name: str
    data_type: str
    group: str = "General"
    # How the Analysis box aggregates this field:
    #   "sum"      -> SUM (amounts, quantity, cost)
    #   "count"    -> COUNT of non-null rows
    #   "distinct" -> COUNT(DISTINCT)
    #   "none"     -> not aggregated
    aggregate: str = "none"


@dataclass(frozen=True)
class Metadata:
    table_name: str
    fields: List[Field]
    display_name: str = ""

    @property
    def by_column(self) -> Dict[str, Field]:
        return {f.column_name: f for f in self.fields}

    def is_allowed_column(self, column_name: str) -> bool:
        return column_name in self.by_column

    def get_field(self, column_name: str) -> Field:
        return self.by_column[column_name]

    def quoted_table(self) -> str:
        """Return the table name with each part bracket-quoted for SQL Server."""
        return ".".join(f"[{part}]" for part in self.table_name.split("."))

    def quoted_column(self, column_name: str) -> str:
        """Bracket-quote a *validated* column name. Caller must whitelist first."""
        return f"[{column_name}]"


def _parse_model_dict(data: dict, default_display_name: str) -> "Metadata":
    """Parse a single model definition dict into a Metadata object."""
    table_name = data.get("table_name", "")
    if not _SAFE_TABLE.match(table_name):
        raise ValueError(f"Invalid table_name in metadata config: {table_name!r}")

    display_name = data.get("display_name") or default_display_name

    fields: List[Field] = []
    seen: set = set()
    for entry in data.get("fields", []):
        column = entry["column_name"]
        if not _SAFE_IDENTIFIER.match(column):
            raise ValueError(f"Invalid column_name in metadata config: {column!r}")
        data_type = entry["data_type"]
        if data_type not in DATA_TYPES:
            raise ValueError(
                f"Invalid data_type {data_type!r} for column {column!r}. "
                f"Allowed: {sorted(DATA_TYPES)}"
            )
        if column in seen:
            raise ValueError(f"Duplicate column_name in metadata config: {column!r}")
        seen.add(column)
        aggregate = entry.get("aggregate") or (
            "sum" if data_type == "number" else "none"
        )
        if aggregate not in AGGREGATE_MODES:
            raise ValueError(
                f"Invalid aggregate {aggregate!r} for column {column!r}. "
                f"Allowed: {sorted(AGGREGATE_MODES)}"
            )

        fields.append(
            Field(
                display_name=entry["display_name"],
                column_name=column,
                data_type=data_type,
                group=entry.get("group") or "General",
                aggregate=aggregate,
            )
        )

    if not fields:
        raise ValueError(f"Model '{default_display_name}' must define at least one field.")

    return Metadata(table_name=table_name, fields=fields, display_name=display_name)


def _load_all_models(path: Path) -> Dict[str, "Metadata"]:
    """Load all models from the config file. Returns a dict keyed by model key."""
    if not path.exists():
        raise FileNotFoundError(f"Metadata config not found at: {path}")

    raw = json.loads(path.read_text(encoding="utf-8"))

    # Legacy flat format: single model at top level
    if "table_name" in raw:
        return {"sales": _parse_model_dict(raw, "Sales")}

    # Multi-model format: each top-level key is a model
    if not raw:
        raise ValueError("Metadata config defines no models.")

    models = {}
    for key, model_dict in raw.items():
        models[key] = _parse_model_dict(model_dict, key.title())
    return models


# Module-level cache loaded once on first call.
_models_cache: Dict[str, "Metadata"] = {}


def _get_config_path() -> Path:
    settings = get_settings()
    config_path = Path(settings.metadata_config_path)
    if not config_path.is_absolute():
        config_path = Path(__file__).resolve().parent.parent / config_path
    return config_path


def get_all_models() -> Dict[str, "Metadata"]:
    """Return all models keyed by their config key. Cached after first load."""
    global _models_cache
    if not _models_cache:
        _models_cache = _load_all_models(_get_config_path())
    return _models_cache


def get_metadata(model_key: str = "sales") -> "Metadata":
    """Return the Metadata for the given model key."""
    models = get_all_models()
    if model_key not in models:
        available = list(models.keys())
        raise KeyError(
            f"Unknown model {model_key!r}. Available: {available}"
        )
    return models[model_key]
