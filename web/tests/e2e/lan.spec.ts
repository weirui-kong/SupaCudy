// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

test.describe('LAN', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'lan', messages(testInfo).nav.lan);
  });

  test('shows the current addressing and passes the quality checks', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await expect(page.getByLabel(m.lan.router_ip, { exact: true })).toHaveValue('192.168.1.1');
    await expect(page.getByText(fill(m.lan.range, { range: '192.168.1.100 – 192.168.1.249' }))).toBeVisible();
    await expect(page.getByText('192.168.1.50')).toBeVisible();
    await expect(page.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await expectPageQuality(page);
  });

  test('changes the DHCP pool', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByLabel(m.lan.start, { exact: true }).fill('50');
    await page.getByLabel(m.lan.limit, { exact: true }).fill('20');
    await page.getByLabel(m.lan.leasetime, { exact: true }).selectOption('24h');
    await expect(page.getByText(fill(m.lan.range, { range: '192.168.1.50 – 192.168.1.69' }))).toBeVisible();
    await page.getByRole('button', { name: m.common.apply }).click();

    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.lan.dhcp).toEqual({ enabled: true, start: 50, limit: 20, leasetime: '24h' });
  });

  test('validates the form before applying', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByLabel(m.lan.router_ip, { exact: true }).fill('192.168.1.0');
    await expect(page.getByText(m.lan.ip_network_or_broadcast)).toBeVisible();
    await page.getByLabel(m.lan.router_ip, { exact: true }).fill('8.8.8.1');
    await expect(page.getByText(m.lan.ip_not_private)).toBeVisible();
    await page.getByLabel(m.lan.router_ip, { exact: true }).fill('192.168.1.1');
    await page.getByLabel(m.lan.limit, { exact: true }).fill('400');
    await expect(page.getByText(fill(m.lan.limit_invalid, { max: 155 }))).toBeVisible();
    await expect(page.getByRole('button', { name: m.common.apply })).toBeDisabled();
    expect(router.calls.some((c) => c.method === 'lan_set')).toBe(false);
  });

  test('warns before moving the router to a new address', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByLabel(m.lan.router_ip, { exact: true }).fill('192.168.50.1');
    await expect(page.getByText(m.lan.address_change_warning)).toBeVisible();
    await page.getByRole('button', { name: m.common.apply }).click();

    const confirm = page.getByRole('dialog', { name: m.lan.change_address });
    await expect(confirm).toContainText(fill(m.lan.change_address_confirm, { ip: '192.168.50.1' }));
    await expectPageQuality(page);
    await confirm.getByRole('button', { name: m.common.apply }).click();

    await expect(page.getByRole('link', { name: 'http://192.168.50.1/supacudy/' })).toBeVisible();
    expect(router.lan.ipaddr).toBe('192.168.50.1');
  });

  test('shows why the router refused a change', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.failNext('lan_set', { status: 0, data: { error: 'subnet_conflict', with: 'guest' } });
    await page.getByLabel(m.lan.start, { exact: true }).fill('20');
    await page.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('alert')).toContainText(fill(m.errors.reasons.subnet_conflict, { with: 'guest' }));
  });

  test('adds, edits and deletes a fixed address', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.lan.add_reservation }).click();
    let dialog = page.getByRole('dialog', { name: m.lan.add_reservation });
    await dialog.getByLabel(m.lan.device, { exact: true }).selectOption('02:5c:00:00:00:11');
    await expect(dialog.getByLabel(m.clients.fixed_ip_address, { exact: true })).toHaveValue('192.168.1.113');
    await dialog.getByLabel(m.clients.fixed_ip_address, { exact: true }).fill('192.168.1.30');
    await dialog.getByLabel(m.lan.hostname, { exact: true }).fill('laptop');
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.save, exact: true }).click();
    await expect(dialog).toBeHidden();
    expect(router.clients[0].reserved_ip).toBe('192.168.1.30');

    await page.getByRole('button', { name: fill(m.common.edit_named, { name: '192.168.1.30' }) }).click();
    dialog = page.getByRole('dialog', { name: m.lan.edit_reservation });
    await dialog.getByLabel(m.clients.fixed_ip_address, { exact: true }).fill('192.168.1.31');
    await dialog.getByRole('button', { name: m.common.save, exact: true }).click();
    await expect(dialog).toBeHidden();
    expect(router.clients[0].reserved_ip).toBe('192.168.1.31');

    await page.getByRole('button', { name: fill(m.common.delete_named, { name: '192.168.1.31' }) }).click();
    await page.getByRole('dialog', { name: m.lan.delete_reservation }).getByRole('button', { name: m.common.delete }).click();
    await expect(page.getByText('192.168.1.31', { exact: true })).toBeHidden();
    expect(router.clients[0].reserved_ip).toBeNull();
  });

  test('rejects a fixed address outside the LAN or already taken', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.lan.add_reservation }).click();
    const dialog = page.getByRole('dialog', { name: m.lan.add_reservation });
    await dialog.getByLabel(m.lan.device, { exact: true }).selectOption('manual');
    await dialog.getByLabel(m.clients.mac, { exact: true }).fill('aa:bb:cc:dd:ee:ff');
    await dialog.getByLabel(m.clients.fixed_ip_address, { exact: true }).fill('10.0.0.5');
    await expect(dialog.getByText(fill(m.lan.ip_outside, { network: '192.168.1.0/24' }))).toBeVisible();
    await dialog.getByLabel(m.clients.fixed_ip_address, { exact: true }).fill('192.168.1.50');
    await expect(dialog.getByText(m.lan.ip_taken)).toBeVisible();
    await expect(dialog.getByRole('button', { name: m.common.save, exact: true })).toBeDisabled();
  });

  test('turns the router into an access point after a clear warning', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const mode = page.getByRole('region', { name: m.netmode.title, exact: true });
    await expect(mode).toContainText(m.netmode.is_router);
    await mode.getByRole('button', { name: m.netmode.to_ap }).click();
    const form = page.getByRole('dialog', { name: m.netmode.to_ap });
    await expect(form.getByLabel(m.netmode.ap_address, { exact: true })).toHaveValue('10.0.0.15');
    await expect(form.getByLabel(m.netmode.main_router, { exact: true })).toHaveValue('10.0.0.1');
    await form.getByLabel(m.netmode.ap_address, { exact: true }).fill('10.0.0.250');
    await form.getByLabel(m.netmode.main_router, { exact: true }).fill('10.0.1.1');
    await expect(form.getByText(fill(m.internet.gateway_outside, { network: '10.0.0.0' }))).toBeVisible();
    await form.getByLabel(m.netmode.main_router, { exact: true }).fill('10.0.0.1');
    await expectPageQuality(page);
    await form.getByRole('button', { name: m.setup.next }).click();
    const confirm = page.getByRole('dialog', { name: m.netmode.to_ap }).filter({ hasText: m.netmode.ap_consequence.slice(0, 20) });
    await expect(confirm).toContainText(fill(m.netmode.ap_consequence, { ip: '10.0.0.250' }));
    await confirm.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('link', { name: 'http://10.0.0.250/supacudy/' })).toBeVisible();
    expect(router.netmode.mode).toBe('ap');
    expect(router.calls.find((c) => c.method === 'netmode_set')?.args).toEqual({ mode: 'ap', ipaddr: '10.0.0.250', netmask: '255.255.255.0', gateway: '10.0.0.1', dns: ['10.0.0.1'] });
  });

  test('switches back from access point to router mode', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.netmode = { mode: 'ap', saved: { ipaddr: '192.168.1.1' } };
    router.lan.ipaddr = '10.0.0.250';
    await page.reload();
    const mode = page.getByRole('region', { name: m.netmode.title, exact: true });
    await expect(mode).toContainText(fill(m.netmode.is_ap, { ip: '10.0.0.250' }));
    await mode.getByRole('button', { name: m.netmode.to_router }).click();
    const confirm = page.getByRole('dialog', { name: m.netmode.to_router });
    await expect(confirm).toContainText(m.netmode.router_consequence);
    await confirm.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.netmode.mode).toBe('router');
    expect(router.lan.ipaddr).toBe('192.168.1.1');
  });
});
