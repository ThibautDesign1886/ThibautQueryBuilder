// Thin API client. In dev, requests go through the Vite proxy at /api. In the
// bundled production build, the same /api paths are served by FastAPI directly.
const BASE = import.meta.env.VITE_API_BASE ?? "/api";

// --- Auth -------------------------------------------------------------------
let authToken = sessionStorage.getItem("appPassword") || "";
let authMode = "open"; // "open" | "password" | "azure_ad"
let onUnauthorized = () => {};

export function setAuth(password) {
  authToken = password || "";
  if (authToken) sessionStorage.setItem("appPassword", authToken);
  else sessionStorage.removeItem("appPassword");
}

export function getAuth() {
  return authToken;
}

export function setAuthMode(mode) {
  authMode = mode;
}

export function setUnauthorizedHandler(fn) {
  onUnauthorized = fn;
}

function headers(extra = {}) {
  return authToken ? { ...extra, "X-App-Password": authToken } : { ...extra };
}

async function handle(res) {
  if (res.status === 401) {
    if (authMode === "azure_ad") {
      // EasyAuth session expired — redirect to Azure AD sign-in.
      window.location.href = "/.auth/login/aad?post_login_redirect_uri=/";
      return;
    }
    onUnauthorized();
    throw new Error("Your session needs the password again.");
  }
  if (!res.ok) {
    let detail = `Request failed (${res.status})`;
    try {
      const body = await res.json();
      if (body.detail) detail = body.detail;
    } catch (_) {
      /* ignore non-JSON error bodies */
    }
    throw new Error(detail);
  }
  return res.json();
}

// --- Auth endpoints ---------------------------------------------------------
export async function getConfig() {
  return handle(await fetch(`${BASE}/config`));
}

export async function getMe() {
  return handle(await fetch(`${BASE}/me`));
}

export async function login(password) {
  const res = await fetch(`${BASE}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  if (res.status === 401) throw new Error("Incorrect password.");
  if (!res.ok) throw new Error(`Login failed (${res.status})`);
  return res.json();
}

// --- Data endpoints ---------------------------------------------------------
export async function getDataSource() {
  return handle(await fetch(`${BASE}/datasource`, { headers: headers() }));
}

export async function getFields(model = "sales") {
  return handle(await fetch(`${BASE}/fields?model=${encodeURIComponent(model)}`, { headers: headers() }));
}

export async function getDistinct(model, column) {
  return handle(await fetch(`${BASE}/distinct?model=${encodeURIComponent(model)}&column=${encodeURIComponent(column)}`, { headers: headers() }));
}

export async function preview(payload) {
  return handle(
    await fetch(`${BASE}/preview`, {
      method: "POST",
      headers: headers({ "Content-Type": "application/json" }),
      body: JSON.stringify(payload),
    })
  );
}

export async function analyze(payload) {
  return handle(
    await fetch(`${BASE}/analyze`, {
      method: "POST",
      headers: headers({ "Content-Type": "application/json" }),
      body: JSON.stringify(payload),
    })
  );
}

export async function exportExcel(payload) {
  const res = await fetch(`${BASE}/export`, {
    method: "POST",
    headers: headers({ "Content-Type": "application/json" }),
    body: JSON.stringify(payload),
  });
  if (res.status === 401) {
    onUnauthorized();
    throw new Error("Your session needs the password again.");
  }
  if (!res.ok) {
    let detail = `Export failed (${res.status})`;
    try {
      const body = await res.json();
      if (body.detail) detail = body.detail;
    } catch (_) {
      /* ignore */
    }
    throw new Error(detail);
  }
  const blob = await res.blob();
  const disposition = res.headers.get("Content-Disposition") || "";
  const match = disposition.match(/filename="?([^"]+)"?/);
  const filename = match ? match[1] : "report.xlsx";
  const url = window.URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);
}

export async function exportCsv(payload) {
  const res = await fetch(`${BASE}/export/csv`, {
    method: "POST",
    headers: headers({ "Content-Type": "application/json" }),
    body: JSON.stringify(payload),
  });
  if (res.status === 401) {
    onUnauthorized();
    throw new Error("Your session needs the password again.");
  }
  if (!res.ok) {
    let detail = `Export failed (${res.status})`;
    try {
      const body = await res.json();
      if (body.detail) detail = body.detail;
    } catch (_) { /* ignore */ }
    throw new Error(detail);
  }
  const blob = await res.blob();
  const disposition = res.headers.get("Content-Disposition") || "";
  const match = disposition.match(/filename="?([^"]+)"?/);
  const filename = match ? match[1] : "report.csv";
  const url = window.URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);
}

export async function listTemplates() {
  return handle(await fetch(`${BASE}/templates`, { headers: headers() }));
}

export async function loadTemplate(id) {
  return handle(await fetch(`${BASE}/templates/${id}`, { headers: headers() }));
}

export async function saveTemplate(payload) {
  return handle(
    await fetch(`${BASE}/templates`, {
      method: "POST",
      headers: headers({ "Content-Type": "application/json" }),
      body: JSON.stringify(payload),
    })
  );
}
