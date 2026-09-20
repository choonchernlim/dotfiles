import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  retries: 0,
  workers: 1,
  reporter: [["line"], ["json", { outputFile: ".check/e2e.json" }]],
  use: { baseURL: "http://127.0.0.1:3101", trace: "retain-on-failure" },
  webServer: {
    command: "npm run start -- --port 3101",
    url: "http://127.0.0.1:3101/healthz",
    reuseExistingServer: false,
  },
});
