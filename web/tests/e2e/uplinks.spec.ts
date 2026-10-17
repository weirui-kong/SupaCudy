// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

test.describe('connection priority', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'internet', messages(testInfo).nav.internet);
  });

  test('lists the connections in order with their IPv4 and IPv6 state', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const prio = card(page, m.uplinks.title);
    const rows = prio.getByRole('listitem');
    await expect(rows).toHaveCount(3);
    await expect(rows.nth(0)).toContainText(m.internet.ethernet);
    await expect(rows.nth(0)).toContainText(`${m.uplinks.ipv4}: ${m.uplinks.in_use}`);
    await expect(rows.nth(0)).toContainText(`${m.uplinks.ipv6}: ${m.uplinks.in_use}`);
    await expect(rows.nth(1)).toContainText(m.uplinks.not_set_up);
    await expect(rows.nth(2)).toContainText(`${m.uplinks.ipv4}: ${m.uplinks.standby}`);
    await expect(prio.getByRole('switch', { name: m.uplinks.reset })).toBeChecked();
    await expect(prio.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await expectPageQuality(page);
  });

  test('moves tethering to the top and keeps connections when switching', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const prio = card(page, m.uplinks.title);
    const name = m.tethering.title;
    await expect(prio.getByRole('button', { name: fill(m.uplinks.move_down, { name }) })).toBeDisabled();
    await prio.getByRole('button', { name: fill(m.uplinks.move_up, { name }) }).click();
    await prio.getByRole('button', { name: fill(m.uplinks.move_up, { name }) }).click();
    await expect(prio.getByRole('button', { name: fill(m.uplinks.move_up, { name }) })).toBeDisabled();
    await expect(prio.getByRole('listitem').nth(0)).toContainText(name);
    await prio.getByRole('switch', { name: m.uplinks.reset }).uncheck();
    await prio.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.uplinks.order).toEqual(['tethering', 'wired', 'repeater']);
    expect(router.uplinks.reset_connections).toBe(false);
  });

  test('checks the internet check addresses before sending them', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const prio = card(page, m.uplinks.title);
    await prio.getByText(m.uplinks.targets, { exact: true }).click();
    const v4 = prio.getByLabel(m.uplinks.targets4);
    const v6 = prio.getByLabel(m.uplinks.targets6);
    await v4.fill('223.5.5.5\n300.1.1.1');
    await expect(prio.getByText(fill(m.uplinks.target_bad4, { value: '300.1.1.1' }))).toBeVisible();
    await expect(prio.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await v4.fill('');
    await expect(prio.getByText(fill(m.uplinks.targets_count, { max: 8 }))).toBeVisible();
    await v4.fill('223.5.5.5\n\n10.250.2.2');
    await v6.fill('2400:3200::1\nnot-an-address');
    await expect(prio.getByText(fill(m.uplinks.target_bad6, { value: 'not-an-address' }))).toBeVisible();
    await v6.fill('2400:3200::1');
    await expectPageQuality(page);
    await prio.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.uplinks.targets4).toEqual(['223.5.5.5', '10.250.2.2']);
    expect(router.uplinks.targets6).toEqual(['2400:3200::1']);
  });

  test('shows a failover with words, not only colors', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.uplinks, { active_v4: 'tethering', active_v6: null });
    await page.reload();
    const rows = card(page, m.uplinks.title).getByRole('listitem');
    await expect(rows.nth(0)).toContainText(`${m.uplinks.ipv4}: ${m.uplinks.no_internet}`);
    await expect(rows.nth(0)).toContainText(`${m.uplinks.ipv6}: ${m.uplinks.no_internet}`);
    await expect(rows.nth(2)).toContainText(`${m.uplinks.ipv4}: ${m.uplinks.in_use}`);
  });

  test('says so while the connections are still being checked', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.uplinks.watching = false;
    await page.reload();
    await expect(card(page, m.uplinks.title).getByText(m.uplinks.starting)).toBeVisible();
  });
});
