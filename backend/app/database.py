"""
SQL Server connectivity (pyodbc).

A thin wrapper that opens short-lived connections using the parameterized
connection string from `config.py`. No ORM is used — queries are built by
`query_builder.py` and executed with bound parameters here.
"""
import contextlib
from typing import Any, Generator, Iterator, List, Sequence, Tuple

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


def stream_rows(
    sql: str, params: Sequence[Any], batch_size: int = 2000
) -> Generator[List[List[Any]], None, None]:
    """
    Execute a SELECT and yield rows in batches without loading the full result
    set into memory.  Each yielded value is a list of rows (list of lists).
    The caller must consume the generator promptly — the DB connection stays
    open until the generator is exhausted or garbage-collected.
    """
    settings = get_settings()
    conn = pyodbc.connect(settings.odbc_connection_string, timeout=10)
    try:
        cursor = conn.cursor()
        cursor.execute(sql, list(params))
        while True:
            batch = cursor.fetchmany(batch_size)
            if not batch:
                break
            yield [list(row) for row in batch]
    finally:
        conn.close()


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
