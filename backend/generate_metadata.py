"""
Metadata config generator.

Reads the column list for the configured master table directly from SQL Server
(INFORMATION_SCHEMA.COLUMNS) using the read-only credentials in your .env, and
writes a ready-to-use metadata_config.json. Friendly display names are derived
from the column names (you can hand-edit them afterwards).

Usage (from the backend/ directory, with the venv active):

    python generate_metadata.py

Options:
    --table dbo.SomeOtherTable   Override the table to introspect.
    --out   metadata_config.json Output path (default: METADATA_CONFIG_PATH).
"""
import argparse
import json
import re
import sys
from pathlib import Path

import pyodbc

from app.config import get_settings

# Map SQL Server data types to the four categories the query builder understands.
_TYPE_MAP = {
    # strings
    "char": "string", "nchar": "string", "varchar": "string",
    "nvarchar": "string", "text": "string", "ntext": "string",
    "uniqueidentifier": "string", "xml": "string",
    # numbers
    "int": "number", "bigint": "number", "smallint": "number",
    "tinyint": "number", "decimal": "number", "numeric": "number",
    "float": "number", "real": "number", "money": "number",
    "smallmoney": "number",
    # dates
    "date": "date", "datetime": "date", "datetime2": "date",
    "smalldatetime": "date", "datetimeoffset": "date", "time": "date",
    # booleans
    "bit": "boolean",
}

_SAFE_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# Ordered grouping rules: the FIRST rule whose predicate matches the (lowercased)
# column name wins, so put more specific prefixes (shipto/billto) before the
# generic ones (customer). This buckets the master table's columns into the
# collapsible categories shown in the left panel of the UI.
_GROUP_RULES = [
    ("Ship To", lambda c: c.startswith("shipto")),
    ("Bill To", lambda c: c.startswith("billto")),
    ("Customer", lambda c: c.startswith("customer")
        or c.startswith("masteraccount") or "currency" in c),
    ("Invoice", lambda c: c.startswith("invoice")),
    ("Sales Order", lambda c: c.startswith("salesorder")),
    ("Salesperson & Manager", lambda c: "salesperson" in c or "salesmanager" in c),
    ("Item & Product", lambda c: c.startswith("item") or c.startswith("alternateitem")
        or c.startswith("product") or c.startswith("family")
        or c.startswith("brand") or c.startswith("category")
        or c.startswith("color") or c.startswith("launch")
        or c.startswith("pmtcode") or c.startswith("associatedbook")
        or c.startswith("reservable") or c.startswith("unitofmeasure")
        or c.startswith("termscode")),
    ("Financials", lambda c: any(k in c for k in (
        "amount", "cost", "price", "margin", "quantity", "exchange",
        "discount", "charge", "freight", "rate"))),
    ("Identifiers", lambda c: c.endswith("id") or c.endswith("key")
        or c.startswith("siteid") or c.startswith("transaction")),
]


def group_for(column: str) -> str:
    """Assign a column to a collapsible category based on its name."""
    lc = column.lower()
    for name, predicate in _GROUP_RULES:
        if predicate(lc):
            return name
    return "Other"


# Columns to leave out of the report entirely (case-insensitive, by name).
EXCLUDE_COLUMNS = {"invoicesequence"}

# Words that mark a numeric column as a true measure (safe to SUM).
_MEASURE_KEYWORDS = (
    "amount", "cost", "price", "margin", "quantity", "charge",
    "freight", "discount", "rate", "exchange",
)


def aggregate_for(column: str, data_type: str) -> str:
    """
    Decide how the Analysis box should aggregate a column:
      "sum"      -> numeric measures (amounts, quantity, cost, …)
      "count"    -> numeric identifiers (line number, key) = 1 per row
      "distinct" -> invoice number (unique count)
      "none"     -> everything else (not aggregated)
    """
    lc = column.lower()
    if data_type == "number":
        if any(k in lc for k in _MEASURE_KEYWORDS):
            return "sum"
        return "count"  # numeric identifiers shouldn't be summed
    if "invoicenumber" in lc:
        return "distinct"
    return "none"


def friendly_name(column: str) -> str:
    """customer_name -> 'Customer Name'; InvoiceDate -> 'Invoice Date'."""
    spaced = re.sub(r"[_\s]+", " ", column)
    spaced = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", spaced)  # camelCase split
    return " ".join(w.capitalize() for w in spaced.split())


def split_table(qualified: str):
    """Return (schema, table) from 'schema.table' or ('dbo', 'table')."""
    parts = qualified.replace("[", "").replace("]", "").split(".")
    if len(parts) == 2:
        return parts[0], parts[1]
    return "dbo", parts[0]


def main() -> int:
    settings = get_settings()
    parser = argparse.ArgumentParser(description="Generate metadata_config.json")
    parser.add_argument("--table", default=None, help="schema.table to introspect")
    parser.add_argument("--out", default=settings.metadata_config_path)
    args = parser.parse_args()

    table_qualified = args.table
    if not table_qualified:
        # Reuse whatever is already in the config as the default target.
        cfg_path = Path(settings.metadata_config_path)
        if not cfg_path.is_absolute():
            cfg_path = Path(__file__).resolve().parent / cfg_path
        table_qualified = json.loads(cfg_path.read_text())["table_name"]

    schema, table = split_table(table_qualified)

    print(f"Connecting to {settings.db_server}/{settings.db_name} ...")
    conn = pyodbc.connect(settings.odbc_connection_string, timeout=15)
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT COLUMN_NAME, DATA_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION
        """,
        [schema, table],
    )
    rows = cursor.fetchall()
    conn.close()

    if not rows:
        print(f"ERROR: no columns found for {schema}.{table}. "
              f"Check the table name and your read permissions.")
        return 1

    fields = []
    skipped = []
    excluded = []
    for column_name, data_type in rows:
        if column_name.lower() in EXCLUDE_COLUMNS:
            excluded.append(column_name)
            continue
        if not _SAFE_IDENTIFIER.match(column_name):
            skipped.append(column_name)
            continue
        mapped = _TYPE_MAP.get(data_type.lower())
        if mapped is None:
            skipped.append(f"{column_name} ({data_type})")
            continue
        fields.append({
            "display_name": friendly_name(column_name),
            "column_name": column_name,
            "data_type": mapped,
            "group": group_for(column_name),
            "aggregate": aggregate_for(column_name, mapped),
        })

    config = {"table_name": f"{schema}.{table}", "fields": fields}

    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = Path(__file__).resolve().parent / out_path
    out_path.write_text(json.dumps(config, indent=2), encoding="utf-8")

    print(f"Wrote {len(fields)} fields to {out_path}")
    counts: dict = {}
    for f in fields:
        counts[f["group"]] = counts.get(f["group"], 0) + 1
    print("Groups: " + ", ".join(f"{g} ({n})" for g, n in sorted(counts.items())))
    agg_counts: dict = {}
    for f in fields:
        agg_counts[f["aggregate"]] = agg_counts.get(f["aggregate"], 0) + 1
    print("Aggregate modes: " + ", ".join(
        f"{m} ({n})" for m, n in sorted(agg_counts.items())))
    if excluded:
        print(f"Excluded by config: {', '.join(excluded)}")
    if skipped:
        print(f"Skipped (unsupported type or unsafe name): {', '.join(skipped)}")
    print("Review the file and tidy up any display names, then restart the API.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
