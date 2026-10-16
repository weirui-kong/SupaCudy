// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, test } from '@playwright/test';
import { isMobile, loginAndWait, messages } from './helpers';

test.describe('navigation', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await loginAndWait(page, testInfo);
  });

  test('uses a sidebar on desktop and a bottom bar on phones', async ({ page }, testInfo) => {
    const navs = page.getByRole('navigation', { name: messages(testInfo).nav.main });
    const sidebar = page.locator('nav.sidebar');
    const bottom = page.locator('nav.bottom-nav');

    await expect(navs.filter({ visible: true })).toHaveCount(1);
    if (isMobile(testInfo)) {
      await expect(bottom).toBeVisible();
      await expect(sidebar).toBeHidden();
      const box = (await bottom.boundingBox())!;
      expect(box.y + box.height).toBeCloseTo(page.viewportSize()!.height, 0);
    } else {
      await expect(sidebar).toBeVisible();
      await expect(bottom).toBeHidden();
    }
  });

  test('moves between pages and marks the current one', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const nav = page.getByRole('navigation', { name: m.nav.main }).filter({ visible: true });

    await nav.getByRole('link', { name: m.nav.settings }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.settings.title);
    await expect(nav.getByRole('link', { name: m.nav.settings })).toHaveAttribute('aria-current', 'page');
    await expect(nav.getByRole('link', { name: m.nav.overview })).not.toHaveAttribute('aria-current', 'page');

    await nav.getByRole('link', { name: m.nav.overview }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.overview.title);
  });

  test('falls back to the overview for an unknown address', async ({ page }, testInfo) => {
    await page.goto('./#/no-such-page');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(messages(testInfo).overview.title);
  });

  test('keeps every visible control large enough to tap', async ({ page }) => {
    const controls = page.locator('a:visible, button:visible, label:has(input[type=radio]):visible');
    for (const handle of await controls.elementHandles()) {
      const box = await handle.boundingBox();
      if (!box) continue;
      const label = await handle.evaluate((el: Element) => el.textContent?.trim() || el.getAttribute('aria-label') || el.outerHTML.slice(0, 60));
      expect(Math.round(box.height), `"${label}" is too short to tap`).toBeGreaterThanOrEqual(44);
      expect(Math.round(box.width), `"${label}" is too narrow to tap`).toBeGreaterThanOrEqual(44);
    }
  });
});
