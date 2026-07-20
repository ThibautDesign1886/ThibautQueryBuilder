// "Conditions" panel
import { createPortal } from "react-dom";
import { useEffect, useRef, useState } from "react";
import { inputType, operatorMeta, operatorsForType } from "../operators";
import * as api from "../api";

const _distinctCache = {};

function useDistinctValues(model, column, enabled) {
  const key = `${model}::${column}`;
  const [state, setState] = useState({ loading: false, values: null });

  useEffect(() => {
    if (!enabled || !column) return;
    if (_distinctCache[key] !== undefined) {
      setState({ loading: false, values: _distinctCache[key] });
      return;
    }
    setState({ loading: true, values: null });
    api.getDistinct(model, column)
      .then((data) => {
        _distinctCache[key] = data;
        setState({ loading: false, values: data });
      })
      .catch(() => {
        _distinctCache[key] = [];
        setState({ loading: false, values: [] });
      });
  }, [key, enabled]);

  return state;
}

function InListPicker({ model, column, filter, onChange }) {
  const [open, setOpen] = useState(false);
  const [dropPos, setDropPos] = useState({ top: 0, left: 0, width: 0 });
  const [search, setSearch] = useState("");
  const triggerRef = useRef(null);
  const dropRef = useRef(null);
  const { loading, values } = useDistinctValues(model, column, true);

  const selected = Array.isArray(filter.values) ? filter.values.map(String) : [];

  // Compute dropdown position from trigger's bounding rect (fixed, viewport-relative)
  const openDropdown = () => {
    if (triggerRef.current) {
      const rect = triggerRef.current.getBoundingClientRect();
      setDropPos({
        top: rect.bottom + 4,
        left: rect.left,
        width: Math.max(rect.width, 260),
      });
    }
    setOpen(true);
  };

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e) => {
      if (
        triggerRef.current && !triggerRef.current.contains(e.target) &&
        dropRef.current && !dropRef.current.contains(e.target)
      ) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  const toggle = (val) => {
    const next = selected.includes(val)
      ? selected.filter((v) => v !== val)
      : [...selected, val];
    onChange({ values: next, listText: next.join(",") });
  };

  const filtered = values
    ? values.filter((v) => String(v).toLowerCase().includes(search.toLowerCase()))
    : [];

  // Too many distinct values — fall back to free text
  if (values !== null && values.length === 0 && !loading) {
    return (
      <input
        type="text"
        value={filter.listText ?? ""}
        placeholder="comma,separated,values"
        onChange={(e) => onChange({ listText: e.target.value })}
      />
    );
  }

  // Portal dropdown — renders at document.body to escape any overflow:hidden ancestors
  const dropdown = open && values && values.length > 0 && createPortal(
    <div
      ref={dropRef}
      className="inlist-dropdown"
      style={{
        position: "fixed",
        top: dropPos.top,
        left: dropPos.left,
        width: dropPos.width,
        zIndex: 9999,
      }}
    >
      <div className="inlist-search">
        <input
          type="search"
          placeholder="Search…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          autoFocus
        />
        <div className="inlist-actions">
          <button
            type="button"
            className="link-btn tiny"
            onClick={() => onChange({ values: values.map(String), listText: values.join(",") })}
          >
            All
          </button>
          <button
            type="button"
            className="link-btn tiny"
            onClick={() => onChange({ values: [], listText: "" })}
          >
            None
          </button>
        </div>
      </div>
      <ul className="inlist-options">
        {filtered.map((val) => (
          <li key={val}>
            <label className="inlist-option">
              <input
                type="checkbox"
                checked={selected.includes(String(val))}
                onChange={() => toggle(String(val))}
              />
              <span>{String(val)}</span>
            </label>
          </li>
        ))}
        {filtered.length === 0 && <li className="inlist-empty">No matches</li>}
      </ul>
    </div>,
    document.body
  );

  return (
    <div className="inlist-picker">
      <button
        ref={triggerRef}
        type="button"
        className="inlist-trigger"
        onClick={() => (open ? setOpen(false) : openDropdown())}
      >
        {loading ? (
          <span className="inlist-loading">Loading…</span>
        ) : selected.length === 0 ? (
          <span className="inlist-placeholder">Select values…</span>
        ) : (
          <span className="inlist-count">{selected.length} selected</span>
        )}
        <span className="inlist-arrow">{open ? "▲" : "▼"}</span>
      </button>

      {selected.length > 0 && (
        <div className="inlist-pills">
          {selected.map((v) => (
            <span key={v} className="inlist-pill">
              {v}
              <button type="button" onClick={() => toggle(v)}>×</button>
            </span>
          ))}
        </div>
      )}

      {dropdown}
    </div>
  );
}

