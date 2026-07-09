#!/bin/bash
# =============================================================================
# Manual one-off deploy to Azure App Service
#
# Use this for your first deploy or to push a hotfix outside of CI.
# For ongoing development, push to main and let GitHub Actions handle it.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Node.js 20+ installed
#   - APP_NAME and RESOURCE_GROUP set below (or as env vars)
# =============================================================================
set -e

APP_NAME="${APP_NAME:-thibaut-querybuilder}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-thibaut-querybuilder}"
SLOT="${SLOT:-staging}"   # deploy to staging; then swap manually in portal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Thibaut Query Builder — Manual Deploy"
echo "    App     : $APP_NAME"
echo "    Slot    : $SLOT"
echo "    Source  : $REPO_ROOT"
echo ""

# ---------------------------------------------------------------------------
# 1. Build the React frontend
# ---------------------------------------------------------------------------
echo "[1/4] Building frontend..."
cd "$REPO_ROOT/frontend"
npm ci --silent
npm run build
echo "      Build complete → frontend/dist/"

# ---------------------------------------------------------------------------
# 2. Create deployment zip
# ---------------------------------------------------------------------------
echo "[2/4] Creating deployment zip..."
cd "$REPO_ROOT"
rm -f deploy.zip

zip -r deploy.zip \
    backend \
    frontend/dist \
    startup.sh \
    -x "backend/.venv/*" \
    -x "backend/.env" \
    -x "backend/report_templates.json" \
    -x "backend/__pycache__/*" \
    -x "backend/app/__pycache__/*" \
    -x "*.pyc" \
    -q

ZIP_SIZE=$(du -sh deploy.zip | cut -f1)
echo "      deploy.zip created ($ZIP_SIZE)"

# ---------------------------------------------------------------------------
# 3. Deploy zip to App Service slot
# ---------------------------------------------------------------------------
echo "[3/4] Deploying to $APP_NAME ($SLOT slot)..."
az webapp deploy \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --slot "$SLOT" \
    --type zip \
    --src-path deploy.zip \
    --async false

echo "      Deploy complete."

# ---------------------------------------------------------------------------
# 4. Smoke test
# ---------------------------------------------------------------------------
echo "[4/4] Waiting 30s for app to start, then smoke testing..."
sleep 30

if [ "$SLOT" = "production" ]; then
    URL="https://$APP_NAME.azurewebsites.net/api/health"
else
    URL="https://$APP_NAME-$SLOT.azurewebsites.net/api/health"
fi

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo "000")

if [ "$STATUS" = "200" ]; then
    echo "      Health check passed (HTTP 200)."
    echo ""
    echo "=== DONE ============================================================="
    echo "  Slot URL : $URL"
    echo ""
    if [ "$SLOT" != "production" ]; then
        echo "  To swap $SLOT → production:"
        echo "    az webapp deployment slot swap \\"
        echo "      --name $APP_NAME \\"
        echo "      --resource-group $RESOURCE_GROUP \\"
        echo "      --slot $SLOT \\"
        echo "      --target-slot production"
    fi
    echo "======================================================================"
else
    echo "      WARNING: Health check returned HTTP $STATUS."
    echo "      Check App Service logs: az webapp log tail --name $APP_NAME --resource-group $RESOURCE_GROUP --slot $SLOT"
    exit 1
fi

# Clean up
rm -f "$REPO_ROOT/deploy.zip"
