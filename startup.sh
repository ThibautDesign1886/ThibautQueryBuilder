#!/bin/bash
# ---------------------------------------------------------------------------
# App Service startup script
# Azure calls this once per container start (after deploy and after restarts).
#
# App Service Linux Python images don't include the SQL Server ODBC driver
# by default. The block below installs it the first time and caches it in
# /home so subsequent restarts skip the download.
# ---------------------------------------------------------------------------
set -e

ODBC_MARKER="/home/.odbc_driver_installed"

if [ ! -f "$ODBC_MARKER" ]; then
    echo "[startup] Installing ODBC Driver 18 for SQL Server..."
    # Debian 11 (Bullseye) — the runtime image used by App Service Python
    curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor > /usr/share/keyrings/microsoft.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
        https://packages.microsoft.com/debian/11/prod bullseye main" \
        > /etc/apt/sources.list.d/mssql-release.list
    apt-get update -qq
    ACCEPT_EULA=Y apt-get install -y -qq msodbcsql18
    touch "$ODBC_MARKER"
    echo "[startup] ODBC driver installed."
fi

# ---------------------------------------------------------------------------
# Install / refresh Python dependencies
# ---------------------------------------------------------------------------
cd /home/site/wwwroot/backend
pip install -r requirements.txt --quiet --no-cache-dir

# ---------------------------------------------------------------------------
# Start the application
# ---------------------------------------------------------------------------
echo "[startup] Starting Thibaut Query Builder..."
exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --workers 2 \
    --log-level info
