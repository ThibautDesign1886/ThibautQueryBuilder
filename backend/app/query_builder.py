"""
Safe SQL query builder.

================================ HOW SAFETY WORKS ================================
The user never writes SQL. They send a structured request: a list of column
names, a list of filters (column + operator + value), and AND/OR logic. This
module turns that structure into a SQL Server query using two complementary
defenses:

1) IDENTIFIER WHITELISTING (for table & column names)
   Column and table names CANNOT be passed as SQL parameters, so we never trust
   them from the request. Every column the user references — both in SELECT and
   in WHERE — is checked against the metadata config. If a column is not in the
   whitelist, we raise an error and build nothing. Only the single predefined
   master table is ever used; the request can never name a table. Whitelisted
   identifiers are additionally bracket-quoted (e.g. [customer_name]).

2) PARAMETERIZED VALUES (for filter values)
   Every user-supplied *value* is bound through a pyodbc "?" placeholder and
   passed in a separate parameter list. Values are never concatenated into the
   SQL string, so injection through a value is impossible.

Operators are also validated, and each operator is checked against the field's
data type (e.g. "contains" only applies to strings; ">" / "between" only apply
to numbers and dates). There are no joins, subqueries, or UNIONs — the builder
only ever emits `SELECT <cols> FROM <master table> [WHERE ...] [ORDER BY ...]`.
================================================================================
"""
from dataclasses import dataclass
from typing import Any, List, Tuple

from .metadata import Metadata
from .models import Filter, QueryRequest

# Operators that take exactly one value.
_SINGLE_VALUE_OPS = {"equals", "not_equals", "contains", "starts_with", "gt", "gte", "lt", "lte"}
# Operators that take two values (an inclusive range).
_RANGE_OPS = {"between"}
# Operators that take a list of values.
_LIST_OPS = {"in_list"}
# Operators that take no value.
_NO_VALUE_OPS = {"is_blank", "is_not_blank"}

ALL_OPERATORS = _SINGLE_VALUE_OPS | _RANGE_OPS | _LIST_OPS | _NO_VALUE_OPS

# Which operators are valid for which data type. This enforces, e.g., that you
# can't run "contains" on a number or ">" on a string.
_OPERATORS_BY_TYPE = {
    "string": {"equals", "not_equals", "contains", "starts_with", "in_list",
               "is_blank", "is_not_blank"},
    "number": {"equals", "not_equals", "gt", "gte", "lt", "lte", "between", "in_list",
               "is_blank", "is_not_blank"},
    "date": {"equals", "not_equals", "gt", "gte", "lt", "lte", "between", "in_list",
             "is_blank", "is_not_blank"},
    "boolean": {"equals", "not_equals", "is_blank", "is_not_blank"},
}


class QueryValidationError(ValueError):
    """Raised when a request references something outside the whitelist."""


@dataclass
class BuiltQuery:
    sql: str
    params: List[Any]


def _validate_columns(metadata: Metadata, columns: List[str]) -> List[str]:
    if not columns:
        raise QueryValidationError("Select at least one column for the report.")
    for col in columns:
        if not metadata.is_allowed_column(col):
            raise QueryValidationError(f"Column not allowed: {col!r}")
    # De-duplicate while preserving order.
    seen, ordered = set(), []
    for col in columns:
        if col not in seen:
            seen.add(col)
            ordered.append(col)
    return ordered


def _coerce_boolean(value: Any) -> int:
    """Map common truthy/falsey representations to SQL Server bit (0/1)."""
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return 1 if value else 0
    if isinstance(value, str):
        return 1 if value.strip().lower() in {"1", "true", "yes", "y", "t"} else 0
    return 1 if value else 0


