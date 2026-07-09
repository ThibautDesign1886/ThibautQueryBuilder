#!/bin/bash
# =============================================================================
# Custom domain + free managed TLS certificate
#
# Run AFTER provision.sh and AFTER you've added the DNS records below.
#
# Prerequisites:
#   1. Azure CLI installed and logged in
#   2. Your domain's DNS is managed in a place you can add records
#   3. Run this script to get the verification ID, add the DNS records,
#      then re-run (or continue) once DNS has propagated (~5–10 min)
# =============================================================================
set -e

# ---------------------------------------------------------------------------
# EDIT THESE VALUES
# ---------------------------------------------------------------------------
RESOURCE_GROUP="rg-thibaut-querybuilder"
APP_NAME="thibaut-querybuilder"
CUSTOM_DOMAIN="querybuilder.thibautdesign.com"   # e.g. tools.yourcompany.com

# ---------------------------------------------------------------------------
# Step 1 — Print DNS records to add at your DNS provider
# ---------------------------------------------------------------------------
echo "==> Fetching domain verification ID..."
VERIFY_ID=$(az webapp show \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query customDomainVerificationId \
    --output tsv)

echo ""
echo "=== ADD THESE DNS RECORDS BEFORE CONTINUING =========================="
echo ""
echo "  Record 1 (CNAME — points your domain to App Service):"
echo "    Type  : CNAME"
echo "    Name  : $(echo $CUSTOM_DOMAIN | cut -d'.' -f1)"
echo "    Value : $APP_NAME.azurewebsites.net"
echo ""
echo "  Record 2 (TXT — proves you own the domain):"
echo "    Type  : TXT"
echo "    Name  : asuid.$(echo $CUSTOM_DOMAIN | cut -d'.' -f1)"
echo "    Value : $VERIFY_ID"
echo ""
echo "  Wait 5–10 minutes for DNS to propagate, then press Enter to continue."
echo "======================================================================"
echo ""
read -p "Press Enter once DNS records are in place..."

# ---------------------------------------------------------------------------
# Step 2 — Bind the custom hostname to the App Service
# ---------------------------------------------------------------------------
echo ""
echo "[1/4] Binding hostname $CUSTOM_DOMAIN..."
az webapp config hostname add \
    --webapp-name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --hostname "$CUSTOM_DOMAIN" \
    --output none
echo "      Done."

# ---------------------------------------------------------------------------
# Step 3 — Create a free managed TLS certificate
# ---------------------------------------------------------------------------
echo "[2/4] Creating managed TLS certificate (free, auto-renews)..."
az webapp config ssl create \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --hostname "$CUSTOM_DOMAIN" \
    --output none
echo "      Done."

# ---------------------------------------------------------------------------
# Step 4 — Get the certificate thumbprint and bind it
# ---------------------------------------------------------------------------
echo "[3/4] Binding TLS certificate..."
THUMBPRINT=$(az webapp config ssl list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?subjectName=='$CUSTOM_DOMAIN'].thumbprint | [0]" \
    --output tsv)

az webapp config ssl bind \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --certificate-thumbprint "$THUMBPRINT" \
    --ssl-type SNI \
    --output none
echo "      Done."

# ---------------------------------------------------------------------------
# Step 5 — Enforce HTTPS (redirect HTTP → HTTPS)
# ---------------------------------------------------------------------------
echo "[4/4] Enforcing HTTPS-only..."
az webapp update \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --https-only true \
    --output none
echo "      Done."

# ---------------------------------------------------------------------------
# Update CORS to include the custom domain
# ---------------------------------------------------------------------------
echo "Updating CORS to include custom domain..."
az webapp config appsettings set \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --output none \
    --settings CORS_ORIGINS="https://$CUSTOM_DOMAIN,https://$APP_NAME.azurewebsites.net"

echo ""
echo "=== DONE ============================================================="
echo ""
echo "  Your app is live at: https://$CUSTOM_DOMAIN"
echo ""
echo "  TLS certificate will auto-renew 30 days before expiry."
echo "======================================================================"
