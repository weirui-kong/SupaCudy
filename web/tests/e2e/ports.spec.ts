// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

test.describe('port forwarding', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'ports', messages(testInfo).nav.ports);
  });

  test('forwards a port to a chosen device', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.ports.add_forward }).click();
    const dialog = page.getByRole('dialog', { name: m.ports.add_forward });
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('NAS web');
    await dialog.getByLabel(m.ports.external_port, { exact: true }).fill('8443');
    await dialog.getByLabel(m.ports.device, { exact: true }).selectOption('192.168.1.50');
    await expect(dialog.getByLabel(m.ports.internal_ip, { exact: true })).toHaveValue('192.168.1.50');
    await dialog.getByLabel(m.ports.internal_port, { exact: true }).fill('443');
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.fw.forwards[0]).toMatchObject({ name: 'NAS web', proto: 'tcp', external_port: '8443', internal_ip: '192.168.1.50', internal_port: '443', enabled: true });
    await expect(card(page, m.ports.forwards)).toContainText('8443 → 192.168.1.50:443');
  });

  test('validates ports, ranges and addresses', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.ports.add_forward }).click();
    const dialog = page.getByRole('dialog', { name: m.ports.add_forward });
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('Range');
    await dialog.getByLabel(m.ports.external_port, { exact: true }).fill('9010-9000');
    await expect(dialog.getByText(m.ports.port_invalid)).toBeVisible();
    await dialog.getByLabel(m.ports.external_port, { exact: true }).fill('9000-9010');
    await dialog.getByLabel(m.ports.internal_ip, { exact: true }).fill('10.1.2.3');
    await expect(dialog.getByText(m.ports.not_lan)).toBeVisible();
    await dialog.getByLabel(m.ports.internal_ip, { exact: true }).fill('192.168.1.113');
    await dialog.getByLabel(m.ports.internal_port, { exact: true }).fill('7000-7005');
    await expect(dialog.getByText(m.ports.range_mismatch)).toBeVisible();
    await expect(dialog.getByRole('button', { name: m.common.save })).toBeDisabled();
  });

  test('shows a clash with another rule', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.fw.forwards.push({ id: 'fwd1', name: 'Old', proto: 'tcp', external_port: '8000-8100', internal_ip: '192.168.1.50', internal_port: '', enabled: true });
    await page.reload();
    await page.getByRole('button', { name: m.ports.add_forward }).click();
    const dialog = page.getByRole('dialog', { name: m.ports.add_forward });
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('New');
    await dialog.getByLabel(m.ports.external_port, { exact: true }).fill('8080');
    await dialog.getByLabel(m.ports.internal_ip, { exact: true }).fill('192.168.1.113');
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(page.getByRole('alert')).toContainText(m.errors.reasons.port_in_use);
  });

  test('edits and deletes a port forward', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.fw.forwards.push({ id: 'fwd1', name: 'Cam', proto: 'tcp', external_port: '554', internal_ip: '192.168.1.50', internal_port: '', enabled: true });
    await page.reload();
    await page.getByRole('button', { name: fill(m.common.edit_named, { name: 'Cam' }) }).click();
    const dialog = page.getByRole('dialog', { name: m.ports.edit_forward });
    await dialog.getByRole('switch', { name: m.ports.enabled }).uncheck();
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(card(page, m.ports.forwards)).toContainText(m.ports.disabled);
    expect(router.fw.forwards[0].enabled).toBe(false);
    await page.getByRole('button', { name: fill(m.common.delete_named, { name: 'Cam' }) }).click();
    await page.getByRole('dialog', { name: m.ports.delete_title }).getByRole('button', { name: m.common.delete }).click();
    await expect(card(page, m.ports.forwards)).toContainText(m.ports.none);
  });

  test('sets a DMZ host after warning', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const dmz = card(page, m.ports.dmz);
    await dmz.getByRole('switch', { name: m.ports.dmz_enable }).check();
    await expect(dmz.getByText(m.ports.dmz_warning)).toBeVisible();
    await dmz.getByLabel(m.ports.device, { exact: true }).selectOption('192.168.1.113');
    await dmz.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.fw.dmz).toEqual({ enabled: true, ip: '192.168.1.113' });
  });

  test('opens a port on the router', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.ports.add_open }).click();
    const dialog = page.getByRole('dialog', { name: m.ports.add_open });
    await expect(dialog.getByText(m.ports.open_warning)).toBeVisible();
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('SSH');
    await dialog.getByLabel(m.ports.proto, { exact: true }).selectOption('tcp udp');
    await dialog.getByLabel(m.ports.port, { exact: true }).fill('2222');
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.fw.open_ports[0]).toMatchObject({ name: 'SSH', proto: 'tcp udp', port: '2222', enabled: true });
    await expect(card(page, m.ports.open_ports)).toContainText(`${m.ports.proto_both} 2222`);
  });

  test('sets up dynamic DNS without showing the saved token', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const ddns = card(page, m.ddns.title);
    await ddns.getByRole('switch', { name: m.ddns.enable }).check();
    await ddns.getByLabel(m.ddns.service, { exact: true }).selectOption('duckdns.org');
    await ddns.getByLabel(m.ddns.domain, { exact: true }).fill('nope');
    await expect(ddns.getByText(m.ddns.domain_invalid)).toBeVisible();
    await ddns.getByLabel(m.ddns.domain, { exact: true }).fill('myhome.duckdns.org');
    await expect(ddns.getByText(m.ddns.password_required)).toBeVisible();
    await ddns.getByLabel(m.ddns.password, { exact: true }).fill('token-123');
    await expectPageQuality(page);
    await ddns.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.ddns).toMatchObject({ enabled: true, service: 'duckdns.org', domain: 'myhome.duckdns.org', password: 'token-123' });
    await expect(ddns).toContainText('203.0.113.7');
    await expect(ddns.getByLabel(m.ddns.password, { exact: true })).toHaveValue('');
    await expect(ddns.getByLabel(m.ddns.password, { exact: true })).toHaveAttribute('placeholder', m.vpn.keep_key);
  });
});
