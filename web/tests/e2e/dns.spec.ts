// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, expectPageQuality, messages, openPage, test } from './helpers';

test.describe('dns', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'dns', messages(testInfo).nav.dns);
  });

  test('starts on automatic with nothing to apply', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await expect(page.getByRole('radio', { name: m.dns.mode_auto })).toBeChecked();
    await expect(page.getByText(m.dns.mode_hint_auto)).toBeVisible();
    await expect(page.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await expectPageQuality(page);
  });

  test('sets manual DNS servers after validating them', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('radio', { name: m.dns.mode_manual }).check();
    const apply = page.getByRole('button', { name: m.common.apply });
    await expect(page.getByText(m.dns.server_required)).toBeVisible();
    await expect(apply).toBeDisabled();
    await page.getByLabel(m.internet.dns1, { exact: true }).fill('9.9.9');
    await expect(page.getByText(m.validation.ipv4)).toBeVisible();
    await page.getByLabel(m.internet.dns1, { exact: true }).fill('9.9.9.9');
    await page.getByLabel(m.internet.dns2, { exact: true }).fill('1.1.1.1');
    await expectPageQuality(page);
    await apply.click();
    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.dns).toMatchObject({ mode: 'manual', servers: ['9.9.9.9', '1.1.1.1'] });
    await expect(apply).toBeDisabled();
  });

  test('turns on encrypted DNS with a listed provider', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('radio', { name: m.dns.mode_encrypted }).check();
    await expect(page.getByText(m.dns.encrypted_warning)).toBeVisible();
    // AliDNS is the default provider.
    await expect(page.getByLabel(m.dns.provider, { exact: true }).locator('option:checked')).toHaveText(m.dns.providers.alidns);
    await page.getByLabel(m.dns.provider, { exact: true }).selectOption('cloudflare');
    await expect(page.getByLabel(m.dns.provider, { exact: true }).locator('option:checked')).toHaveText(m.dns.providers.cloudflare);
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.dns).toMatchObject({ mode: 'encrypted', provider: 'cloudflare' });
    expect(router.calls.find((c) => c.method === 'dns_set')?.args).toEqual({ mode: 'encrypted', servers: [], provider: 'cloudflare', url: '' });
  });

  test('uses AliDNS when encrypted DNS is turned on without picking a provider', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('radio', { name: m.dns.mode_encrypted }).check();
    await page.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.calls.find((c) => c.method === 'dns_set')?.args).toEqual({ mode: 'encrypted', servers: [], provider: 'alidns', url: '' });
  });

  test('checks a custom DoH address', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('radio', { name: m.dns.mode_encrypted }).check();
    await page.getByLabel(m.dns.provider, { exact: true }).selectOption('custom');
    const field = page.getByLabel(m.dns.url, { exact: true });
    await field.fill('http://dns.example/dns-query');
    await expect(page.getByText(m.dns.url_invalid)).toBeVisible();
    await expect(page.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await field.fill('https://dns.example/dns-query');
    await page.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.dns).toMatchObject({ mode: 'encrypted', provider: 'custom', url: 'https://dns.example/dns-query' });
  });

  test('hides encrypted DNS when the router cannot do it', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.dns.encrypted_available = false;
    await page.reload();
    await expect(page.getByRole('radio', { name: m.dns.mode_manual })).toBeVisible();
    await expect(page.getByRole('radio', { name: m.dns.mode_encrypted })).toHaveCount(0);
    await expect(page.getByText(m.dns.encrypted_missing)).toBeVisible();
  });

  test('shows why the router refused the change', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.failNext('dns_set', { status: 0, data: { error: 'encrypted_unavailable' } });
    await page.getByRole('radio', { name: m.dns.mode_encrypted }).check();
    await page.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('alert')).toContainText(m.errors.reasons.encrypted_unavailable);
    expect(router.dns.mode).toBe('auto');
  });

  test('turns off rebind protection', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('switch', { name: m.dns.rebind_enable }).uncheck();
    await expect.poll(() => router.dns.rebind_protection).toBe(false);
  });

  test('adds, renames and deletes a local host name', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.dns.add_host }).click();
    const dialog = page.getByRole('dialog', { name: m.dns.add_host });
    await dialog.getByLabel(m.dns.hostname, { exact: true }).fill('bad name');
    await expect(dialog.getByText(m.dns.hostname_invalid)).toBeVisible();
    await dialog.getByLabel(m.dns.hostname, { exact: true }).fill('nas.home');
    await dialog.getByLabel(m.internet.ipaddr, { exact: true }).fill('192.168.1.50');
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.dns.hosts).toEqual([{ id: 'host1', name: 'nas.home', ip: '192.168.1.50' }]);

    await page.getByRole('button', { name: m.common.edit_named.replace('{name}', 'nas.home') }).click();
    const edit = page.getByRole('dialog', { name: m.common.edit_named.replace('{name}', 'nas.home') });
    await edit.getByLabel(m.dns.hostname, { exact: true }).fill('files.home');
    await edit.getByRole('button', { name: m.common.save }).click();
    await expect.poll(() => router.dns.hosts[0]?.name).toBe('files.home');
    await page.getByRole('button', { name: m.common.delete_named.replace('{name}', 'files.home') }).click();
    await expect.poll(() => router.dns.hosts.length).toBe(0);
  });

  test('refuses a duplicate host name', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.dns.hosts.push({ id: 'host1', name: 'nas.home', ip: '192.168.1.50' });
    await page.reload();
    await page.getByRole('button', { name: m.dns.add_host }).click();
    const dialog = page.getByRole('dialog', { name: m.dns.add_host });
    await dialog.getByLabel(m.dns.hostname, { exact: true }).fill('NAS.home');
    await dialog.getByLabel(m.internet.ipaddr, { exact: true }).fill('192.168.1.51');
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(page.getByRole('alert')).toContainText(m.errors.reasons.host_exists);
  });
});
