import { defineConfig, devices } from '@playwright/test';
import 'dotenv/config';

const baseURL = process.env.BASE_URL ?? 'https://playwright.dev';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,

  // Fail the build if test.only is left in the source on CI.
  forbidOnly: !!process.env.CI,

  // Retry on CI only
  retries: process.env.CI ? 2 : 0,

  // Opt into fewer workers on CI (override as needed)
  workers: process.env.CI ? 2 : undefined,

  reporter: [
    ['list'],
    ['html', { open: 'never' }],
  ],

  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
  ],

  // If you need to start your app before running tests, uncomment:
  // webServer: {
  //   command: 'npm run dev',
  //   url: baseURL,
  //   reuseExistingServer: !process.env.CI,
  // },
});
