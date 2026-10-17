// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, expectPageQuality, fill, loginAndWait, messages, test } from './helpers';

test.describe('overview', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await loginAndWait(page, testInfo);
  });

  test('shows real device and system values', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const row = (label: string) => page.locator('.row', { has: page.getByText(label, { exact: true }) }).locator('dd');

    await expect(row(m.overview.model)).toHaveText('Cudy TR3000 v1');
    await expect(row(m.overview.temperature)).toHaveText(
      fill(m.overview.temperature_value, { cpu: fill(m.overview.degrees, { value: '52' }), wifi: fill(m.overview.degrees, { value: '47' }) }),
    );
    await expect(row(m.overview.openwrt)).toContainText(/^\d+\.\d+\.\d+/);
    await expect(row(m.overview.uptime)).not.toHaveText(m.common.unavailable);
    await expect(row(m.overview.cpus)).toHaveText(/^\d+$/);
    await expect(page.getByRole('meter', { name: m.overview.memory })).toHaveAttribute('aria-valuetext', /^\d+%$/);
    await expect(page.getByRole('meter', { name: m.overview.storage })).toHaveAttribute('aria-valuetext', '30%');
  });

  test('links to the source code on GitHub with an icon, in a new window', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const link = page.getByRole('link', { name: new RegExp(m.overview.source) });
    await expect(page.getByText(m.overview.source, { exact: true })).toBeHidden();
    await expect(link.locator('svg')).toBeVisible();
    await expect(link).not.toContainText('github.com');
    await expect(link).toHaveAttribute('href', 'https://github.com/weirui-kong/SupaCudy');
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(link).toHaveAttribute('rel', /noopener/);
  });

  test('shows the network map and links to the internet page', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const map = page.getByRole('navigation', { name: m.overview.topology });
    await expect(map).toContainText(m.internet.ethernet);
    await expect(map).toContainText(m.overview.clients_online.replace('{count}', '3'));
    await map.getByRole('link', { name: new RegExp(m.nav.internet) }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.nav.internet);
  });

  test('passes the quality checks', async ({ page }, testInfo) => {
    await expect(page.getByRole('meter', { name: messages(testInfo).overview.memory })).toBeVisible();
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

  test('keeps a tooltip next to its trigger while scrolling', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.setViewportSize({ width: page.viewportSize()!.width, height: 420 });
    const trigger = page.getByRole('button', { name: m.common.more_info }).first();
    await trigger.click();
    const tip = page.getByRole('tooltip').filter({ hasText: m.overview.load_hint });
    await expect(tip).toBeVisible();

    await page.evaluate(() => window.scrollBy(0, 60));
    await expect.poll(async () => {
      const [a, b] = [await trigger.boundingBox(), await tip.boundingBox()];
      return a && b ? Math.round(b.y - (a.y + a.height)) : null;
    }).toBe(8);

  });
});
