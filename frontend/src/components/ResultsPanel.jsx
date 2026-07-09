// "Results" panel: an Execute button that runs the preview (first 100 rows) and
// renders them in a grid, or a message when there are no records.
export default function ResultsPanel({ result, executing, onExecute }) {
  return (
    <section className="panel panel-results">
      <div className="panel-head">
        <h2>Results</h2>
        <div className="panel-head-actions">
          {result && result.row_count > 0 && (
            <span className="badge">{result.row_count} rows</span>
          )}
          <button
            type="button"
            className="execute-btn"
            onClick={onExecute}
            disabled={executing}
          >
            {executing ? "EXECUTING…" : "EXECUTE"}
          </button>
        </div>
      </div>
      <div className="panel-body">
        {!result && (
          <p className="muted">
            Click <strong>Execute</strong> to preview the first 100 rows.
          </p>
        )}
        {result && result.row_count === 0 && (
          <div className="empty-state">{result.message || "No records found."}</div>
        )}
        {result && result.row_count > 0 && (
          <div className="table-scroll">
            <table className="results-table">
              <thead>
                <tr>
                  {result.display_names.map((name, i) => (
                    <th key={i}>{name}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {result.rows.map((row, rIdx) => (
                  <tr key={rIdx}>
                    {row.map((cell, cIdx) => (
                      <td key={cIdx}>{cell === null ? "" : String(cell)}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </section>
  );
}
