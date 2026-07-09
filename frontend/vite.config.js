import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The dev server proxies /api -> FastAPI backend so the frontend can use
// relative URLs and avoid CORS issues during development.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      // The backend now serves the API under /api directly, so forward the path
      // as-is (no rewrite). Use 127.0.0.1 (not "localhost"): on Node 18+
      // "localhost" can resolve to IPv6 (::1) while uvicorn listens on IPv4 only.
      "/api": {
        target: "http://127.0.0.1:8000",
        changeOrigin: true,
      },
    },
  },
});
