// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, expectPageQuality, isMobile, loginAndWait, messages, test } from './helpers';

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

  test('reaches every page and marks the current one', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const nav = page.getByRole('navigation', { name: m.nav.main }).filter({ visible: true });
    const pages = [
      { label: m.nav.clients, title: m.nav.clients },
      { label: m.nav.lan, title: m.nav.lan },
      { label: m.nav.settings, title: m.settings.title },
      { label: m.nav.overview, title: m.overview.title },
    ];

    for (const target of pages) {
      const direct = nav.getByRole('link', { name: target.label, exact: true });
      if (await direct.count()) {
        await direct.click();
        await expect(direct).toHaveAttribute('aria-current', 'page');
      } else {
        // Phones: secondary pages are listed on the "More" page.
        await nav.getByRole('link', { name: m.nav.more, exact: true }).click();
        await page.getByRole('main').getByRole('link', { name: target.label, exact: true }).click();
        await expect(nav.getByRole('link', { name: m.nav.more, exact: true })).toHaveAttribute('aria-current', 'page');
      }
      await expect(page.getByRole('heading', { level: 1 })).toHaveText(target.title);
    }
  });

  test('opens native OpenWrt only after a warning', async ({ page, context }, testInfo) => {
    const m = messages(testInfo);
    if (isMobile(testInfo)) {
      await page.goto('./#/more');
      await page.getByRole('main').getByRole('button', { name: m.nav.luci }).click();
    } else {
      const button = page.locator('nav.sidebar').getByRole('button', { name: m.nav.luci });
      // Bottom left, just above "Log out".
      const logout = page.locator('nav.sidebar').getByRole('button', { name: m.nav.logout });
      expect((await button.boundingBox())!.y).toBeLessThan((await logout.boundingBox())!.y);
      expect((await button.boundingBox())!.y).toBeGreaterThan(page.viewportSize()!.height / 2);
      await button.click();
    }
    const dialog = page.getByRole('dialog', { name: m.luci.title });
    await expect(dialog).toContainText(m.luci.consequence);
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.cancel }).click();
    await expect(dialog).toBeHidden();
    expect(context.pages()).toHaveLength(1);

    await page.getByRole('button', { name: m.nav.luci }).filter({ visible: true }).click();
    const popup = context.waitForEvent('page');
    await dialog.getByRole('button', { name: m.luci.confirm }).click();
    expect(new URL((await popup).url()).pathname).toBe('/cgi-bin/luci/');
    await expect(dialog).toBeHidden();
  });

  test('the More page passes the quality checks', async ({ page }, testInfo) => {
    await page.goto('./#/more');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(messages(testInfo).nav.more);
    await expectPageQuality(page);
  });

  test('falls back to the overview for an unknown address', async ({ page }, testInfo) => {
    await page.goto('./#/no-such-page');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(messages(testInfo).overview.title);
  });

  test('keeps every visible control large enough to tap', async ({ page }) => {
    for (const route of ['overview', 'clients', 'lan', 'settings', 'more']) {
      await page.goto(`./#/${route}`);
      await page.waitForTimeout(300);
      const controls = page.locator('a:visible, button:visible, select:visible, input:visible, label:has(input):visible');
      for (const handle of await controls.elementHandles()) {
        const box = await handle.boundingBox();
        if (!box) continue;
        // Inputs inside a switch or segmented control are invisible overlays.
        if (await handle.evaluate((el: Element) => el.matches('input[type=checkbox], input[type=radio]'))) continue;
        const label = await handle.evaluate((el: Element) => el.textContent?.trim() || el.getAttribute('aria-label') || el.outerHTML.slice(0, 60));
        expect(Math.round(box.height), `${route}: "${label}" is too short to tap`).toBeGreaterThanOrEqual(44);
        expect(Math.round(box.width), `${route}: "${label}" is too narrow to tap`).toBeGreaterThanOrEqual(44);
      }
    }
  });
});
