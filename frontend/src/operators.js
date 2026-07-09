// Operator catalog. Keys must match the backend operator identifiers in
// query_builder.py. `valueMode` tells the UI which inputs to render.
//   none   -> no value input (is_blank / is_not_blank)
//   single -> one input
//   range  -> two inputs (between)
//   list   -> comma-separated list (in_list)
export const OPERATORS = [
  { id: "equals", label: "equals", valueMode: "single" },
  { id: "not_equals", label: "not equals", valueMode: "single" },
  { id: "contains", label: "contains", valueMode: "single" },
  { id: "starts_with", label: "starts with", valueMode: "single" },
  { id: "gt", label: "greater than", valueMode: "single" },
  { id: "lt", label: "less than", valueMode: "single" },
  { id: "between", label: "between", valueMode: "range" },
  { id: "in_list", label: "in list", valueMode: "list" },
  { id: "is_blank", label: "is blank", valueMode: "none" },
  { id: "is_not_blank", label: "is not blank", valueMode: "none" },
];

// Mirror of the backend's per-type operator validation so the UI only offers
// operators valid for the chosen field's data type.
const BY_TYPE = {
  string: ["equals", "not_equals", "contains", "starts_with", "in_list", "is_blank", "is_not_blank"],
  number: ["equals", "not_equals", "gt", "lt", "between", "in_list", "is_blank", "is_not_blank"],
  date: ["equals", "not_equals", "gt", "lt", "between", "in_list", "is_blank", "is_not_blank"],
  boolean: ["equals", "not_equals", "is_blank", "is_not_blank"],
};

export function operatorsForType(dataType) {
  const allowed = BY_TYPE[dataType] || BY_TYPE.string;
  return OPERATORS.filter((op) => allowed.includes(op.id));
}

export function operatorMeta(id) {
  return OPERATORS.find((op) => op.id === id) || OPERATORS[0];
}

// HTML input type to use for a given data type.
export function inputType(dataType) {
  if (dataType === "number") return "number";
  if (dataType === "date") return "date";
  return "text";
}
