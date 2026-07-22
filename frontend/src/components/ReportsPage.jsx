import { useEffect, useMemo, useState } from "react";
import * as api from "../api";

// SVG icon helpers
function IconTable() {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" width="16" height="16">
      <rect x="2" y="3" width="16" height="14" rx="2" />
      <line x1="2" y1="8" x2="18" y2="8" />
      <line x1="7" y1="8" x2="7" y2="17" />
    </svg>
  );
}

function IconDownload() {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" width="16" height="16">
      <path d="M10 3v10m0 0-3-3m3 3 3-3" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M3 14v1a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-1" strokeLinecap="round" />
    </svg>
  );
}

function IconCsv() {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" width="16" height="16">
      <path d="M4 4h7l5 5v7a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z" />
      <path d="M11 4v5h5" strokeLinecap="round" />
      <path d="M7 13c-.6 0-1-.4-1-1s.4-1 1-1h.5" strokeLinecap="round" />
      <path d="M10.5 11l.5 2-.5 2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M13 11v4" strokeLinecap="round" />
    </svg>
  );
}

function IconDuplicate() {
  return (
    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" width="16" height="16">
      <rect x="7" y="7" width="10" height="10" rx="1.5" />
      <path d="M13 7V5a1 1 0 0 0-1-1H3a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h2" strokeLinecap="round" />
    </svg>
  );
}

function formatDate(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}.${m}.${day}`;
}

const RECENT_KEY = "qb_recent_reports";
const MAX_RECENT = 10;

function getRecent() {
  try {
    return JSON.parse(sessionStorage.getItem(RECENT_KEY) || "[]");
  } catch {
    return [];
  }
}

function pushRecent(id) {
  const list = getRecent().filter((x) => x !== id);
  list.unshift(id);
  sessionStorage.setItem(RECENT_KEY, JSON.stringify(list.slice(0, MAX_RECENT)));
}

export default function ReportsPage({ dataSources, onOpen }) {
  const [templates, setTemplates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [filterModel, setFilterModel] = useState("");
  const [activeTab, setActiveTab] = useState("public");
  const [exportingId, setExportingId] = useState(null);
  const [exportingCsvId, setExportingCsvId] = useState(null);
  const [duplicatingId, setDuplicatingId] = useState(null);
  const [error, setError] = useState("");
  const [recentIds, setRecentIds] = useState(getRecent);

  useEffect(() => {
    setLoading(true);
    api
      .listTemplates()
      .then(setTemplates)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  const filtered = useMemo(() => {
    let list = templates;
    if (activeTab === "recent") {
      list = recentIds
        .map((id) => templates.find((t) => t.id === id))
        .filter(Boolean);
    }
    if (filterModel) list = list.filter((t) => t.model === filterModel);
    if (search) {
      const q = search.toLowerCase();
      list = list.filter((t) => t.name.toLowerCase().includes(q));
    }
    return list;
  }, [templates, activeTab, recentIds, filterModel, search]);

  function handleOpen(id) {
    pushRecent(id);
    setRecentIds(getRecent());
    onOpen(id);
  }

  async function handleExportExcel(id) {
    setError("");
    setExportingId(id);
    try {
      const t = await api.loadTemplate(id);
      await api.exportExcel(t.config);
    } catch (e) {
      setError(e.message);
    } finally {
      setExportingId(null);
    }
  }

  async function handleExportCsv(id) {
    setError("");
    setExportingCsvId(id);
    try {
      const t = await api.loadTemplate(id);
      await api.exportCsv(t.config);
    } catch (e) {
      setError(e.message);
    } finally {
      setExportingCsvId(null);
    }
  }

  async function handleDuplicate(t) {
    setError("");
    setDuplicatingId(t.id);
    try {
      const full = await api.loadTemplate(t.id);
      await api.saveTemplate({
        name: `${t.name} (Copy)`,
        config: full.config,
      });
      const updated = await api.listTemplates();
      setTemplates(updated);
    } catch (e) {
      setError(e.message);
    } finally {
      setDuplicatingId(null);
    }
  }

  const modelLabel = (key) => {
    const ds = dataSources.find((d) => d.key === key);
    return ds ? ds.label : key;
  };

  return (
    <main className="reports-page">
      {error && <div className="alert alert-error">{error}</div>}

      <div className="reports-tabs">
        <button
          className={`reports-tab${activeTab === "public" ? " active" : ""}`}
          onClick={() => setActiveTab("public")}
        >
          Public Reports
          <span className="reports-tab-badge">{templates.length}</span>
        </button>
        <button
          className={`reports-tab${activeTab === "recent" ? " active" : ""}`}
          onClick={() => setActiveTab("recent")}
        >
          Recently Viewed
        </button>
      </div>

      <div className="reports-filters">
        <select
          className="reports-filter-select"
          value={filterModel}
          onChange={(e) => setFilterModel(e.target.value)}
        >
          <option value="">Select data source</option>
          {dataSources.map((ds) => (
            <option key={ds.key} value={ds.key}>
              {ds.label}
            </option>
          ))}
        </select>

        <div className="reports-search-wrap">
          <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" width="15" height="15" className="reports-search-icon">
            <circle cx="8.5" cy="8.5" r="5.5" />
            <path d="m14 14 2.5 2.5" strokeLinecap="round" />
          </svg>
          <input
            type="text"
            className="reports-search"
            placeholder="Search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className="reports-list">
        {loading ? (
          <div className="reports-empty">Loading reports…</div>
        ) : filtered.length === 0 ? (
          <div className="reports-empty">
            {activeTab === "recent"
              ? "No recently viewed reports."
              : "No reports found."}
          </div>
        ) : (
          filtered.map((t) => (
            <div className="report-card" key={t.id}>
              <div className="report-card-body">
                <button
                  className="report-card-name"
                  onClick={() => handleOpen(t.id)}
                >
                  {t.name}
                </button>
                <div className="report-card-meta">
                  {t.model && (
                    <span className="report-card-model">
                      {modelLabel(t.model)}
                    </span>
                  )}
                  {t.created_at && (
                    <span>Created: <strong>{formatDate(t.created_at)}</strong></span>
                  )}
                  {t.updated_at && (
                    <span>Last change: <strong>{formatDate(t.updated_at)}</strong></span>
                  )}
                </div>
              </div>

              <div className="report-card-actions">
                <button
                  className="report-action-btn"
                  title="Open in Query Builder"
                  onClick={() => handleOpen(t.id)}
                >
                  <IconTable />
                </button>
                <button
                  className="report-action-btn"
                  title="Export to Excel"
                  onClick={() => handleExportExcel(t.id)}
                  disabled={exportingId === t.id}
                >
                  {exportingId === t.id ? (
                    <span className="report-action-spinner" />
                  ) : (
                    <IconDownload />
                  )}
                </button>
                <button
                  className="report-action-btn"
                  title="Export to CSV"
                  onClick={() => handleExportCsv(t.id)}
                  disabled={exportingCsvId === t.id}
                >
                  {exportingCsvId === t.id ? (
                    <span className="report-action-spinner" />
                  ) : (
                    <IconCsv />
                  )}
                </button>
                <button
                  className="report-action-btn"
                  title="Duplicate"
                  onClick={() => handleDuplicate(t)}
                  disabled={duplicatingId === t.id}
                >
                  {duplicatingId === t.id ? (
                    <span className="report-action-spinner" />
                  ) : (
                    <IconDuplicate />
                  )}
                </button>
              </div>
            </div>
          ))
        )}
      </div>
    </main>
  );
}
