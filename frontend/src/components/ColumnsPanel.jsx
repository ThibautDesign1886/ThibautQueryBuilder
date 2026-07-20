// "Columns" panel: selected report columns with title editing, sorting,
// up/down buttons, and drag-to-reorder.
import { useRef, useState } from "react";

export default function ColumnsPanel({
  columns,
  titles,
  sortByCol,
  onTitleChange,
  onSetSort,
  onRemove,
  onMove,
}) {
  const [dragOver, setDragOver] = useState(null);
  const dragSrc = useRef(null);

  function handleDragStart(e, idx) {
    dragSrc.current = idx;
    e.dataTransfer.effectAllowed = "move";
    // Minimal ghost — just the row itself
    e.dataTransfer.setDragImage(e.currentTarget, 0, 0);
  }

  function handleDragOver(e, idx) {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    if (idx !== dragSrc.current) setDragOver(idx);
  }

  function handleDrop(e, idx) {
    e.preventDefault();
    if (dragSrc.current !== null && dragSrc.current !== idx) {
      onMove(dragSrc.current, idx);
    }
    setDragOver(null);
    dragSrc.current = null;
  }

  function handleDragEnd() {
    setDragOver(null);
    dragSrc.current = null;
  }

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
              <th style={{ width: 68 }} />
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
              <tr
                key={f.column_name}
                draggable
                onDragStart={(e) => handleDragStart(e, idx)}
                onDragOver={(e) => handleDragOver(e, idx)}
                onDrop={(e) => handleDrop(e, idx)}
                onDragEnd={handleDragEnd}
                className={`col-row${dragOver === idx ? " col-row-drop" : ""}`}
              >
                <td style={{ padding: "4px 6px" }}>
                  <div className="col-controls">
                    <span className="col-drag-handle" title="Drag to reorder">⠿</span>
                    <div className="col-move">
                      <button
                        type="button"
                        className="icon-btn"
                        title="Move up"
                        disabled={idx === 0}
                        onClick={() => onMove(idx, idx - 1)}
                      >▲</button>
                      <button
                        type="button"
                        className="icon-btn"
                        title="Move down"
                        disabled={idx === columns.length - 1}
                        onClick={() => onMove(idx, idx + 1)}
                      >▼</button>
                    </div>
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
                  >✕</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
