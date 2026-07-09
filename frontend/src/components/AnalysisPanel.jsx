// "Analysis" panel: a quick summary of the full filtered dataset — total row
// count plus totals (and avg/min/max) for each selected numeric column.
const fmtInt = (n) =>
  n == null ? "—" : Number(n).toLocaleString(undefined, { maximumFractionDigits: 0 });

const fmtNum = (n) =>
  n == null
    ? "—"
    : Number(n).toLocaleString(undefined, {
        minimumFractionDigits: 0,
        maximumFractionDigits: 2,
      });

export default function AnalysisPanel({ analysis, loading }) {
  return (
    <section className="panel">
      <div className="panel-head">
        <h2>Analysis</h2>
        {loading && <span className="panel-head-note">Calculating…</span>}
      </div>
      <div className="panel-body">
        {!analysis && !loading && (
          <p className="muted">Run Execute to see totals for the filtered data.</p>
        )}

        {analysis && (
          <>
            <div className="stat-rowcount">
              <span className="stat-rowcount-num">
                {fmtInt(analysis.row_count)}
              </span>
              <span className="stat-rowcount-label">total rows</span>
            </div>

            {analysis.stats.length === 0 ? (
              <p className="muted">
                Select a measure (e.g. Invoice Amount) or Invoice Number to see
                totals.
              </p>
            ) : (
              <table className="stat-table">
                <thead>
                  <tr>
                    <th>Field</th>
                    <th className="num">Total</th>
                    <th className="num">Avg</th>
                  </tr>
                </thead>
                <tbody>
                  {analysis.stats.map((s) => {
                    const isSum = s.aggregate === "sum";
                    const tag =
                      s.aggregate === "distinct"
                        ? "unique"
                        : s.aggregate === "count"
                        ? "per row"
                        : null;
                    const totalText = isSum
                      ? fmtNum(s.total)
                      : fmtInt(s.total);
                    const hint = isSum
                      ? `min ${fmtNum(s.minimum)} · max ${fmtNum(
                          s.maximum
                        )} · ${fmtInt(s.count)} values`
                      : `${fmtInt(s.count)} non-blank values`;
                    return (
                      <tr key={s.column}>
                        <td title={hint}>
                          {s.title}
                          {tag && <span className="stat-tag">{tag}</span>}
                        </td>
                        <td className="num strong">{totalText}</td>
                        <td className="num">
                          {isSum ? fmtNum(s.average) : "—"}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </>
        )}
      </div>
    </section>
  );
}
