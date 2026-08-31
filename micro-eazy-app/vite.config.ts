import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// The port is assigned in ecosystem/registry.json, once, for the whole
// ecosystem — 5174, beside the app it replaces on 5173 so the two can be run
// side by side and compared. Do not change it here; change it there.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5174,
    // Same rule as the app it replaces: the borrower session cookie is
    // SameSite=Lax and will not travel on a cross-site XHR, so /api is PROXIED
    // rather than called directly. See pwa/DEPLOY.md — that file is the full
    // explanation and it was written after this cost several days.
    proxy: {
      "/api": {
        target: process.env.VITE_SUITE_ORIGIN ?? "https://lms.servicesuitecloud.com",
        changeOrigin: true,
        secure: true,
      },
    },
  },
  build: { outDir: "dist", sourcemap: true },
});
