import { defineConfig } from "@playwright/test";
import { servers } from "./support/servers";

// The servers are imported but never wired in, so nothing starts the app.
export const unused = servers;

export default defineConfig({
  testDir: "./e2e",
  retries: process.env.CI ? 2 : 1,
  reporter: "html",
  use: { video: "on" },
});
