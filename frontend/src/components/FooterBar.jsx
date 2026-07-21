// Sticky footer: save/load report templates on the left; Reset and Export to
// Excel actions on the right (mirrors the Catalyst SAVE / RESET footer).
export default function FooterBar({
  templates,
  templateName,
  onNameChange,
  onSave,
  onLoad,
  onReset,
  onExport,
  onExportCsv,
  saving,
  exporting,
  exportingCsv,
}) {
  return (
    <footer className="footer-bar">
      <div className="footer-left">
        <input
          type="text"
          className="footer-input"
          placeholder="Report name"
          value={templateName}
          onChange={(e) => onNameChange(e.target.value)}
        />
        <button
          type="button"
          className="footer-btn primary"
          onClick={onSave}
          disabled={saving || !templateName.trim()}
        >
          {saving ? "SAVING…" : "SAVE"}
        </button>
        <select
          className="footer-select"
          value=""
          onChange={(e) => e.target.value && onLoad(Number(e.target.value))}
        >
          <option value="">Load report…</option>
          {templates.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </select>
      </div>
      <div className="footer-right">
        <button type="button" className="footer-btn" onClick={onReset}>
          RESET
        </button>
        <button
          type="button"
          className="footer-btn"
          onClick={onExport}
          disabled={exporting || exportingCsv}
        >
          {exporting ? "EXPORTING…" : "EXPORT TO EXCEL"}
        </button>
        <button
          type="button"
          className="footer-btn"
          onClick={onExportCsv}
          disabled={exporting || exportingCsv}
        >
          {exportingCsv ? "EXPORTING…" : "EXPORT TO CSV"}
        </button>
      </div>
    </footer>
  );
}
