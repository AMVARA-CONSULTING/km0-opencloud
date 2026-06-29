import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.KM0_AUTH_BASE_URL || 'https://cloud.km0digital.com';

export default defineConfig({
  testDir: '.',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list']],
  use: {
    baseURL,
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'desktop-chrome',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 7'] },
    },
  ],
  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.02,
    },
  },
});
