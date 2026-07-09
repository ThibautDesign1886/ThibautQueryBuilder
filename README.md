# Thibaut Query Builder

Internal web app for building and exporting SQL queries against Thibaut's master dataset. Users select columns, apply filter conditions, sort results, preview the first 100 rows, run aggregation analysis, and export to Excel — all without writing any SQL.

## Tech stack

| Layer | Technology |
|---|---|
| Backend | Python 3.11 · FastAPI · pyodbc |
| Frontend | React 18 · Vite |
| Database | SQL Server (Azure SQL) |
| Hosting | Azure App Service (Linux, Python) |
| Auth | Azure AD SSO via App Service EasyAuth (production) · shared password (staging) · open (local dev) |
| CI/CD | GitHub Actions → staging slot → production swap |
| Monitoring | Azure Application Insights (OpenTelemetry) |

## Local development

### Prerequisites

- Python 3.11+
- Node.js 20+
- [ODBC Driver 18 for SQL Server](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server) installed locally
- Access to the Thibaut SQL Server (or a local copy of the master table)

### Backend

```bash
cd backend

# Copy the example env file and fill in your values
cp .env.example .env
# Edit .env — at minimum set DB_SERVER, DB_NAME, DB_USER, DB_PASSWORD

# Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start the API (runs at http://localhost:8000)
uvicorn app.main:app --reload --port 8000
```

The API docs are available at http://localhost:8000/docs.

### Frontend

```bash
cd frontend

# Install dependencies
npm install

# Start the Vite dev server (runs at http://localhost:5173)
npm run dev
```

The dev server proxies `/api` requests to the FastAPI backend at `http://127.0.0.1:8000`, so you only need one browser tab.

## Environment variables

All backend configuration is controlled by environment variables. Copy `backend/.env.example` to `backend/.env` for local development. In production these are set as Azure App Service Application Settings.

See [`backend/.env.example`](backend/.env.example) for the full list and descriptions.

Key variables:

| Variable | Default | Description |
|---|---|---|
| `DB_SERVER` | — | Azure SQL Server hostname |
| `DB_NAME` | — | Database name |
| `DB_USER` | — | SQL login username |
| `DB_PASSWORD` | — | SQL login password |
| `AUTH_MODE` | `open` | `open` (local) · `password` (staging) · `azure_ad` (production) |
| `APP_PASSWORD` | — | Shared password when `AUTH_MODE=password` |
| `PREVIEW_ROW_LIMIT` | `100` | Max rows returned by /api/preview |
| `EXPORT_ROW_LIMIT` | `500000` | Max rows returned by /api/export |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | — | Leave blank to disable telemetry locally |

## Deployment

Deployment is automated via GitHub Actions (`.github/workflows/deploy.yml`).

**Workflow:**

1. Every push to `main` triggers a build: the React frontend is compiled with `npm run build` and a `deploy.zip` is created.
2. The zip is deployed to the **staging slot** of the Azure App Service.
3. A smoke test hits `/api/health` on the staging URL.
4. If the smoke test passes, the staging slot is swapped into **production** (zero-downtime).
5. Pull requests trigger a build-only run — no deployment.

**Required GitHub configuration:**

- **Secret** `AZURE_CREDENTIALS` — service principal JSON (see workflow file for the `az ad sp create-for-rbac` command)
- **Variable** `APP_NAME` — your App Service name (e.g. `thibaut-querybuilder`)
- **Variable** `RESOURCE_GROUP` — your resource group (e.g. `rg-thibaut-querybuilder`)

### First-time infrastructure setup

```bash
# Edit the variables at the top of the script, then:
chmod +x infra/provision.sh
./infra/provision.sh
```

This creates the App Service Plan, Web App, staging slot, Application Insights resource, and prints the outbound IPs to add to the SQL Server firewall.

### Manual deploy (outside of CI)

```bash
chmod +x scripts/deploy-manual.sh
./scripts/deploy-manual.sh
```

### Custom domain + TLS

```bash
chmod +x infra/setup-domain.sh
./infra/setup-domain.sh
```

## Database setup

Run the following SQL scripts once against your SQL Server before first use:

```bash
# Creates the dbo.report_templates table (for saved report templates)
backend/sql/create_templates_table.sql
```

The `backend/sql/sample_master_table.sql` script creates a `dbo.MasterReportTable` with sample data for local testing. In production this is replaced by the real master table configured in `backend/metadata_config.json`.

## Metadata configuration

`backend/metadata_config.json` defines:
- The single master table used as the data source (`table_name`)
- Every column available in the query builder (`fields`) — only whitelisted columns can ever appear in a generated query

To regenerate the metadata from the live table schema:

```bash
cd backend
python generate_metadata.py
```

This introspects `INFORMATION_SCHEMA.COLUMNS` and writes an updated `metadata_config.json`. Review and tidy the display names before restarting the API.
