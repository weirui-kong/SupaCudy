// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';
import type { MockRouter } from './mock/router';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

// Test-only keys, not used anywhere real.
const PRIVATE = 'oGwIsQXePkq1NIVJdElbnzYDLLHMwFq5A+5Ilruz11s=';
const PUBLIC = 'qrYCfRcXMOaEA2xznhSAKdDiPRWAHe6VeBTg4Jqawzg=';
const PSK = 'irMdu0PKEDRBjbj/oi0azFqXoQ6PlS7h9dY2NMRHFp8=';
const CONF = `[Interface]
PrivateKey = ${PRIVATE}
Address = 10.250.30.2/32, fd00::2/128
DNS = 10.250.2.3, corp.example

[Peer]
PublicKey = ${PUBLIC}
PresharedKey = ${PSK}
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
`;

function addProfile(router: MockRouter) {
  router.vpn.profiles.push({
    id: 'cfg1', name: 'Home server', addresses: ['10.250.30.2/32'], dns: ['10.250.2.3'], mtu: 0, public_key: PUBLIC,
    endpoint_host: 'vpn.example.com', endpoint_port: 51820, allowed_ips: ['0.0.0.0/0'], keepalive: 25,
    private_key: PRIVATE, preshared_key: PSK,
  });
}

test.describe('vpn', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'vpn', messages(testInfo).nav.vpn);
  });

  test('starts disconnected and explains what to do', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await expect(card(page, m.vpn.status)).toContainText(m.vpn.not_connected);
    await expect(card(page, m.vpn.profiles)).toContainText(m.vpn.no_profiles);
    await expect(page.getByRole('switch', { name: m.vpn.allow_lan })).toBeDisabled();
    await expectPageQuality(page);
  });

  test('imports a pasted configuration, fills the form and saves it', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.vpn.add_profile }).click();
    const dialog = page.getByRole('dialog', { name: m.vpn.add_profile });
    await dialog.getByLabel(m.vpn.config_text, { exact: true }).fill(CONF);
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.vpn.read_config }).click();

    // Nothing is saved until the user checks the fields and saves.
    expect(router.vpn.profiles).toEqual([]);
    await expect(dialog.getByLabel(m.vpn.endpoint, { exact: true })).toHaveValue('vpn.example.com:51820');
    await expect(dialog.getByLabel(m.vpn.addresses, { exact: true })).toHaveValue('10.250.30.2/32, fd00::2/128');
    await expect(dialog.getByLabel(m.vpn.dns, { exact: true })).toHaveValue('10.250.2.3');
    await expect(dialog.getByLabel(m.vpn.name, { exact: true })).toHaveValue('vpn.example.com');
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('Travel VPN');
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.save }).click();

    await expect(dialog).toBeHidden();
    expect(router.vpn.profiles[0]).toMatchObject({
      name: 'Travel VPN', private_key: PRIVATE, public_key: PUBLIC, preshared_key: PSK,
      addresses: ['10.250.30.2/32', 'fd00::2/128'], allowed_ips: ['0.0.0.0/0', '::/0'], keepalive: 25,
    });
    await expect(card(page, m.vpn.profiles)).toContainText('Travel VPN');
  });

  test('opens a .conf file', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.vpn.add_profile }).click();
    const dialog = page.getByRole('dialog', { name: m.vpn.add_profile });
    const chooser = page.waitForEvent('filechooser');
    await dialog.getByRole('button', { name: m.vpn.import_file }).click();
    await (await chooser).setFiles({ name: 'tokyo-01.conf', mimeType: 'text/plain', buffer: Buffer.from(CONF) });
    await expect(dialog.getByLabel(m.vpn.name, { exact: true })).toHaveValue('tokyo-01');
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.vpn.profiles[0].name).toBe('tokyo-01');
  });

  test('says what is wrong with a configuration it cannot read', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.vpn.add_profile }).click();
    const dialog = page.getByRole('dialog', { name: m.vpn.add_profile });
    await dialog.getByLabel(m.vpn.config_text, { exact: true }).fill('[Interface]\nPrivateKey = x\n');
    await dialog.getByRole('button', { name: m.vpn.read_config }).click();
    await expect(dialog.getByText(m.vpn.parse_no_peer)).toBeVisible();
    expect(router.vpn.profiles).toEqual([]);
  });

  test('validates a profile filled in by hand', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.vpn.add_profile }).click();
    const dialog = page.getByRole('dialog', { name: m.vpn.add_profile });
    await dialog.getByRole('radio', { name: m.vpn.source_manual }).check();
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('Manual');
    await dialog.getByLabel(m.vpn.endpoint, { exact: true }).fill('vpn.example.com');
    await expect(dialog.getByText(m.vpn.endpoint_invalid)).toBeVisible();
    await dialog.getByLabel(m.vpn.endpoint, { exact: true }).fill('[2001:db8::1]:51820');
    await dialog.getByLabel(m.vpn.public_key, { exact: true }).fill('short');
    await expect(dialog.getByText(m.vpn.key_invalid)).toBeVisible();
    await dialog.getByLabel(m.vpn.public_key, { exact: true }).fill(PUBLIC);
    await dialog.getByLabel(m.vpn.private_key, { exact: true }).fill(PRIVATE);
    await dialog.getByLabel(m.vpn.addresses, { exact: true }).fill('10.0.0.2');
    await expect(dialog.getByText(m.vpn.addresses_invalid)).toBeVisible();
    await expect(dialog.getByRole('button', { name: m.common.save })).toBeDisabled();
    await dialog.getByLabel(m.vpn.addresses, { exact: true }).fill('10.0.0.2/32');
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.vpn.profiles[0]).toMatchObject({ endpoint_host: '2001:db8::1', endpoint_port: 51820, allowed_ips: ['0.0.0.0/0'] });
  });

  test('connects, shows the tunnel and disconnects', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    addProfile(router);
    await page.reload();
    await card(page, m.vpn.profiles).getByRole('button', { name: m.vpn.connect }).click();
    const status = card(page, m.vpn.status);
    await expect(status).toContainText(fill(m.vpn.connected, { name: 'Home server' }));
    await expect(status).toContainText('203.0.113.5:51820');
    await expect(status).toContainText('10.250.30.2/32');
    // The profile has no IPv6 address, so IPv6 must not bypass the tunnel.
    await expect(status).toContainText(m.vpn.ipv6_blocked);
    await expect(card(page, m.vpn.profiles)).toContainText(m.vpn.in_use);
    await expect(card(page, m.vpn.profiles).getByRole('button', { name: fill(m.common.delete_named, { name: 'Home server' }) })).toBeDisabled();
    await expectPageQuality(page);
    await status.getByRole('button', { name: m.vpn.disconnect }).click();
    await expect(status).toContainText(m.vpn.not_connected);
    expect(router.vpn.active).toBeNull();
  });

  test('sends IPv6 through the tunnel when the profile has an IPv6 address', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    addProfile(router);
    router.vpn.profiles[0].addresses = ['10.250.30.2/32', 'fd00:250::2/128'];
    router.vpn.active = 'cfg1';
    await page.reload();
    await expect(card(page, m.vpn.status)).toContainText(m.vpn.ipv6_tunnel);
  });

  test('says when the server does not answer', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    addProfile(router);
    router.vpn.active = 'cfg1';
    router.vpn.reachable = false;
    await page.reload();
    await expect(card(page, m.vpn.status)).toContainText(fill(m.vpn.connecting, { name: 'Home server' }));
    await expect(card(page, m.vpn.status)).toContainText(m.vpn.never);
  });

  test('edits a profile keeping its keys', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    addProfile(router);
    await page.reload();
    await page.getByRole('button', { name: fill(m.common.edit_named, { name: 'Home server' }) }).click();
    const dialog = page.getByRole('dialog', { name: fill(m.vpn.edit_profile, { name: 'Home server' }) });
    await expect(dialog.getByLabel(m.vpn.private_key, { exact: true })).toHaveValue('');
    await expect(dialog.getByLabel(m.vpn.private_key, { exact: true })).toHaveAttribute('placeholder', m.vpn.keep_key);
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('Home');
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.vpn.profiles[0]).toMatchObject({ name: 'Home', private_key: PRIVATE, preshared_key: PSK });
  });

  test('deletes a profile after confirming', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    addProfile(router);
    await page.reload();
    await page.getByRole('button', { name: fill(m.common.delete_named, { name: 'Home server' }) }).click();
    const confirm = page.getByRole('dialog', { name: m.vpn.delete_profile });
    await expect(confirm).toContainText(fill(m.vpn.delete_confirm, { name: 'Home server' }));
    await confirm.getByRole('button', { name: m.common.delete }).click();
    await expect(card(page, m.vpn.profiles)).toContainText(m.vpn.no_profiles);
    expect(router.vpn.profiles).toEqual([]);
  });

  test('turns on the kill switch and the upstream network exception', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('switch', { name: m.vpn.kill_switch }).check();
    await expect.poll(() => router.vpn.kill_switch).toBe(true);
    const allow = page.getByRole('switch', { name: m.vpn.allow_lan });
    await expect(allow).toBeEnabled();
    await allow.uncheck();
    await expect.poll(() => router.vpn.allow_lan).toBe(false);
  });

  test('sends only chosen devices through the VPN', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('radio', { name: m.vpn.route_selected }).check();
    await expect.poll(() => router.vpn.route_mode).toBe('selected');
    await expect(page.getByText(m.vpn.route_selected_dns)).toBeVisible();
    await expect(page.getByText(m.vpn.kill_switch_selected_hint)).toBeVisible();
    await page.getByRole('switch', { name: 'Pixel-Phone' }).check();
    await expect.poll(() => router.vpn.devices).toEqual(['6a:00:00:00:02:00']);
    await page.getByRole('switch', { name: 'Home NAS' }).check();
    await expect.poll(() => router.vpn.devices).toEqual(['6a:00:00:00:02:00', '00:11:32:aa:bb:12']);
    await expectPageQuality(page);
    await page.getByRole('switch', { name: 'Pixel-Phone' }).uncheck();
    await expect.poll(() => router.vpn.devices).toEqual(['00:11:32:aa:bb:12']);
  });

  test('keeps listing a chosen device that left the network', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.vpn, { route_mode: 'selected', devices: ['02:aa:00:00:00:99'] });
    await page.reload();
    await expect(page.getByRole('switch', { name: '02:AA:00:00:00:99' })).toBeChecked();
    await expect(page.getByRole('radio', { name: m.vpn.route_selected })).toBeChecked();
  });

  test('adds an OpenVPN profile from a file and connects it', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.vpn.add_openvpn }).click();
    const dialog = page.getByRole('dialog', { name: m.vpn.add_openvpn });
    await expect(dialog.getByRole('button', { name: m.common.save })).toBeDisabled();
    const chooser = page.waitForEvent('filechooser');
    await dialog.getByRole('button', { name: m.vpn.import_file }).click();
    await (await chooser).setFiles({
      name: 'office.ovpn', mimeType: 'text/plain',
      buffer: Buffer.from('client\ndev tun\nproto udp\nremote vpn.example.com 1194\n<ca>\n-----BEGIN CERTIFICATE-----\n</ca>\n'),
    });
    await expect(dialog.getByLabel(m.vpn.name, { exact: true })).toHaveValue('office');
    await dialog.getByLabel(m.vpn.username, { exact: true }).fill('alice');
    await dialog.getByLabel(m.internet.password, { exact: true }).fill('s3cret');
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.vpn.profiles[0]).toMatchObject({ type: 'openvpn', name: 'office', remote: 'vpn.example.com:1194', username: 'alice', password: 's3cret' });

    const profiles = card(page, m.vpn.profiles);
    await expect(profiles).toContainText('OpenVPN · vpn.example.com:1194');
    await profiles.getByRole('button', { name: m.vpn.connect }).click();
    await expect(card(page, m.vpn.status)).toContainText(fill(m.vpn.connected, { name: 'office' }));
    await expect(card(page, m.vpn.status)).not.toContainText(m.vpn.last_handshake);
    await expect(page.getByText(m.vpn.route_ovpn)).toBeVisible();
  });

  test('shows why the router refused an OpenVPN file', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.vpn.add_openvpn }).click();
    const dialog = page.getByRole('dialog', { name: m.vpn.add_openvpn });
    await dialog.getByLabel(m.vpn.config_text, { exact: true }).fill('client\n');
    await expect(dialog.getByText(m.vpn.ovpn_no_remote)).toBeVisible();
    await dialog.getByLabel(m.vpn.config_text, { exact: true }).fill('client\nremote vpn.example.com 1194\nup /tmp/evil.sh\n');
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('Evil');
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(page.getByRole('alert')).toContainText(fill(m.errors.reasons.ovpn_unsafe, { directive: 'up' }));
    expect(router.vpn.profiles).toEqual([]);
  });

  test('edits an OpenVPN profile keeping its file and password', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.vpn.profiles.push({
      id: 'cfg1', type: 'openvpn', name: 'Office', remote: 'vpn.example.com:1194', config: 'remote vpn.example.com 1194',
      username: 'alice', password: 'old', private_key: '', preshared_key: '',
    });
    await page.reload();
    await page.getByRole('button', { name: fill(m.common.edit_named, { name: 'Office' }) }).click();
    const dialog = page.getByRole('dialog', { name: fill(m.vpn.edit_profile, { name: 'Office' }) });
    await expect(dialog.getByText(m.vpn.ovpn_keep)).toBeVisible();
    await dialog.getByLabel(m.vpn.name, { exact: true }).fill('Work');
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.vpn.profiles[0]).toMatchObject({ name: 'Work', config: 'remote vpn.example.com 1194', password: 'old' });
  });

  test('sends chosen websites and networks through the VPN', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('radio', { name: m.vpn.route_selected }).check();
    const area = page.getByLabel(m.vpn.destinations);
    await area.fill('example.com\nnot a host');
    await expect(page.getByText(fill(m.vpn.destination_bad, { value: 'not' }))).toBeVisible();
    await area.fill('example.com\n203.0.113.0/24');
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.vpn.destinations).toEqual(['example.com', '203.0.113.0/24']);
  });

  test('offers only networks when the router cannot route by website', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.vpn, { route_mode: 'selected', domains_supported: false });
    await page.reload();
    await expect(page.getByText(m.vpn.destinations_hint_ip)).toBeVisible();
    await page.getByLabel(m.vpn.destinations).fill('example.com');
    await expect(page.getByText(fill(m.vpn.destination_bad, { value: 'example.com' }))).toBeVisible();
  });
});
