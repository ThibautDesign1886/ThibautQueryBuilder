// "Columns" panel: the selected report columns with an editable Title,
// per-column Sorting, and up/down reordering.
export default function ColumnsPanel({
  columns,
  titles,
  sortByCol,
  onTitleChange,
  onSetSort,
  onRemove,
  onMove,
}) {
  return (
    <section className="panel">
      <div className="panel-head">
        <h2>Columns</h2>
        <span className="panel-head-note">
          {columns.length} selected · check attributes on the left to add
        </span>
      </div>
      <div className="panel-body no-pad">
        <table className="grid-table">
          <thead>
            <tr>
              <th style={{ width: 52 }} />
              <th>Expression</th>
              <th>Title</th>
              <th className="col-sorting">Sorting</th>
              <th className="col-actions" />
            </tr>
          </thead>
          <tbody>
            {columns.length === 0 && (
              <tr>
                <td colSpan={5} className="grid-empty">
                  No columns selected yet.
                </td>
              </tr>
            )}
            {columns.map((f, idx) => (
              <tr key={f.column_name}>
                <td style={{ padding: "4px 6px" }}>
                  <div className="col-move">
                    <button
                      type="button"
                      className="icon-btn"
                      title="Move up"
                      disabled={idx === 0}
                      onClick={() => onMove(idx, idx - 1)}
                    >
                      ▲
                    </button>
                    <button
                      type="button"
                      className="icon-btn"
                      title="Move down"
                      disabled={idx === columns.length - 1}
                      onClick={() => onMove(idx, idx + 1)}
                    >
                      ▼
                    </button>
                  </div>
                </td>
                <td>
                  <span className="cell-icon">▦</span>
                  {f.display_name}
                </td>
                <td>
                  <input
                    className="title-input"
                    type="text"
                    value={titles[f.column_name] ?? f.display_name}
                    onChange={(e) => onTitleChange(f.column_name, e.target.value)}
                  />
                </td>
                <td className="col-sorting">
                  <select
                    value={sortByCol[f.column_name] || ""}
                    onChange={(e) => onSetSort(f.column_name, e.target.value || null)}
                  >
                    <option value="">Not sorted</option>
                    <option value="ASC">Ascending</option>
                    <option value="DESC">Descending</option>
                  </select>
                </td>
                <td className="col-actions">
                  <button
                    type="button"
                    className="icon-btn"
                    title="Remove column"
                    onClick={() => onRemove(f.column_name)}
                  >
                    ✕
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
