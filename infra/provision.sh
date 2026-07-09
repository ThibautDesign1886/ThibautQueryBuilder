#!/bin/bash
# =============================================================================
# Thibaut Query Builder — Azure App Service Provisioning
#
# Run this once to create the App Service infrastructure.
# Prerequisites:
#   1. Azure CLI installed (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
#   2. Logged in: az login
#   3. Right subscription selected: az account set --subscription "<name or id>"
#
# Usage:
#   chmod +x infra/provision.sh
#   ./infra/provision.sh
# =============================================================================
set -e

# ---------------------------------------------------------------------------
# EDIT THESE VALUES before running
# ---------------------------------------------------------------------------
RESOURCE_GROUP="rg-thibaut-querybuilder"      # your existing resource group
LOCATION="eastus"                              # match your SQL Server region
PLAN_NAME="asp-thibaut-querybuilder"
APP_NAME="thibaut-querybuilder"                # must be globally unique (.azurewebsites.net)
PYTHON_VERSION="3.11"

# SQL Server (already in Azure)
DB_SERVER="your-server.database.windows.net"  # e.g. myserver.database.windows.net
DB_NAME="your-database-name"
DB_USER="your-db-user"
DB_PASSWORD="your-db-password"                # use Key Vault in production

echo "==> Provisioning Thibaut Query Builder on Azure App Service"
echo "    Resource group : $RESOURCE_GROUP"
echo "    App name       : $APP_NAME"
echo "    Location       : $LOCATION"
echo ""

# ---------------------------------------------------------------------------
# 1. App Service Plan — Linux P0v3 (~$75/month)
#    P0v3 = 1 vCPU, 4 GB RAM, deployment slots, VNet integration
# ---------------------------------------------------------------------------
echo "[1/6] Creating App Service Plan ($PLAN_NAME)..."
az appservice plan create \
    --name "$PLAN_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku P0V3 \
    --is-linux \
    --output none

echo "      Done."

# ---------------------------------------------------------------------------
# 2. Web App
# ---------------------------------------------------------------------------
echo "[2/6] Creating Web App ($APP_NAME)..."
az webapp create \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$PLAN_NAME" \
    --runtime "PYTHON:$PYTHON_VERSION" \
    --output none

echo "      Done."

# ---------------------------------------------------------------------------
# 3. Startup command — points to the startup.sh at the repo root
# ---------------------------------------------------------------------------
echo "[3/6] Setting startup command..."
az webapp config set \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --startup-file "/home/site/wwwroot/startup.sh" \
    --output none

echo "      Done."

# ---------------------------------------------------------------------------
# 4. Application Settings (environment variables)
#    These override / replace the .env file in production.
#    AUTH_MODE=azure_ad is set here; EasyAuth will be enabled separately.
# ---------------------------------------------------------------------------
echo "[4/7] Creating Application Insights resource..."
az extension add --name application-insights --only-show-errors 2>/dev/null || true
az monitor app-insights component create \
    --app "$APP_NAME-insights" \
    --location "$LOCATION" \
    --resource-group "$RESOURCE_GROUP" \
    --application-type web \
    --output none

AI_CONNECTION_STRING=$(az monitor app-insights component show \
    --app "$APP_NAME-insights" \
    --resource-group "$RESOURCE_GROUP" \
    --query connectionString \
    --output tsv)

echo "      Done. Connection string captured."

echo "[5/7] Setting application settings..."
az webapp config appsettings set \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --output none \
    --settings \
        AUTH_MODE="azure_ad" \
        DB_DRIVER="ODBC Driver 18 for SQL Server" \
        DB_SERVER="$DB_SERVER" \
        DB_PORT="1433" \
        DB_NAME="$DB_NAME" \
        DB_USER="$DB_USER" \
        DB_PASSWORD="$DB_PASSWORD" \
        DB_ENCRYPT="yes" \
        DB_TRUST_SERVER_CERTIFICATE="no" \
        METADATA_CONFIG_PATH="metadata_config.json" \
        PREVIEW_ROW_LIMIT="100" \
        EXPORT_ROW_LIMIT="500000" \
        CORS_ORIGINS="https://$APP_NAME.azurewebsites.net" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="false" \
        WEBSITES_PORT="8000" \
        APPLICATIONINSIGHTS_CONNECTION_STRING="$AI_CONNECTION_STRING"

echo "      Done."

# ---------------------------------------------------------------------------
# 5. Staging deployment slot
#    Lets you deploy to staging, verify, then swap to production (zero downtime).
# ---------------------------------------------------------------------------
echo "[6/7] Creating staging deployment slot..."
az webapp deployment slot create \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --slot "staging" \
    --output none

# Copy settings to the staging slot
az webapp config appsettings set \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --slot "staging" \
    --output none \
    --settings \
        AUTH_MODE="password" \
        APP_PASSWORD="StagingPassword123" \
        DB_DRIVER="ODBC Driver 18 for SQL Server" \
        DB_SERVER="$DB_SERVER" \
        DB_PORT="1433" \
        DB_NAME="$DB_NAME" \
        DB_USER="$DB_USER" \
        DB_PASSWORD="$DB_PASSWORD" \
        DB_ENCRYPT="yes" \
        DB_TRUST_SERVER_CERTIFICATE="no" \
        METADATA_CONFIG_PATH="metadata_config.json" \
        PREVIEW_ROW_LIMIT="100" \
        EXPORT_ROW_LIMIT="500000" \
        CORS_ORIGINS="https://$APP_NAME-staging.azurewebsites.net" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="false" \
        WEBSITES_PORT="8000" \
        APPLICATIONINSIGHTS_CONNECTION_STRING="$AI_CONNECTION_STRING"

echo "      Done."

# ---------------------------------------------------------------------------
# 6. Allow App Service outbound IPs on the SQL Server firewall
#    Get the outbound IPs and print them — you'll need to add them to
#    your SQL Server firewall rules manually (or via az sql server firewall-rule).
# ---------------------------------------------------------------------------
echo "[7/7] Fetching outbound IPs for SQL Server firewall..."
OUTBOUND_IPS=$(az webapp show \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "outboundIpAddresses" \
    --output tsv)

echo ""
echo "=== DONE ============================================================="
echo ""
echo "App URL  : https://$APP_NAME.azurewebsites.net"
echo "Staging  : https://$APP_NAME-staging.azurewebsites.net"
echo ""
echo "ACTION REQUIRED — Add these IPs to your SQL Server firewall:"
echo "  $OUTBOUND_IPS" | tr ',' '\n' | xargs -I{} echo "  az sql server firewall-rule create --resource-group $RESOURCE_GROUP --server <sql-server-name> --name AppService-{} --start-ip-address {} --end-ip-address {}"
echo ""
echo "NEXT STEPS:"
echo "  1. Run backend/sql/create_templates_table.sql on your SQL Server"
echo "  2. Register Azure AD App Registration (see README)"
echo "  3. Enable App Service EasyAuth in the portal"
echo "  4. Deploy the app (see CI/CD setup)"
echo "======================================================================"
