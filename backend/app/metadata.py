"""
Metadata registry.

This module loads the single approved master table definition from the JSON
config file and exposes a small, read-only API the rest of the app uses to:

  * list the friendly fields shown in the UI,
  * validate that a requested column is whitelisted,
  * map a whitelisted column to its data type, and
  * expose the (fixed) master table name.

The metadata config is the *only* source of truth for which table and columns
may ever appear in a generated query. Nothing the user sends can add a column
or change the table.
"""
import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Dict, List

from .config import get_settings

# A safe SQL identifier: letters, digits, underscore only. Column names that
# come from the config are additionally checked against this so a typo in the
# config can never produce an injectable identifier.
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
    #   "count"    -> COUNT of non-null rows (e.g. invoice line number = 1/row)
    #   "distinct" -> COUNT(DISTINCT) (e.g. unique invoice numbers)
    #   "none"     -> not aggregated
    aggregate: str = "none"


@dataclass(frozen=True)
class Metadata:
    table_name: str
    fields: List[Field]

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


def _load_from_path(path: Path) -> Metadata:
    if not path.exists():
        raise FileNotFoundError(f"Metadata config not found at: {path}")

    raw = json.loads(path.read_text(encoding="utf-8"))

    table_name = raw.get("table_name", "")
    if not _SAFE_TABLE.match(table_name):
        raise ValueError(f"Invalid table_name in metadata config: {table_name!r}")

    fields: List[Field] = []
    seen = set()
    for entry in raw.get("fields", []):
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
        # Default aggregate: numbers sum (legacy behaviour), everything else none.
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
        raise ValueError("Metadata config must define at least one field.")

    return Metadata(table_name=table_name, fields=fields)


@lru_cache
def get_metadata() -> Metadata:
    """Load and cache the metadata config (resolved relative to the backend dir)."""
    settings = get_settings()
    config_path = Path(settings.metadata_config_path)
    if not config_path.is_absolute():
        # Resolve relative to the backend package root (parent of app/).
        config_path = Path(__file__).resolve().parent.parent / config_path
    return _load_from_path(config_path)
