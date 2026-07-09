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
SITE="/home/site/wwwroot"

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
# Python deps are pre-bundled in backend/site-packages by the CI build.
# Just point Python at them — no pip install needed at runtime.
# ---------------------------------------------------------------------------
export PYTHONPATH="$SITE/backend/site-packages:$PYTHONPATH"

# ---------------------------------------------------------------------------
# Start the application immediately
# ---------------------------------------------------------------------------
echo "[startup] Starting Thibaut Query Builder..."
cd "$SITE/backend"
exec python -m uvicorn app.main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --workers 2 \
    --log-level info