def _build_filter_clause(
    metadata: Metadata, f: Filter
) -> Tuple[str, List[Any]]:
    """Return a single WHERE fragment and its bound parameters for one filter."""
    if not metadata.is_allowed_column(f.column):
        raise QueryValidationError(f"Filter column not allowed: {f.column!r}")

    field = metadata.get_field(f.column)
    op = f.operator

    if op not in ALL_OPERATORS:
        raise QueryValidationError(f"Unknown operator: {op!r}")
    if op not in _OPERATORS_BY_TYPE[field.data_type]:
        raise QueryValidationError(
            f"Operator {op!r} is not valid for {field.data_type} "
            f"field {field.display_name!r}."
        )

    col = metadata.quoted_column(f.column)  # safe: column already whitelisted

    # --- No-value operators ---------------------------------------------------
    if op == "is_blank":
        # NULL or empty string.
        if field.data_type == "string":
            return f"({col} IS NULL OR {col} = '')", []
        return f"{col} IS NULL", []
    if op == "is_not_blank":
        if field.data_type == "string":
            return f"({col} IS NOT NULL AND {col} <> '')", []
        return f"{col} IS NOT NULL", []

    # --- List operator --------------------------------------------------------
    if op == "in_list":
        values = f.values if f.values is not None else (
            [f.value] if f.value is not None else []
        )
        if not values:
            raise QueryValidationError(
                f"'in list' requires at least one value for {field.display_name!r}."
            )
        if field.data_type == "boolean":
            values = [_coerce_boolean(v) for v in values]
        placeholders = ", ".join(["?"] * len(values))
        return f"{col} IN ({placeholders})", list(values)

    # --- Range operator -------------------------------------------------------
    if op == "between":
        values = f.values or []
        if len(values) != 2:
            raise QueryValidationError(
                f"'between' requires exactly two values for {field.display_name!r}."
            )
        return f"{col} BETWEEN ? AND ?", [values[0], values[1]]

    # --- Single-value operators ----------------------------------------------
    value = f.value
    if value is None and op not in _NO_VALUE_OPS:
        raise QueryValidationError(
            f"Operator {op!r} requires a value for {field.display_name!r}."
        )

    if op == "equals":
        if field.data_type == "boolean":
            value = _coerce_boolean(value)
        return f"{col} = ?", [value]
    if op == "not_equals":
        if field.data_type == "boolean":
            value = _coerce_boolean(value)
        return f"{col} <> ?", [value]
    if op == "gt":
        return f"{col} > ?", [value]
    if op == "gte":
        return f"{col} >= ?", [value]
    if op == "lt":
        return f"{col} < ?", [value]
    if op == "lte":
        return f"{col} <= ?", [value]
    if op == "contains":
        # LIKE with the wildcard supplied as part of the *parameter*, not the
        # SQL. We escape LIKE metacharacters so user input is treated literally.
        return f"{col} LIKE ? ESCAPE '\\'", [f"%{_escape_like(value)}%"]
    if op == "starts_with":
        return f"{col} LIKE ? ESCAPE '\\'", [f"{_escape_like(value)}%"]

    raise QueryValidationError(f"Unsupported operator: {op!r}")


def _escape_like(value: Any) -> str:
    """Escape LIKE wildcards so they are matched literally."""
    text = str(value)
    return (
        text.replace("\\", "\\\\")
        .replace("%", "\\%")
        .replace("_", "\\_")
        .replace("[", "\\[")
    )


def _build_where(metadata: Metadata, request: QueryRequest):
    """
    Build the WHERE clause shared by the SELECT and the aggregate query.

    Returns (where_sql, params) where where_sql is either "" or a string that
    starts with " WHERE ...". Every value is parameterized; every column is
    whitelisted inside `_build_filter_clause`.
    """
    logic = (request.filter_logic or "AND").upper()
    if logic not in {"AND", "OR"}:
        raise QueryValidationError("filter_logic must be 'AND' or 'OR'.")

    where_fragments: List[str] = []
    params: List[Any] = []
    for f in request.filters:
        fragment, fragment_params = _build_filter_clause(metadata, f)
        where_fragments.append(fragment)
        params.extend(fragment_params)

    if not where_fragments:
        return "", params
    joiner = f" {logic} "
    return " WHERE " + joiner.join(where_fragments), params


