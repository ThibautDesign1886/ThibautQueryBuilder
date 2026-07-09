// Left "Entities & Attributes" panel: a fixed single Data Source, a search box,
// and the master-table attributes bucketed into collapsible groups. Checking an
// attribute adds it to the report Columns.
import { useMemo, useState } from "react";

export default function AttributePanel({
  dataSourceLabel,
  fields,
  selected,
  onToggle,
  onSelectAllInGroup,
  onClearAll,
}) {
  const [search, setSearch] = useState("");
  const [collapsed, setCollapsed] = useState({}); // group -> bool

  // Build ordered groups preserving first-seen order.
  const groups = useMemo(() => {
    const order = [];
    const map = new Map();
    for (const f of fields) {
      const g = f.group || "General";
      if (!map.has(g)) {
        map.set(g, []);
        order.push(g);
      }
      map.get(g).push(f);
    }
    return order.map((name) => ({ name, fields: map.get(name) }));
  }, [fields]);

  const term = search.trim().toLowerCase();
  const matches = (f) =>
    !term ||
    f.display_name.toLowerCase().includes(term) ||
    f.column_name.toLowerCase().includes(term);

  const isOpen = (g) => (term ? true : !collapsed[g]);
  const toggleGroup = (g) =>
    setCollapsed((p) => ({ ...p, [g]: !p[g] }));

  return (
    <section className="panel attr-panel">
      <div className="panel-head">
        <h2>Entities &amp; Attributes</h2>
      </div>
      <div className="panel-body">
        <div className="datasource-row">
          <label>Data Source</label>
          <select value={dataSourceLabel} disabled>
            <option>{dataSourceLabel}</option>
          </select>
        </div>

        <div className="attr-toolbar">
          <input
            type="search"
            placeholder="Search attributes…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <button type="button" className="link-btn" onClick={onClearAll}>
            Clear all
          </button>
        </div>

        <div className="tree">
          {groups.map((group) => {
            const visible = group.fields.filter(matches);
            if (term && visible.length === 0) return null;
            const open = isOpen(group.name);
            const selCount = group.fields.filter((f) =>
              selected.includes(f.column_name)
            ).length;
            return (
              <div className="tree-group" key={group.name}>
                <div className="tree-group-head">
                  <button
                    type="button"
                    className="tree-toggle"
                    onClick={() => toggleGroup(group.name)}
                    aria-label={open ? "Collapse" : "Expand"}
                  >
                    <span className={`caret ${open ? "open" : ""}`}>▶</span>
                    <span className="tree-group-name">{group.name}</span>
                    <span className="tree-group-count">
                      {selCount > 0 ? `${selCount}/` : ""}
                      {group.fields.length}
                    </span>
                  </button>
                  {open && (
                    <button
                      type="button"
                      className="link-btn tiny"
                      onClick={() => onSelectAllInGroup(group.fields)}
                    >
                      all
                    </button>
                  )}
                </div>
                {open && (
                  <ul className="tree-items">
                    {visible.map((f) => (
                      <li key={f.column_name}>
                        <label className="tree-item">
                          <input
                            type="checkbox"
                            checked={selected.includes(f.column_name)}
                            onChange={() => onToggle(f.column_name)}
                          />
                          <span className="tree-item-name">
                            {f.display_name}
                          </span>
                          <span className="tree-item-type">{f.data_type}</span>
                        </label>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
