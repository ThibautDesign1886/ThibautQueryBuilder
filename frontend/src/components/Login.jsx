// Simple shared-password screen shown before the app loads when the backend
// reports auth_required.
import { useState } from "react";

export default function Login({ onSubmit, error, busy }) {
  const [password, setPassword] = useState("");

  function submit(e) {
    e.preventDefault();
    if (password.trim()) onSubmit(password);
  }

  return (
    <div className="login-screen">
      <form className="login-card" onSubmit={submit}>
        <div className="login-brand">
          <span className="brand-mark">▣</span>
          <span className="brand-name">Thibaut Query Builder</span>
        </div>
        <p className="login-sub">Enter the access password to continue.</p>
        <input
          type="password"
          autoFocus
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        {error && <div className="login-error">{error}</div>}
        <button type="submit" className="login-btn" disabled={busy || !password.trim()}>
          {busy ? "Checking…" : "Enter"}
        </button>
      </form>
    </div>
  );
}
