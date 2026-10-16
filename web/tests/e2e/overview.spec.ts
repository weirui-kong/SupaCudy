// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, test } from '@playwright/test';
import { expectPageQuality, loginAndWait, messages } from './helpers';

test.describe('overview', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await loginAndWait(page, testInfo);
  });

  test('shows real device and system values', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const row = (label: string) => page.locator('.row', { has: page.getByText(label, { exact: true }) }).locator('dd');

    await expect(row(m.overview.model)).toHaveText('SupaCudy smoke test');
    await expect(row(m.overview.openwrt)).toContainText(/^\d+\.\d+\.\d+/);
    await expect(row(m.overview.uptime)).not.toHaveText(m.common.unavailable);
    await expect(row(m.overview.cpus)).toHaveText(/^\d+$/);
    await expect(page.getByRole('meter', { name: m.overview.memory })).toHaveAttribute('aria-valuetext', /^\d+%$/);
  });

  test('passes the quality checks', async ({ page }) => {
    await expect(page.getByRole('meter')).toBeVisible();
    await expectPageQuality(page);
  });

  test('explains fields in tooltips that stay on screen', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const triggers = page.getByRole('button', { name: m.common.more_info });
    await expect(triggers).toHaveCount(2);

    for (const [index, text] of [m.overview.load_hint, m.overview.memory_hint].entries()) {
      await triggers.nth(index).click();
      const tip = page.getByRole('tooltip', { name: text }).or(page.getByRole('tooltip').filter({ hasText: text }));
      await expect(tip).toBeVisible();

      const box = (await tip.boundingBox())!;
      const width = page.viewportSize()!.width;
      expect(box.x, 'tooltip leaves the left edge').toBeGreaterThanOrEqual(0);
      expect(box.x + box.width, 'tooltip leaves the right edge').toBeLessThanOrEqual(width);

      await page.keyboard.press('Escape');
      await expect(tip).toBeHidden();
    }
  });
});
