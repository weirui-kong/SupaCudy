// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, expectPageQuality, fill, loginAndWait, messages, test } from './helpers';

test.describe('rescue mode', () => {
  test('explains rescue mode before and after logging in', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.rescue = { active: true, address: '192.168.200.1', ssid: 'SupaCudy-Rescue', since: 1_792_000_000 };
    await page.goto('./');
    const banner = page.getByText(m.rescue.title);
    await expect(banner).toBeVisible();
    await expect(page.getByText(fill(m.rescue.address, { address: '192.168.200.1' }), { exact: false })).toBeVisible();
    await expectPageQuality(page);

    await loginAndWait(page, testInfo);
    await expect(page.getByRole('main').getByText(m.rescue.title)).toBeVisible();
    await expect(page.getByRole('main')).toContainText(fill(m.rescue.ssid, { ssid: 'SupaCudy-Rescue' }));
    await expect(page.getByRole('main')).toContainText(m.rescue.temporary);
    await expectPageQuality(page);
  });

  test('shows nothing while the router is reachable normally', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await loginAndWait(page, testInfo);
    await expect(page.getByText(m.rescue.title)).toHaveCount(0);
  });
});