def build_query(
    metadata: Metadata,
    request: QueryRequest,
    row_limit: int,
) -> BuiltQuery:
    """
    Build a safe, parameterized SELECT for the master table.

    Emits: SELECT TOP (n) <cols> FROM <master table> [WHERE ...] ORDER BY <c1>
    """
    columns = _validate_columns(metadata, request.columns)

    if row_limit <= 0:
        raise QueryValidationError("row_limit must be a positive integer.")

    select_cols = ", ".join(metadata.quoted_column(c) for c in columns)

    where_sql, where_params = _build_where(metadata, request)

    # TOP (?) is parameterized so the limit itself can't be injected.
    sql = f"SELECT TOP (?) {select_cols} FROM {metadata.quoted_table()}"
    final_params: List[Any] = [int(row_limit)] + where_params
    sql += where_sql

    # ORDER BY: use the user's sort list (validated), else fall back to the first
    # selected column so previews are deterministic. Sort directions are limited
    # to ASC/DESC and column names are whitelisted — never taken raw.
    order_terms: List[str] = []
    for s in request.sorts:
        if not metadata.is_allowed_column(s.column):
            raise QueryValidationError(f"Sort column not allowed: {s.column!r}")
        direction = (s.direction or "ASC").upper()
        if direction not in {"ASC", "DESC"}:
            raise QueryValidationError(
                f"Sort direction must be ASC or DESC, got {s.direction!r}."
            )
        order_terms.append(f"{metadata.quoted_column(s.column)} {direction}")

    if order_terms:
        sql += " ORDER BY " + ", ".join(order_terms)
    else:
        sql += f" ORDER BY {metadata.quoted_column(columns[0])}"

    return BuiltQuery(sql=sql, params=final_params)


@dataclass
class BuiltAggregate:
    sql: str
    params: List[Any]
    # Parallel list of {"column": ..., "mode": ...} matching the alias indices.
    aggregations: List[dict]


def build_aggregate_query(
    metadata: Metadata, request: QueryRequest
) -> BuiltAggregate:
    """
    Build a safe aggregate query for the Analysis box.

    Emits a single row with COUNT(*) AS row_count, plus per selected column that
    has an aggregate mode in its metadata:
        mode "sum"      -> SUM, AVG, MIN, MAX, COUNT
        mode "count"    -> COUNT (non-null) — e.g. invoice line number = 1/row
        mode "distinct" -> COUNT(DISTINCT) + COUNT — e.g. unique invoice numbers

    Columns and the table are whitelisted; filters are parameterized; no joins.
    """
    columns = _validate_columns(metadata, request.columns)

    select_parts = ["COUNT(*) AS row_count"]
    aggregations: List[dict] = []
    for col in columns:
        mode = metadata.get_field(col).aggregate
        if mode not in {"sum", "count", "distinct"}:
            continue
        i = len(aggregations)
        qc = metadata.quoted_column(col)  # safe: already whitelisted
        # COUNT of non-null values is always available.
        select_parts.append(f"COUNT({qc}) AS cnt_{i}")
        if mode == "sum":
            select_parts.extend([
                f"SUM({qc}) AS sum_{i}",
                f"AVG(CAST({qc} AS FLOAT)) AS avg_{i}",
                f"MIN({qc}) AS min_{i}",
                f"MAX({qc}) AS max_{i}",
            ])
        elif mode == "distinct":
            select_parts.append(f"COUNT(DISTINCT {qc}) AS dct_{i}")
        aggregations.append({"column": col, "mode": mode})

    where_sql, where_params = _build_where(metadata, request)
    sql = (
        f"SELECT {', '.join(select_parts)} "
        f"FROM {metadata.quoted_table()}{where_sql}"
    )
    return BuiltAggregate(
        sql=sql, params=where_params, aggregations=aggregations
    )
