import { test } from "@playwright/test";

test("waits", async ({ page }) => {
  await page.goto("/");
  await page.waitForTimeout(5000);
});
