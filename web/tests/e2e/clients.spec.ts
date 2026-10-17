// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

test.describe('clients', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'clients', messages(testInfo).nav.clients);
  });

  test('lists online and offline devices and passes the quality checks', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const online = page.getByRole('table', { name: m.clients.online });
    const offline = page.getByRole('table', { name: m.clients.offline });

    await expect(online.getByRole('button', { name: 'Work-Laptop', exact: true })).toBeVisible();
    await expect(online.getByRole('button', { name: 'Pixel-Phone', exact: true })).toBeVisible();
    await expect(online.getByRole('button', { name: 'Home NAS', exact: true })).toBeVisible();
    await expect(offline.getByRole('button', { name: 'Living-Room-TV', exact: true })).toBeVisible();
    await expect(offline.getByText(m.clients.blocked, { exact: true })).toBeVisible();
    await expect(online.getByText(m.clients.fixed, { exact: true })).toBeVisible();
    await expectPageQuality(page);
  });

  test('shows live speeds once two samples are in', async ({ page }) => {
    const laptopRow = page.getByRole('row').filter({ has: page.getByRole('button', { name: 'Work-Laptop', exact: true }) });
    await expect(laptopRow).toContainText(/\d+(\.\d)? KB\/s/, { timeout: 10_000 });
  });

  test('blocks and unblocks internet access from the list', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const toggle = page.getByRole('switch', { name: fill(m.clients.block_named, { name: 'Work-Laptop' }) });

    await toggle.check();
    await expect(page.getByRole('status').filter({ hasText: fill(m.clients.blocked_done, { name: 'Work-Laptop' }) })).toBeVisible();
    expect(router.clients[0].blocked).toBe(true);

    await toggle.uncheck();
    await expect(page.getByRole('status').filter({ hasText: fill(m.clients.unblocked_done, { name: 'Work-Laptop' }) })).toBeVisible();
    expect(router.clients[0].blocked).toBe(false);
  });

  test('explains a failed change and keeps the old state', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.failNext('client_block', { status: 0, data: { error: 'something_new' } });
    // Clicked, not checked: the switch goes back as soon as the router refuses,
    // which on a slow machine can be before check() looks.
    await page.getByRole('switch', { name: fill(m.clients.block_named, { name: 'Work-Laptop' }) }).click();

    await expect(page.getByRole('alert')).toContainText(fill(m.errors.rejected, { reason: 'something_new' }));
    expect(router.clients[0].blocked).toBe(false);
    await expect(page.getByRole('switch', { name: fill(m.clients.block_named, { name: 'Work-Laptop' }) })).not.toBeChecked();
  });

  test('renames a device, limits it and gives it a fixed address', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: fill(m.clients.manage_named, { name: 'Work-Laptop' }) }).click();
    const dialog = page.getByRole('dialog', { name: 'Work-Laptop' });
    await expect(dialog).toBeVisible();
    await expectPageQuality(page);

    await dialog.getByLabel(m.clients.name, { exact: true }).fill('Office laptop');
    await dialog.getByLabel(m.clients.type, { exact: true }).selectOption('laptop');
    await dialog.getByLabel(m.clients.up_limit, { exact: true }).fill('200');
    await dialog.getByLabel(m.clients.down_limit, { exact: true }).fill('1000');
    await dialog.getByRole('switch', { name: m.clients.fixed_ip }).check();
    await dialog.getByLabel(m.clients.fixed_ip_address, { exact: true }).fill('192.168.1.20');
    await dialog.getByRole('button', { name: m.common.save, exact: true }).click();

    await expect(dialog).toBeHidden();
    await expect(page.getByRole('button', { name: 'Office laptop', exact: true })).toBeVisible();
    const laptop = router.clients[0];
    expect([laptop.name, laptop.type, laptop.up_limit, laptop.down_limit, laptop.reserved_ip]).toEqual(['Office laptop', 'laptop', 200, 1000, '192.168.1.20']);
  });

  test('only sends what changed', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: fill(m.clients.manage_named, { name: 'Pixel-Phone' }) }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel(m.clients.name, { exact: true }).fill('My phone');
    router.calls.length = 0;
    await dialog.getByRole('button', { name: m.common.save, exact: true }).click();
    await expect(dialog).toBeHidden();
    expect(router.calls.map((c) => c.method).filter((m) => m !== 'clients_list')).toEqual(['client_set']);
  });

  test('rejects invalid input before sending it', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: fill(m.clients.manage_named, { name: 'Work-Laptop' }) }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel(m.clients.up_limit, { exact: true }).fill('fast');
    await expect(dialog.getByText(m.clients.limit_invalid)).toBeVisible();
    await dialog.getByRole('switch', { name: m.clients.fixed_ip }).check();
    await dialog.getByLabel(m.clients.fixed_ip_address, { exact: true }).fill('192.168.1.300');
    await expect(dialog.getByText(m.validation.ipv4)).toBeVisible();
    await expect(dialog.getByRole('button', { name: m.common.save, exact: true })).toBeDisabled();
    // rescue_get is the shell's background poll.
    expect(router.calls.filter((c) => !['clients_list', 'rescue_get'].includes(c.method)).map((c) => c.method)).toEqual([]);
  });

  test('forgets offline devices after confirmation', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.clients.forget_offline }).click();
    const dialog = page.getByRole('dialog', { name: m.clients.forget_offline });
    await expect(dialog).toContainText(fill(m.clients.forget_offline_confirm, { count: 1 }));
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.clients.forget_offline }).click();

    await expect(page.getByText(m.clients.none_offline)).toBeVisible();
    expect(router.clients.some((c) => !c.online)).toBe(false);
  });

  test('cancelling a confirmation changes nothing', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.clients.reset_counters }).click();
    await page.getByRole('dialog').getByRole('button', { name: m.common.cancel }).click();
    expect(router.calls.some((c) => c.method === 'clients_reset_counters')).toBe(false);
    expect(router.clients[0].rx_bytes).toBeGreaterThan(0);
  });

  test('remembers the sort order', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.getByLabel(m.clients.sort, { exact: true }).selectOption('ip');
    const online = page.getByRole('table', { name: m.clients.online });
    const firstClient = online.getByRole('row').filter({ has: page.getByRole('cell') }).first();
    await expect(firstClient).toContainText('192.168.1.50');
    await page.reload();
    await expect(page.getByLabel(m.clients.sort, { exact: true })).toHaveValue('ip');
  });
});
