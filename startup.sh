#!/bin/bash
# ---------------------------------------------------------------------------
# App Service startup script
# Azure calls this once per container start (after deploy and after restarts).
#
# ODBC driver installation is done in the background so uvicorn can start
# immediately and respond to Azure's health probes. The marker file at
# /home/.odbc_driver_installed persists across restarts so the install only
# runs once per container instance.
# ---------------------------------------------------------------------------

ODBC_MARKER="/home/.odbc_driver_installed"
VENV="/home/site/wwwroot/.venv"

# ---------------------------------------------------------------------------
# Install ODBC driver in the background (first run only)
# ---------------------------------------------------------------------------
if [ ! -f "$ODBC_MARKER" ]; then
    echo "[startup] Installing ODBC Driver 18 for SQL Server (background)..."
    (
        set -e
        curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor > /usr/share/keyrings/microsoft.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
            https://packages.microsoft.com/debian/11/prod bullseye main" \
            > /etc/apt/sources.list.d/mssql-release.list
        apt-get update -qq
        ACCEPT_EULA=Y apt-get install -y -qq msodbcsql18
        touch "$ODBC_MARKER"
        echo "[startup] ODBC driver installed."
    ) &
fi

# ---------------------------------------------------------------------------
# Install / refresh Python dependencies into a cached venv on /home
# (persisted across restarts, much faster on subsequent starts)
# ---------------------------------------------------------------------------
if [ ! -d "$VENV" ]; then
    echo "[startup] Creating virtual environment..."
    python -m venv "$VENV"
fi

source "$VENV/bin/activate"
echo "[startup] Installing Python dependencies..."
pip install -r /home/site/wwwroot/backend/requirements.txt --quiet --no-cache-dir

# ---------------------------------------------------------------------------
# Start the application
# ---------------------------------------------------------------------------
echo "[startup] Starting Thibaut Query Builder..."
cd /home/site/wwwroot/backend
exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --workers 2 \
    --log-level info
