// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

test.describe('wireless', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'wireless', messages(testInfo).nav.wireless);
  });

  test('shows both radios with their networks and passes the quality checks', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const two = card(page, fill(m.wifi.radio_title, { band: m.bands['2g'] }));
    const five = card(page, fill(m.wifi.radio_title, { band: m.bands['5g'] }));
    await expect(two.getByLabel(m.wifi.ssid, { exact: true })).toHaveValue('Home-WiFi');
    await expect(five.getByLabel(m.wifi.ssid, { exact: true })).toHaveValue('Home-WiFi-5G');
    await expect(two.getByLabel(m.wifi.security, { exact: true })).toHaveValue('sae-mixed');
    await expect(page.getByRole('region', { name: fill(m.wifi.guest_title, { band: m.bands['2g'] }) })).toBeVisible();
    await expectPageQuality(page);
  });

  test('changes the network name and password after warning about reconnecting', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const two = card(page, fill(m.wifi.radio_title, { band: m.bands['2g'] }));
    await two.getByLabel(m.wifi.ssid, { exact: true }).fill('Travel-WiFi');
    await two.getByLabel(m.wifi.key, { exact: true }).fill('new-secret-1');
    await two.getByRole('button', { name: m.common.apply }).click();

    const confirm = page.getByRole('dialog', { name: m.wifi.reconnect_title });
    await expect(confirm).toContainText(fill(m.wifi.reconnect_message, { band: m.bands['2g'] }));
    await expectPageQuality(page);
    await confirm.getByRole('button', { name: m.common.apply }).click();

    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.wifi.radios[0].main).toMatchObject({ ssid: 'Travel-WiFi', key: 'new-secret-1' });
  });

  test('changes advanced settings without a reconnect warning', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const five = card(page, fill(m.wifi.radio_title, { band: m.bands['5g'] }));
    await five.getByRole('button', { name: m.wifi.advanced }).click();
    await five.getByLabel(m.wifi.channel, { exact: true }).selectOption('149');
    await five.getByLabel(m.wifi.width, { exact: true }).selectOption('40');
    await five.getByLabel(m.wifi.txpower, { exact: true }).selectOption('low');
    await five.getByRole('button', { name: m.common.apply }).click();

    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    await expect(page.getByRole('dialog', { name: m.wifi.reconnect_title })).not.toBeVisible();
    expect(router.wifi.radios[1]).toMatchObject({ channel: 149, width: 40, txpower: 'low' });
  });

  test('validates the name and password as the user types', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const two = card(page, fill(m.wifi.radio_title, { band: m.bands['2g'] }));
    await two.getByLabel(m.wifi.ssid, { exact: true }).fill('');
    await expect(two.getByText(m.wifi.ssid_empty)).toBeVisible();
    await two.getByLabel(m.wifi.ssid, { exact: true }).fill('我的超长无线网络名称测试一二三');
    await expect(two.getByText(m.wifi.ssid_too_long)).toBeVisible();
    await two.getByLabel(m.wifi.ssid, { exact: true }).fill('Home-WiFi');
    await two.getByLabel(m.wifi.key, { exact: true }).fill('short');
    await expect(two.getByText(m.wifi.key_too_short)).toBeVisible();
    await expect(two.getByRole('button', { name: m.common.apply })).toBeDisabled();
    expect(router.calls.some((c) => c.method === 'wifi_set')).toBe(false);
  });

  test('warns about an open network and drops the password field', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const two = card(page, fill(m.wifi.radio_title, { band: m.bands['2g'] }));
    await two.getByLabel(m.wifi.security, { exact: true }).selectOption('none');
    await expect(two.getByText(m.wifi.open_warning)).toBeVisible();
    await expect(two.getByLabel(m.wifi.key, { exact: true })).toHaveCount(0);
  });

  test('locks channel and width while the radio is used as a repeater', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.wifi.radios[0].locked = 'repeater';
    await page.reload();
    const two = card(page, fill(m.wifi.radio_title, { band: m.bands['2g'] }));
    await two.getByRole('button', { name: m.wifi.advanced }).click();
    await expect(two.getByText(m.wifi.locked_repeater)).toBeVisible();
    await expect(two.getByLabel(m.wifi.channel, { exact: true })).toBeDisabled();
    await expect(two.getByLabel(m.wifi.width, { exact: true })).toBeDisabled();
    await expect(two.getByLabel(m.wifi.txpower, { exact: true })).toBeEnabled();
  });

  test('turns a radio off', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const five = card(page, fill(m.wifi.radio_title, { band: m.bands['5g'] }));
    await five.getByRole('switch', { name: fill(m.wifi.enable, { band: m.bands['5g'] }) }).uncheck();
    await expect(five.getByText(fill(m.wifi.disabled_hint, { band: m.bands['5g'] }))).toBeVisible();
    await five.getByRole('button', { name: m.common.apply }).click();
    await page.getByRole('dialog', { name: m.wifi.reconnect_title }).getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.wifi.radios[1].enabled).toBe(false);
  });

  test('sets up a guest network', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const guest = card(page, fill(m.wifi.guest_title, { band: m.bands['2g'] }));
    await guest.getByRole('switch', { name: fill(m.wifi.guest_enable, { band: m.bands['2g'] }) }).check();
    await expect(guest.getByLabel(m.wifi.ssid, { exact: true })).toHaveValue('Home-WiFi-Guest');
    await expect(guest.getByText(m.wifi.guest_isolation)).toBeVisible();
    await guest.getByLabel(m.wifi.key, { exact: true }).fill('welcome-guests');
    await expectPageQuality(page);
    await guest.getByRole('button', { name: m.common.apply }).click();

    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.wifi.radios[0].guest).toMatchObject({ enabled: true, ssid: 'Home-WiFi-Guest', key: 'welcome-guests' });
    await expect(guest.getByText(fill(m.wifi.guest_isolation_subnet, { subnet: '192.168.2.0/24' }))).toBeVisible({ timeout: 10_000 });
  });

  test('explains a refusal from the router', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.failNext('wifi_set', { status: 0, data: { error: 'channel_unavailable' } });
    const five = card(page, fill(m.wifi.radio_title, { band: m.bands['5g'] }));
    await five.getByRole('button', { name: m.wifi.advanced }).click();
    await five.getByLabel(m.wifi.channel, { exact: true }).selectOption('36');
    await five.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('alert')).toContainText(m.errors.reasons.channel_unavailable);
  });

  test('shares the network as a QR code', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const two = card(page, fill(m.wifi.radio_title, { band: m.bands['2g'] }));
    await two.getByRole('button', { name: m.wifi.share }).click();
    const dialog = page.getByRole('dialog', { name: fill(m.wifi.share_title, { ssid: 'Home-WiFi' }) });
    await expect(dialog.getByRole('img', { name: fill(m.wifi.share_qr, { ssid: 'Home-WiFi' }) })).toBeVisible();
    await expect(dialog).not.toContainText('correct-horse');
    await dialog.getByRole('button', { name: m.login.show_password }).click();
    await expect(dialog).toContainText('correct-horse');
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.close }).last().click();
    await expect(dialog).toBeHidden();
  });

  test('offers sharing only for networks that are on', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.wifi.radios[1].main.enabled = false;
    await page.reload();
    await expect(card(page, fill(m.wifi.radio_title, { band: m.bands['5g'] })).getByRole('button', { name: m.wifi.share })).toHaveCount(0);
    await expect(card(page, fill(m.wifi.guest_title, { band: m.bands['2g'] })).getByRole('button', { name: m.wifi.share })).toHaveCount(0);
  });

  test('merges both bands into one network after warning', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const bands = card(page, m.wifi.bands_title);
    const toggle = bands.getByRole('switch', { name: m.wifi.bands_merge });
    await expect(toggle).not.toBeChecked();
    await toggle.check();
    await bands.getByLabel(m.wifi.ssid, { exact: true }).fill('Family');
    await expectPageQuality(page);
    await bands.getByRole('button', { name: m.common.apply }).click();
    const confirm = page.getByRole('dialog', { name: m.wifi.reconnect_title });
    await expect(confirm).toContainText(fill(m.wifi.bands_reconnect, { ssid: 'Family' }));
    await confirm.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.wifi.radios.map((r) => r.main.ssid)).toEqual(['Family', 'Family']);
    expect(router.wifi.radios[1]).toMatchObject({ channel: 'auto', width: 80 });
  });

  test('splits merged bands back into separate names', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.wifi.radios[1].main.ssid = 'Home-WiFi';
    await page.reload();
    const toggle = card(page, m.wifi.bands_title).getByRole('switch', { name: m.wifi.bands_merge });
    await expect(toggle).toBeChecked();
    await toggle.click();
    const confirm = page.getByRole('dialog', { name: m.wifi.reconnect_title });
    await expect(confirm).toContainText(m.wifi.bands_split_reconnect);
    await expectPageQuality(page);
    await confirm.getByRole('button', { name: m.wifi.bands_split }).click();
    await expect.poll(() => router.wifi.radios.map((r) => r.main.ssid)).toEqual(['Home-WiFi', 'Home-WiFi-5G']);
    await expect(toggle).not.toBeChecked();
    await expect(card(page, fill(m.wifi.radio_title, { band: m.bands['5g'] })).getByLabel(m.wifi.ssid, { exact: true })).toHaveValue('Home-WiFi-5G');
  });

  test.describe('with the bands merged', () => {
    test.beforeEach(async ({ page, router }) => {
      router.wifi.radios[1].main.ssid = router.wifi.radios[0].main.ssid;
      router.wifi.radios[1].main.key = router.wifi.radios[0].main.key;
      router.wifi.radios[1].main.encryption = router.wifi.radios[0].main.encryption;
      await page.reload();
    });

    test('sets the name and password once, for every band', async ({ page }, testInfo) => {
      const m = messages(testInfo);
      const bands = card(page, m.wifi.bands_title);
      await expect(bands.getByRole('switch', { name: m.wifi.bands_merge })).toBeChecked();
      await expect(bands.getByLabel(m.wifi.ssid, { exact: true })).toHaveValue('Home-WiFi');
      for (const band of ['2g', '5g'] as const) {
        const radio = card(page, fill(m.wifi.radio_title, { band: m.bands[band] }));
        await expect(radio.getByLabel(m.wifi.ssid, { exact: true })).toHaveCount(0);
        await expect(radio.getByText(fill(m.wifi.shared_hint, { ssid: 'Home-WiFi' }))).toBeVisible();
        await expect(radio.getByRole('button', { name: m.wifi.share })).toHaveCount(0);
      }
      await expect(bands.getByRole('button', { name: m.wifi.share })).toBeVisible();
      await expectPageQuality(page);
    });

    test('a new password goes to both bands and they stay merged', async ({ page, router }, testInfo) => {
      const m = messages(testInfo);
      const bands = card(page, m.wifi.bands_title);
      await bands.getByLabel(m.wifi.key, { exact: true }).fill('new-shared-pass');
      await bands.getByRole('button', { name: m.common.apply }).click();
      await page.getByRole('dialog', { name: m.wifi.reconnect_title }).getByRole('button', { name: m.common.apply }).click();
      await expect.poll(() => router.wifi.radios.map((r) => r.main.key)).toEqual(['new-shared-pass', 'new-shared-pass']);
      await expect(bands.getByRole('switch', { name: m.wifi.bands_merge })).toBeChecked();
      await expect(bands.getByLabel(m.wifi.key, { exact: true })).toHaveValue('new-shared-pass');
      await expect(bands.getByRole('button', { name: m.common.apply })).toBeDisabled();
    });

    test('band settings change without breaking the merge', async ({ page, router }, testInfo) => {
      const m = messages(testInfo);
      const five = card(page, fill(m.wifi.radio_title, { band: m.bands['5g'] }));
      await five.getByRole('button', { name: m.wifi.advanced }).click();
      await five.getByLabel(m.wifi.txpower, { exact: true }).selectOption('low');
      await five.getByRole('button', { name: m.common.apply }).click();
      await expect.poll(() => router.wifi.radios[1].txpower).toBe('low');
      expect(router.wifi.radios[1].main.ssid).toBe('Home-WiFi');
      await expect(card(page, m.wifi.bands_title).getByRole('switch', { name: m.wifi.bands_merge })).toBeChecked();
    });

    test('cancelling the split keeps the bands merged', async ({ page, router }, testInfo) => {
      const m = messages(testInfo);
      const toggle = card(page, m.wifi.bands_title).getByRole('switch', { name: m.wifi.bands_merge });
      await toggle.click();
      const confirm = page.getByRole('dialog', { name: m.wifi.reconnect_title });
      await confirm.getByRole('button', { name: m.common.cancel }).click();
      await expect(confirm).toBeHidden();
      await expect(toggle).toBeChecked();
      expect(router.calls.filter((c) => c.method === 'wifi_set')).toHaveLength(0);
    });
  });
});
