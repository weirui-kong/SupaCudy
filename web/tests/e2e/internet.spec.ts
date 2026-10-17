// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

test.describe('internet', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'internet', messages(testInfo).nav.internet);
  });

  test('shows the Ethernet connection and passes the quality checks', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await expect(page.getByText(m.internet.online, { exact: true })).toBeVisible();
    await expect(page.getByText(fill(m.internet.via, { source: m.internet.ethernet }))).toBeVisible();
    const ethernet = card(page, m.internet.ethernet);
    await expect(ethernet).toContainText(m.internet.proto_dhcp);
    await expect(ethernet).toContainText('10.0.0.15/24');
    await expect(card(page, m.internet.repeater).getByRole('button', { name: m.internet.choose_network })).toBeVisible();
    await expect(page.getByText('Cafe-Free')).toBeVisible();
    await expectPageQuality(page);
  });

  test('shows the offline state without fake values', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.wan.carrier = false;
    await page.reload();
    await expect(page.getByText(m.internet.offline, { exact: true })).toBeVisible();
    const ethernet = card(page, m.internet.ethernet);
    await expect(ethernet).toContainText(m.internet.no_cable);
    await expect(ethernet).toContainText(m.internet.no_cable_hint);
    await expect(ethernet).not.toContainText('10.0.0.15');
    await expectPageQuality(page);
  });

  test('switches the WAN to a static address', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await card(page, m.internet.ethernet).getByRole('button', { name: m.internet.ethernet_settings }).click();
    const dialog = page.getByRole('dialog', { name: m.internet.ethernet_settings });
    await dialog.getByRole('radio', { name: m.internet.proto_static }).check();
    await dialog.getByLabel(m.internet.ipaddr, { exact: true }).fill('203.0.113.10');
    await dialog.getByLabel(m.internet.gateway, { exact: true }).fill('198.51.100.1');
    await expect(dialog.getByText(fill(m.internet.gateway_outside, { network: '203.0.113.0' }))).toBeVisible();
    await expect(dialog.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await dialog.getByLabel(m.internet.gateway, { exact: true }).fill('203.0.113.1');
    await dialog.getByLabel(m.internet.dns1, { exact: true }).fill('9.9.9.9');
    await expect(dialog.getByText(m.internet.wan_apply_warning)).toBeVisible();
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.apply }).click();

    await expect(dialog).toBeHidden();
    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.wan).toMatchObject({ proto: 'static', ipaddr: '203.0.113.10', gateway: '203.0.113.1', dns: ['9.9.9.9'] });
  });

  test('requires a PPPoE user name and rejects bad DNS servers', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await card(page, m.internet.ethernet).getByRole('button', { name: m.internet.ethernet_settings }).click();
    const dialog = page.getByRole('dialog', { name: m.internet.ethernet_settings });
    await dialog.getByRole('radio', { name: m.internet.proto_pppoe }).check();
    await expect(dialog.getByText(m.internet.username_required)).toBeVisible();
    await dialog.getByLabel(m.internet.username, { exact: true }).fill('user@isp');
    await dialog.getByLabel(m.internet.password, { exact: true }).fill('isp-secret');
    await dialog.getByLabel(m.internet.dns2, { exact: true }).fill('not-an-ip');
    await expect(dialog.getByText(m.validation.ipv4)).toBeVisible();
    await expect(dialog.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await dialog.getByLabel(m.internet.dns2, { exact: true }).fill('');
    await dialog.getByRole('button', { name: m.common.apply }).click();
    await expect(dialog).toBeHidden();
    expect(router.wan).toMatchObject({ proto: 'pppoe', username: 'user@isp', password: 'isp-secret', dns: [] });
  });

  test('shows why the router refused a WAN address', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await card(page, m.internet.ethernet).getByRole('button', { name: m.internet.ethernet_settings }).click();
    const dialog = page.getByRole('dialog', { name: m.internet.ethernet_settings });
    await dialog.getByRole('radio', { name: m.internet.proto_static }).check();
    await dialog.getByLabel(m.internet.ipaddr, { exact: true }).fill('192.168.1.20');
    await dialog.getByLabel(m.internet.gateway, { exact: true }).fill('192.168.1.254');
    await dialog.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('alert')).toContainText(fill(m.errors.reasons.subnet_conflict, { with: 'lan' }));
    await expect(dialog).toBeVisible();
    expect(router.wan.proto).toBe('dhcp');
  });

  test('joins a secured network as a repeater', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await card(page, m.internet.repeater).getByRole('button', { name: m.internet.choose_network }).click();
    const dialog = page.getByRole('dialog', { name: m.internet.choose_network });
    await expect(dialog.getByText(fill(m.internet.found, { count: 3 }))).toBeVisible();
    await expect(dialog.getByRole('button', { name: /Hotel-WiFi/ })).toHaveCount(1);
    await expect(dialog.getByRole('button', { name: /Corp-Secure/ })).toBeDisabled();
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: /Hotel-WiFi/ }).click();

    const join = page.getByRole('dialog', { name: fill(m.internet.join_named, { ssid: 'Hotel-WiFi' }) });
    await join.getByLabel(m.wifi.key, { exact: true }).fill('short');
    await expect(join.getByText(m.wifi.key_too_short)).toBeVisible();
    await expect(join.getByRole('button', { name: m.internet.join, exact: true })).toBeDisabled();
    await join.getByLabel(m.wifi.key, { exact: true }).fill('hotel-guest');
    await expectPageQuality(page);
    await join.getByRole('button', { name: m.internet.join, exact: true }).click();

    await expect(join).toBeHidden();
    expect(router.repeater).toMatchObject({ ssid: 'Hotel-WiFi', band: '2g', enabled: true });
    expect(router.calls.find((c) => c.method === 'repeater_connect')?.args).toMatchObject({ key: 'hotel-guest', save: true, encryption: 'psk2' });
    await expect(page.getByText(fill(m.internet.connected_to, { ssid: 'Hotel-WiFi' }))).toBeVisible({ timeout: 10_000 });
    await expect(page.getByRole('listitem').filter({ hasText: 'Hotel-WiFi' })).toBeVisible();
  });

  test('rejoins a saved network without retyping the password', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.repeater.saved.push({ ssid: 'Hotel-WiFi', encryption: 'psk2', key: 'hotel-guest', last_used: 1 });
    await card(page, m.internet.repeater).getByRole('button', { name: m.internet.choose_network }).click();
    await page.getByRole('dialog', { name: m.internet.choose_network }).getByRole('button', { name: /Hotel-WiFi/ }).click();
    const join = page.getByRole('dialog', { name: fill(m.internet.join_named, { ssid: 'Hotel-WiFi' }) });
    await expect(join.getByLabel(m.wifi.key, { exact: true })).toHaveAttribute('placeholder', m.internet.saved_password);
    await join.getByRole('button', { name: m.internet.join, exact: true }).click();
    await expect(join).toBeHidden();
    expect(router.calls.find((c) => c.method === 'repeater_connect')?.args).toMatchObject({ key: '' });
    expect(router.repeater.ssid).toBe('Hotel-WiFi');
  });

  test('warns before joining an open network', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await card(page, m.internet.repeater).getByRole('button', { name: m.internet.choose_network }).click();
    await page.getByRole('dialog', { name: m.internet.choose_network }).getByRole('button', { name: /Cafe-Free/ }).click();
    const join = page.getByRole('dialog', { name: fill(m.internet.join_named, { ssid: 'Cafe-Free' }) });
    await expect(join.getByText(m.internet.open_upstream)).toBeVisible();
    await expect(join.getByLabel(m.wifi.key, { exact: true })).toHaveCount(0);
    await join.getByRole('button', { name: m.internet.back }).click();
    await expect(page.getByRole('dialog', { name: m.internet.choose_network })).toBeVisible();
    expect(router.calls.some((c) => c.method === 'repeater_connect')).toBe(false);
  });

  test('disconnects from the upstream network after confirming', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.repeater, { ssid: 'Hotel-WiFi', band: '2g', enabled: true, connected: true });
    await page.reload();
    const repeater = card(page, m.internet.repeater);
    await expect(repeater).toContainText('-52 dBm');
    await repeater.getByRole('button', { name: m.internet.disconnect }).click();
    const confirm = page.getByRole('dialog', { name: m.internet.disconnect });
    await expect(confirm).toContainText(fill(m.internet.disconnect_confirm, { ssid: 'Hotel-WiFi' }));
    await expectPageQuality(page);
    await confirm.getByRole('button', { name: m.internet.disconnect }).click();
    await expect(confirm).toBeHidden();
    expect(router.repeater.enabled).toBe(false);
  });

  test('warns when the repeater cannot reach its network', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.repeater, { ssid: 'Hotel-WiFi', band: '2g', enabled: true, connected: false });
    await page.reload();
    const repeater = card(page, m.internet.repeater);
    await expect(repeater).toContainText(fill(m.internet.connecting_to, { ssid: 'Hotel-WiFi' }));
    await expect(repeater).toContainText(m.internet.not_connected_hint);
  });

  test('forgets a saved network and changes the repeater options', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: fill(m.internet.forget_named, { ssid: 'Cafe-Free' }) }).click();
    await expect(page.getByText(m.internet.no_saved)).toBeVisible();
    expect(router.repeater.saved).toEqual([]);

    await page.getByRole('switch', { name: m.internet.auto_switch }).uncheck();
    await expect.poll(() => router.repeater.auto_switch).toBe(false);
    await page.getByRole('switch', { name: m.internet.force_20mhz }).check();
    await expect.poll(() => router.repeater.force_20mhz).toBe(true);
    expect(router.repeater.auto_switch).toBe(false);
  });

  test('returns to the login page when the session expires', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.sessions.clear();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title, { timeout: 10_000 });
  });

  test("clones this device's MAC address for the Ethernet WAN", async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const macCard = card(page, m.mac.title);
    await expect(macCard).toContainText('52:54:00:FA:02:01');
    await expect(macCard).toContainText(m.mac.factory_label);
    await macCard.getByRole('button', { name: fill(m.mac.edit_named, { name: m.internet.ethernet }) }).click();

    const dialog = page.getByRole('dialog', { name: m.mac.title_wan });
    await dialog.getByRole('radio', { name: m.mac.mode_clone }).check();
    await expect(dialog.getByLabel(m.mac.clone_from, { exact: true })).toHaveValue('02:5c:00:00:00:11');
    await expect(dialog.getByRole('option', { name: new RegExp(m.mac.this_device) })).toHaveCount(1);
    await expect(dialog.getByText(m.mac.reconnect_wan)).toBeVisible();
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.apply }).click();

    await expect(dialog).toBeHidden();
    expect(router.mac.wanCustom).toBe('02:5c:00:00:00:11');
    expect(router.calls.find((c) => c.method === 'mac_set')?.args).toEqual({ target: 'wan', mode: 'custom', macaddr: '02:5c:00:00:00:11' });
  });

  test('validates a typed MAC address and restores the factory one', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.mac.wanCustom = '02:aa:bb:cc:dd:ee';
    await page.reload();
    const macCard = card(page, m.mac.title);
    await expect(macCard).toContainText(m.mac.custom_label);
    await macCard.getByRole('button', { name: fill(m.mac.edit_named, { name: m.internet.ethernet }) }).click();
    const dialog = page.getByRole('dialog', { name: m.mac.title_wan });
    const field = dialog.getByLabel(m.mac.address, { exact: true });
    await expect(field).toHaveValue('02:aa:bb:cc:dd:ee');
    await field.fill('not a mac');
    await expect(dialog.getByText(m.validation.mac)).toBeVisible();
    await field.fill('01:00:5e:00:00:01');
    await expect(dialog.getByText(m.mac.unusable)).toBeVisible();
    await expect(dialog.getByRole('button', { name: m.common.apply })).toBeDisabled();

    await dialog.getByRole('radio', { name: m.mac.mode_default }).check();
    await dialog.getByRole('button', { name: m.common.apply }).click();
    await expect(dialog).toBeHidden();
    expect(router.mac.wanCustom).toBeNull();
  });

  test('gives the repeater a random MAC address only once it is in use', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const edit = card(page, m.mac.title).getByRole('button', { name: fill(m.mac.edit_named, { name: m.internet.repeater }) });
    await expect(edit).toBeDisabled();
    await expect(card(page, m.mac.title)).toContainText(m.mac.repeater_unused);

    Object.assign(router.repeater, { ssid: 'Hotel-WiFi', band: '2g', enabled: true, connected: true });
    await page.reload();
    await edit.click();
    const dialog = page.getByRole('dialog', { name: m.mac.title_repeater });
    await dialog.getByRole('radio', { name: m.mac.mode_random }).check();
    await dialog.getByRole('button', { name: m.common.apply }).click();
    await expect(dialog).toBeHidden();
    expect(router.mac.repeaterCustom).toBe('06:11:22:33:44:55');
  });

  test('uses a phone connected by USB', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const tether = card(page, m.tethering.title);
    await expect(tether).toContainText(m.tethering.off);
    await tether.getByRole('switch', { name: m.tethering.enable }).check();
    await expect.poll(() => router.tethering.enabled).toBe(true);
    await expect(tether).toContainText(m.tethering.no_phone, { timeout: 10_000 });

    router.tethering.available = true;
    router.wan.carrier = false;
    await page.reload();
    await expect(tether).toContainText('192.168.42.20/24');
    await expect(page.getByText(fill(m.internet.via, { source: m.tethering.title }))).toBeVisible();
    await expectPageQuality(page);
  });

  test('turns the WAN port into a LAN port after warning', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const ethernet = card(page, m.internet.ethernet);
    await ethernet.getByRole('switch', { name: m.internet.wan_as_lan }).check();
    const confirm = page.getByRole('dialog', { name: m.internet.wan_as_lan });
    await expect(confirm).toContainText(m.internet.wan_as_lan_offline);
    await expectPageQuality(page);
    await confirm.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.wanAsLan).toBe(true);
    await expect(ethernet.getByText(m.internet.wan_as_lan_active)).toBeVisible({ timeout: 10_000 });
    await expect(ethernet.getByRole('button', { name: m.internet.ethernet_settings })).toBeDisabled();
    await ethernet.getByRole('switch', { name: m.internet.wan_as_lan }).uncheck();
    await expect.poll(() => router.wanAsLan).toBe(false);
  });

  test('never shows the saved PPPoE password and keeps it when left empty', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.wan, { proto: 'pppoe', username: 'user@isp', password: 'isp-secret' });
    await card(page, m.internet.ethernet).getByRole('button', { name: m.internet.ethernet_settings }).click();
    const dialog = page.getByRole('dialog', { name: m.internet.ethernet_settings });
    const field = dialog.getByLabel(m.internet.password, { exact: true });
    await expect(field).toHaveValue('');
    await expect(field).toHaveAttribute('placeholder', m.vpn.keep_key);
    expect(JSON.stringify(router.calls)).not.toContain('isp-secret');
    await dialog.getByRole('button', { name: m.common.apply }).click();
    await expect(dialog).toBeHidden();
    expect(router.wan).toMatchObject({ proto: 'pppoe', password: 'isp-secret' });
  });
});
