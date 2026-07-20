// "Conditions" panel: the filters, phrased as "Select records where all/any of
// the following apply". Each condition can be enabled/disabled with a checkbox.
import { useEffect, useState } from "react";
import { inputType, operatorMeta, operatorsForType } from "../operators";
import * as api from "../api";

// Cache distinct values per model+column so we don't re-fetch on every render.
const _distinctCache = {};

function useDistinctValues(model, column, enabled) {
  const key = `${model}::${column}`;
  const [values, setValues] = useState(_distinctCache[key] ?? null);

  useEffect(() => {
    if (!enabled || !column) return;
    if (_distinctCache[key] !== undefined) {
      setValues(_distinctCache[key]);
      return;
    }
    api.getDistinct(model, column).then((data) => {
      _distinctCache[key] = data; // [] means too many (>40)
      setValues(data);
    }).catch(() => {
      _distinctCache[key] = [];
      setValues([]);
    });
  }, [key, enabled]);

  return values; // null = loading, [] = too many / use text, [...] = show dropdown
}

function InListInput({ model, column, filter, onChange }) {
  const isInList = filter.operator === "in_list";
  const distinctValues = useDistinctValues(model, column, isInList);

  if (!isInList) return null;

  const selected = Array.isArray(filter.values) ? filter.values.map(String) : [];

  // Show multi-select checkboxes when we have ≤40 distinct values
  if (distinctValues && distinctValues.length > 0) {
    const toggleValue = (val) => {
      const next = selected.includes(val)
        ? selected.filter((v) => v !== val)
        : [...selected, val];
      onChange({ values: next, listText: next.join(",") });
    };
    return (
      <div className="in-list-dropdown">
        {distinctValues.map((val) => (
          <label key={val} className="in-list-option">
            <input
              type="checkbox"
              checked={selected.includes(String(val))}
              onChange={() => toggleValue(String(val))}
            />
            <span>{String(val)}</span>
          </label>
        ))}
      </div>
    );
  }

  // Fallback: text input for comma-separated values
  return (
    <input
      type="text"
      value={filter.listText ?? ""}
      placeholder="comma,separated,values"
      onChange={(e) => onChange({ listText: e.target.value })}
    />
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
                  onChange={(e) => onChange(idx, { column: e.target.value, values: [], listText: "" })}
                >
                  {fields.map((f) => (
                    <option key={f.column_name} value={f.column_name}>
                      {f.display_name}
                    </option>
                  ))}
                </select>

                <select
                  value={filter.operator}
                  onChange={(e) => onChange(idx, { operator: e.target.value, values: [], listText: "" })}
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
                  <InListInput
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