export default function ConditionsPanel({
  model,
  fields,
  filters,
  logic,
  onLogicChange,
  onAdd,
  onRemove,
  onChange,
}) {
  const fieldByCol = Object.fromEntries(fields.map((f) => [f.column_name, f]));

  return (
    <section className="panel panel-conditions">
      <div className="panel-head">
        <h2>Conditions</h2>
        <button type="button" className="add-link" onClick={onAdd}>
          <span className="add-circle">+</span> Add condition
        </button>
      </div>
      <div className="panel-body">
        <div className="conditions-intro">
          <span className="cell-icon">▦</span>
          Select records where{" "}
          <select
            className="logic-select"
            value={logic}
            onChange={(e) => onLogicChange(e.target.value)}
          >
            <option value="AND">all</option>
            <option value="OR">any</option>
          </select>{" "}
          of the following apply
        </div>

        {filters.length === 0 && (
          <p className="muted">
            No conditions — all rows are returned (up to the limit).
          </p>
        )}

        <div className="conditions-list">
          {filters.map((filter, idx) => {
            const field = fieldByCol[filter.column] || fields[0];
            const dataType = field ? field.data_type : "string";
            const ops = operatorsForType(dataType);
            const meta = operatorMeta(filter.operator);
            return (
              <div
                className={`condition-row ${filter.enabled ? "" : "disabled"}`}
                key={filter.id}
              >
                <input
                  type="checkbox"
                  className="cond-enable"
                  checked={filter.enabled}
                  title={filter.enabled ? "Active" : "Inactive"}
                  onChange={(e) => onChange(idx, { enabled: e.target.checked })}
                />
                <select
                  value={filter.column}
                  onChange={(e) =>
                    onChange(idx, { column: e.target.value, values: [], listText: "" })
                  }
                >
                  {fields.map((f) => (
                    <option key={f.column_name} value={f.column_name}>
                      {f.display_name}
                    </option>
                  ))}
                </select>
                <select
                  value={filter.operator}
                  onChange={(e) =>
                    onChange(idx, { operator: e.target.value, values: [], listText: "" })
                  }
                >
                  {ops.map((op) => (
                    <option key={op.id} value={op.id}>
                      {op.label}
                    </option>
                  ))}
                </select>

                {meta.valueMode === "single" && (
                  <input
                    type={inputType(dataType)}
                    value={filter.value ?? ""}
                    placeholder="value"
                    onChange={(e) => onChange(idx, { value: e.target.value })}
                  />
                )}
                {meta.valueMode === "range" && (
                  <div className="range-inputs">
                    <input
                      type={inputType(dataType)}
                      value={filter.values?.[0] ?? ""}
                      placeholder="from"
                      onChange={(e) =>
                        onChange(idx, {
                          values: [e.target.value, filter.values?.[1] ?? ""],
                        })
                      }
                    />
                    <span className="range-sep">and</span>
                    <input
                      type={inputType(dataType)}
                      value={filter.values?.[1] ?? ""}
                      placeholder="to"
                      onChange={(e) =>
                        onChange(idx, {
                          values: [filter.values?.[0] ?? "", e.target.value],
                        })
                      }
                    />
                  </div>
                )}
                {meta.valueMode === "list" && (
                  <InListPicker
                    model={model}
                    column={filter.column}
                    filter={filter}
                    onChange={(patch) => onChange(idx, patch)}
                  />
                )}
                {meta.valueMode === "none" && (
                  <span className="no-value">— no value —</span>
                )}

                <button
                  type="button"
                  className="icon-btn"
                  title="Remove condition"
                  onClick={() => onRemove(idx)}
                >
                  ✕
                </button>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
