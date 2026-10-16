// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { defineConfig, devices } from '@playwright/test';

// Runs against the smoke-test container, which scripts/test-e2e.sh starts.
const baseURL = process.env.E2E_BASE_URL ?? 'http://localhost:18080/supacudy/';

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
  use: { baseURL, trace: 'retain-on-failure' },
  projects: Object.entries(viewports).flatMap(([viewportName, device]) =>
    themes.flatMap((colorScheme) =>
      locales.map((locale) => ({
        name: `${viewportName}-${colorScheme}-${locale}`,
        use: { ...device, colorScheme, locale },
      })),
    ),
  ),
});
