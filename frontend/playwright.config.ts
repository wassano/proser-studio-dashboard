import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests', use: { baseURL: 'http://127.0.0.1:5174', viewport: { width: 1440, height: 1000 }, launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH } },
  webServer: { command: 'npm run dev', url: 'http://127.0.0.1:5174', reuseExistingServer: !process.env.CI },
});
