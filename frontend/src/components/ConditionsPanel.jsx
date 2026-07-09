// "Conditions" panel: the filters, phrased as "Select records where all/any of
// the following apply". Each condition can be enabled/disabled with a checkbox.
import { inputType, operatorMeta, operatorsForType } from "../operators";

export default function ConditionsPanel({
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
                  onChange={(e) => onChange(idx, { column: e.target.value })}
                >
                  {fields.map((f) => (
                    <option key={f.column_name} value={f.column_name}>
                      {f.display_name}
                    </option>
                  ))}
                </select>

                <select
                  value={filter.operator}
                  onChange={(e) => onChange(idx, { operator: e.target.value })}
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
                  <input
                    type="text"
                    value={filter.listText ?? ""}
                    placeholder="comma,separated,values"
                    onChange={(e) => onChange(idx, { listText: e.target.value })}
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
