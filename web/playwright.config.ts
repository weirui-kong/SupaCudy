// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { defineConfig, devices } from '@playwright/test';

// The built UI is served by `vite preview`; every test answers /ubus with
// the in-memory mock router (tests/e2e/mock/router.ts).
const PORT = Number(process.env.E2E_PORT ?? 4173);

const viewports = {
  desktop: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } },
  mobile: { ...devices['Pixel 7'], viewport: { width: 390, height: 844 } },
};
const themes = ['light', 'dark'] as const;
const locales = ['zh-CN', 'en'] as const;

export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: { baseURL: `http://127.0.0.1:${PORT}/`, trace: 'retain-on-failure' },
  webServer: {
    command: `npx vite preview --host 127.0.0.1 --port ${PORT} --strictPort`,
    url: `http://127.0.0.1:${PORT}/`,
    reuseExistingServer: !process.env.CI,
  },
  projects: Object.entries(viewports).flatMap(([viewportName, device]) =>
    themes.flatMap((colorScheme) =>
      locales.map((locale) => ({
        name: `${viewportName}-${colorScheme}-${locale}`,
        use: { ...device, colorScheme, locale },
      })),
    ),
  ),
});
