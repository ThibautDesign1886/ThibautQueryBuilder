import { useEffect, useMemo, useState } from "react";
import * as api from "./api";
import AttributePanel from "./components/AttributePanel";
import ColumnsPanel from "./components/ColumnsPanel";
import AnalysisPanel from "./components/AnalysisPanel";
import ConditionsPanel from "./components/ConditionsPanel";
import ResultsPanel from "./components/ResultsPanel";
import FooterBar from "./components/FooterBar";
import Login from "./components/Login";
import { operatorMeta, operatorsForType } from "./operators";

let filterId = 0;
const nextId = () => ++filterId;

export default function App() {
  const [fields, setFields] = useState([]);
  const [dataSources, setDataSources] = useState([]); // [{key, label}]
  const [selectedModel, setSelectedModel] = useState("sales");

  const [selected, setSelected] = useState([]); // ordered column_names
  const [titles, setTitles] = useState({}); // column_name -> custom title
  const [sorts, setSorts] = useState([]); // ordered [{column, direction}]
  const [filters, setFilters] = useState([]);
  const [logic, setLogic] = useState("AND");

  const [result, setResult] = useState(null);
  const [analysis, setAnalysis] = useState(null);
  const [templates, setTemplates] = useState([]);
  const [templateName, setTemplateName] = useState("");

  // --- auth state ------------------------------------------------------------
  const [authChecked, setAuthChecked] = useState(false);
  const [authRequired, setAuthRequired] = useState(false);
  const [authed, setAuthed] = useState(false);
  const [loginError, setLoginError] = useState("");
  const [loginBusy, setLoginBusy] = useState(false);
  const [currentUser, setCurrentUser] = useState(null); // { email, auth_mode }

  const [loadingFields, setLoadingFields] = useState(true);
  const [executing, setExecuting] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const fieldByCol = useMemo(
    () => Object.fromEntries(fields.map((f) => [f.column_name, f])),
    [fields]
  );

  // The selected columns as field objects, in selection order.
  const selectedFields = useMemo(
    () => selected.map((c) => fieldByCol[c]).filter(Boolean),
    [selected, fieldByCol]
  );

  const sortByCol = useMemo(() => {
    const m = {};
    for (const s of sorts) m[s.column] = s.direction;
    return m;
  }, [sorts]);

  // --- auth bootstrap --------------------------------------------------------
  useEffect(() => {
    api.setUnauthorizedHandler(() => {
      api.setAuth("");
      setAuthed(false);
      setLoginError("Your session expired — please sign in again.");
    });

    api
      .getConfig()
      .then(async (cfg) => {
        if (cfg?.app_title) document.title = cfg.app_title;
        const mode = cfg.auth_mode ?? (cfg.auth_required ? "password" : "open");
        api.setAuthMode(mode);

        if (mode === "azure_ad") {
          // Azure App Service EasyAuth already authenticated the user.
          // Just load their identity and proceed directly to the app.
          setAuthRequired(false);
          setAuthed(true);
          api.getMe().then(setCurrentUser).catch(() => {});
          return;
        }

        if (!cfg.auth_required) {
          setAuthRequired(false);
          setAuthed(true);
          return;
        }

        setAuthRequired(true);
        // If we already have a saved password, validate it silently.
        const saved = api.getAuth();
        if (saved) {
          try {
            await api.login(saved);
            setAuthed(true);
          } catch (_) {
            api.setAuth("");
          }
        }
      })
      .catch(() => {
        // If config can't load, assume no auth so the app is still usable.
        setAuthRequired(false);
        setAuthed(true);
      })
      .finally(() => setAuthChecked(true));
  }, []);

  // --- load data once authenticated ------------------------------------------
  useEffect(() => {
    if (!authed) return;
    setLoadingFields(true);
    Promise.all([api.getFields(selectedModel), api.getDataSource()])
      .then(([fieldData, dsList]) => {
        setFields(fieldData);
        if (Array.isArray(dsList)) setDataSources(dsList);
      })
      .catch((e) => setError(e.message))
      .finally(() => setLoadingFields(false));
    refreshTemplates();
  }, [authed]);

  // --- switch data model -----------------------------------------------------
  async function handleModelChange(modelKey) {
    if (modelKey === selectedModel) return;
    setSelectedModel(modelKey);
    setSelected([]);
    setSorts([]);
    setTitles({});
    setFilters([]);
    setResult(null);
    setAnalysis(null);
    setError("");
    setNotice("");
    setLoadingFields(true);
    try {
      const fieldData = await api.getFields(modelKey);
      setFields(fieldData);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoadingFields(false);
    }
  }

  function refreshTemplates() {
    api.listTemplates().then(setTemplates).catch(() => {});
  }

  async function handleLogin(password) {
    setLoginBusy(true);
    setLoginError("");
    try {
      await api.login(password);
      api.setAuth(password);
      setAuthed(true);
    } catch (e) {
      setLoginError(e.message || "Incorrect password.");
    } finally {
      setLoginBusy(false);
    }
  }

  // --- column selection ------------------------------------------------------
  function toggleColumn(col) {
    setSelected((prev) => {
      if (prev.includes(col)) {
        // Removing a column also clears its sort and title.
        setSorts((s) => s.filter((x) => x.column !== col));
        setTitles((t) => {
          const { [col]: _drop, ...rest } = t;
          return rest;
        });
        return prev.filter((c) => c !== col);
      }
      return [...prev, col];
    });
  }

  function selectAllInGroup(groupFields) {
    setSelected((prev) => {
      const add = groupFields
        .map((f) => f.column_name)
        .filter((c) => !prev.includes(c));
      return [...prev, ...add];
    });
  }

  function clearAllColumns() {
    setSelected([]);
    setSorts([]);
    setTitles({});
  }

  function setTitle(col, value) {
    setTitles((t) => ({ ...t, [col]: value }));
  }

  // --- sorting ---------------------------------------------------------------
  function setSort(col, direction) {
    setSorts((prev) => {
      const exists = prev.find((s) => s.column === col);
      if (!direction) return prev.filter((s) => s.column !== col);
      if (exists)
        return prev.map((s) => (s.column === col ? { ...s, direction } : s));
      return [...prev, { column: col, direction }];
    });
  }

  // --- conditions / filters --------------------------------------------------
  function addFilter() {
    if (fields.length === 0) return;
    const first = fields[0];
    const ops = operatorsForType(first.data_type);
    setFilters((prev) => [
      ...prev,
      {
        id: nextId(),
        enabled: true,
        column: first.column_name,
        operator: ops[0].id,
        value: "",
        values: ["", ""],
        listText: "",
      },
    ]);
  }

  function removeFilter(idx) {
    setFilters((prev) => prev.filter((_, i) => i !== idx));
  }

  function changeFilter(idx, patch) {
    setFilters((prev) =>
      prev.map((f, i) => {
        if (i !== idx) return f;
        const updated = { ...f, ...patch };
        if (patch.column) {
          const field = fieldByCol[patch.column];
          const ops = operatorsForType(field ? field.data_type : "string");
          if (!ops.some((op) => op.id === updated.operator)) {
            updated.operator = ops[0].id;
          }
        }
        return updated;
      })
    );
  }

  // --- payload ---------------------------------------------------------------
  function buildFilterPayload() {
    return filters
      .filter((f) => f.enabled && fieldByCol[f.column])
      .map((f) => {
        const meta = operatorMeta(f.operator);
        const base = { column: f.column, operator: f.operator };
        if (meta.valueMode === "single") return { ...base, value: f.value };
        if (meta.valueMode === "range") return { ...base, values: f.values };
        if (meta.valueMode === "list") {
          const values = (f.listText || "")
            .split(",")
            .map((s) => s.trim())
            .filter((s) => s.length > 0);
          return { ...base, values };
        }
        return base;
      });
  }

  function buildPayload() {
    // Guard against any stale columns that aren't in the current metadata.
    const validColumns = selected.filter((c) => fieldByCol[c]);
    // Only send title overrides that differ from the default display name.
    const titleOverrides = {};
    for (const col of validColumns) {
      const t = titles[col];
      if (t && t !== fieldByCol[col]?.display_name) titleOverrides[col] = t;
    }
    return {
      model: selectedModel,
      columns: validColumns,
      filters: buildFilterPayload(),
      filter_logic: logic,
      sorts: sorts
        .filter((s) => fieldByCol[s.column])
        .map((s) => ({ column: s.column, direction: s.direction })),
      titles: titleOverrides,
    };
  }

  // --- actions ---------------------------------------------------------------
  async function handleExecute() {
    setError("");
    setNotice("");
    if (selected.length === 0) {
      setError("Select at least one column.");
      return;
    }
    setExecuting(true);
    const payload = buildPayload();
    try {
      // Preview rows and the full-dataset analysis run together on Execute.
      const [previewRes, analysisRes] = await Promise.all([
        api.preview(payload),
        api.analyze(payload),
      ]);
      setResult(previewRes);
      setAnalysis(analysisRes);
    } catch (e) {
      setError(e.message);
      setResult(null);
      setAnalysis(null);
    } finally {
      setExecuting(false);
    }
  }

  async function handleExport() {
    setError("");
    setNotice("");
    if (selected.length === 0) {
      setError("Select at least one column.");
      return;
    }
    setExporting(true);
    try {
      await api.exportExcel(buildPayload());
    } catch (e) {
      setError(e.message);
    } finally {
      setExporting(false);
    }
  }

  async function handleSave() {
    setError("");
    setNotice("");
    setSaving(true);
    try {
      const payload = buildPayload();
      await api.saveTemplate({
        name: templateName.trim(),
        config: {
          model: selectedModel,
          columns: payload.columns,
          filters: payload.filters,
          filter_logic: payload.filter_logic,
          sorts: payload.sorts,
          titles: payload.titles,
        },
      });
      setNotice(`Saved report “${templateName.trim()}”.`);
      refreshTemplates();
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  }

  async function handleLoad(id) {
    setError("");
    setNotice("");
    try {
      const t = await api.loadTemplate(id);
      const cfg = t.config;

      // If the template targets a different model, switch to it first.
      let currentFields = fields;
      const templateModel = cfg.model || "sales";
      if (templateModel !== selectedModel) {
        setSelectedModel(templateModel);
        setLoadingFields(true);
        try {
          currentFields = await api.getFields(templateModel);
          setFields(currentFields);
        } catch (e) {
          setError(e.message);
          return;
        } finally {
          setLoadingFields(false);
        }
      }

      // A saved report may reference fields that have since been removed from
      // the metadata. Drop anything no longer available so the report still
      // loads; the user can re-save to make the cleanup permanent.
      const known = new Set(currentFields.map((f) => f.column_name));
      const dropped = new Set();

      const validColumns = (cfg.columns || []).filter((c) => {
        if (known.has(c)) return true;
        dropped.add(c);
        return false;
      });
      const validSorts = (cfg.sorts || []).filter((s) => known.has(s.column));
      const validTitles = Object.fromEntries(
        Object.entries(cfg.titles || {}).filter(([k]) => known.has(k))
      );
      const validFilters = (cfg.filters || []).filter((f) => {
        if (known.has(f.column)) return true;
        dropped.add(f.column);
        return false;
      });

      setSelected(validColumns);
      setTitles(validTitles);
      setSorts(validSorts);
      setLogic(cfg.filter_logic || "AND");
      setTemplateName(t.name);
      setFilters(
        validFilters.map((f) => {
          const meta = operatorMeta(f.operator);
          return {
            id: nextId(),
            enabled: true,
            column: f.column,
            operator: f.operator,
            value: meta.valueMode === "single" ? f.value ?? "" : "",
            values: meta.valueMode === "range" ? f.values ?? ["", ""] : ["", ""],
            listText:
              meta.valueMode === "list" ? (f.values || []).join(", ") : "",
          };
        })
      );
      setResult(null);
      setAnalysis(null);
      if (dropped.size > 0) {
        setNotice(
          `Loaded “${t.name}”. Removed fields no longer available: ` +
            `${[...dropped].join(", ")}. Save to update the report.`
        );
      } else {
        setNotice(`Loaded report “${t.name}”.`);
      }
    } catch (e) {
      setError(e.message);
    }
  }

  function handleReset() {
    setSelected([]);
    setTitles({});
    setSorts([]);
    setFilters([]);
    setLogic("AND");
    setResult(null);
    setAnalysis(null);
    setTemplateName("");
    setError("");
    setNotice("");
  }

  if (!authChecked) {
    return <div className="boot-screen">Loading…</div>;
  }

  if (authRequired && !authed) {
    return <Login onSubmit={handleLogin} error={loginError} busy={loginBusy} />;
  }

  return (
    <div className="catalyst">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark">▣</span>
          <span className="brand-name">Thibaut Query Builder</span>
        </div>
        {currentUser?.email && (
          <div className="topbar-user">{currentUser.email}</div>
        )}
      </header>

      <nav className="tabbar">
        <span className="tab">Detail</span>
        <span className="tab active">Query Builder</span>
      </nav>

      <main className="workspace">
        {error && <div className="alert alert-error">{error}</div>}
        {notice && <div className="alert alert-info">{notice}</div>}

        {loadingFields ? (
          <div className="panel">
            <div className="panel-body">Loading fields…</div>
          </div>
        ) : (
          <div className="layout">
            <div className="layout-left">
              <AttributePanel
                dataSources={dataSources}
                selectedModel={selectedModel}
                onModelChange={handleModelChange}
                fields={fields}
                selected={selected}
                onToggle={toggleColumn}
                onSelectAllInGroup={selectAllInGroup}
                onClearAll={clearAllColumns}
              />
            </div>

            <div className="layout-right">
              <div className="row-two">
                <div className="grow">
                  <ColumnsPanel
                    columns={selectedFields}
                    titles={titles}
                    sortByCol={sortByCol}
                    onTitleChange={setTitle}
                    onSetSort={setSort}
                    onRemove={toggleColumn}
                  />
                </div>
                <div className="sorting-col">
                  <AnalysisPanel analysis={analysis} loading={executing} />
                </div>
              </div>

              <ConditionsPanel
                fields={fields}
                filters={filters}
                logic={logic}
                onLogicChange={setLogic}
                onAdd={addFilter}
                onRemove={removeFilter}
                onChange={changeFilter}
              />

              <ResultsPanel
                result={result}
                executing={executing}
                onExecute={handleExecute}
              />
            </div>
          </div>
        )}
      </main>

      <FooterBar
        templates={templates}
        templateName={templateName}
        onNameChange={setTemplateName}
        onSave={handleSave}
        onLoad={handleLoad}
        onReset={handleReset}
        onExport={handleExport}
        saving={saving}
        exporting={exporting}
      />
    </div>
  );
}
