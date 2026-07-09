"""
SQL Server connectivity (pyodbc).

A thin wrapper that opens short-lived connections using the parameterized
connection string from `config.py`. No ORM is used — queries are built by
`query_builder.py` and executed with bound parameters here.
"""
import contextlib
from typing import Any, Iterator, List, Sequence, Tuple

import pyodbc

from .config import get_settings


@contextlib.contextmanager
def get_connection() -> Iterator[pyodbc.Connection]:
    """Yield a pyodbc connection and guarantee it is closed afterwards."""
    settings = get_settings()
    conn = pyodbc.connect(settings.odbc_connection_string, timeout=10)
    try:
        yield conn
    finally:
        conn.close()


def run_select(sql: str, params: Sequence[Any]) -> Tuple[List[str], List[List[Any]]]:
    """
    Execute a parameterized SELECT and return (column_names, rows).

    `params` are bound positionally to the `?` placeholders in `sql` — values
    are never interpolated into the SQL text.
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, list(params))
        columns = [col[0] for col in cursor.description]
        rows = [list(row) for row in cursor.fetchall()]
        return columns, rows


def execute(sql: str, params: Sequence[Any] = ()) -> None:
    """Execute a parameterized non-query statement (INSERT/UPDATE/DDL)."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, list(params))
        conn.commit()


def execute_returning_scalar(sql: str, params: Sequence[Any] = ()) -> Any:
    """Execute a statement and return the first column of the first row."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, list(params))
        row = cursor.fetchone()
        conn.commit()
        return row[0] if row else None
