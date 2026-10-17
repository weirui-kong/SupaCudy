// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, PASSWORD, test } from './helpers';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

test.describe('settings: time', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'settings', messages(testInfo).nav.settings);
  });

  test('shows the router clock and changes the time zone', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const time = card(page, m.settings.time);
    await expect(time.getByLabel(m.settings.timezone, { exact: true })).toHaveValue('UTC');
    await expect(time).toContainText('2026');
    await expectPageQuality(page);

    await time.getByLabel(m.settings.timezone, { exact: true }).selectOption('Asia/Shanghai');
    await time.getByRole('switch', { name: m.settings.ntp }).uncheck();
    await time.getByRole('button', { name: m.common.apply }).click();
    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.time).toMatchObject({ zonename: 'Asia/Shanghai', ntp: false });
    expect(router.calls.find((c) => c.method === 'time_set')?.args).toMatchObject({ time: 0 });
  });

  test('warns about a wrong clock and copies the browser clock', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const time = card(page, m.settings.time);
    await expect(time.getByText(m.settings.clock_drift)).toBeVisible();
    await time.getByRole('button', { name: m.settings.sync_clock }).click();
    await expect(time.getByText(m.settings.clock_drift)).toBeHidden();
    expect(Math.abs(router.time.time - Date.now() / 1000)).toBeLessThan(30);
  });

  test.describe('in another time zone', () => {
    test.use({ timezoneId: 'Europe/Berlin' });

    test('offers the browser time zone', async ({ page }, testInfo) => {
      const m = messages(testInfo);
      const time = card(page, m.settings.time);
      await time.getByRole('button', { name: fill(m.settings.use_browser_zone, { zone: 'Europe/Berlin' }) }).click();
      await expect(time.getByLabel(m.settings.timezone, { exact: true })).toHaveValue('Europe/Berlin');
      await expect(time.getByRole('button', { name: m.common.apply })).toBeEnabled();
    });
  });
});

test.describe('settings: admin password', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'settings', messages(testInfo).nav.settings);
  });

  test('changes the password after checking the current one', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const pw = card(page, m.settings.password);
    await pw.getByLabel(m.settings.password_current, { exact: true }).fill(PASSWORD);
    await pw.getByLabel(m.settings.password_new, { exact: true }).fill('a-new-secret');
    await pw.getByLabel(m.settings.password_confirm, { exact: true }).fill('a-new-secret');
    await expectPageQuality(page);
    await pw.getByRole('button', { name: m.settings.password_change }).click();

    await expect(page.getByRole('status').filter({ hasText: m.settings.password_changed })).toBeVisible();
    expect(router.password).toBe('a-new-secret');
    await expect(pw.getByLabel(m.settings.password_new, { exact: true })).toHaveValue('');
    // The current session survives the change.
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.nav.settings);
  });

  test('refuses a wrong current password without changing anything', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const pw = card(page, m.settings.password);
    await pw.getByLabel(m.settings.password_current, { exact: true }).fill('not-the-password');
    await pw.getByLabel(m.settings.password_new, { exact: true }).fill('a-new-secret');
    await pw.getByLabel(m.settings.password_confirm, { exact: true }).fill('a-new-secret');
    await pw.getByRole('button', { name: m.settings.password_change }).click();

    await expect(pw.getByText(m.errors.reasons.wrong_password)).toBeVisible();
    expect(router.password).toBe(PASSWORD);
    expect(router.calls.some((c) => c.method === 'password_set')).toBe(false);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.nav.settings);
  });

  test('validates the new password as the user types', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const pw = card(page, m.settings.password);
    const button = pw.getByRole('button', { name: m.settings.password_change });
    await pw.getByLabel(m.settings.password_current, { exact: true }).fill(PASSWORD);
    await pw.getByLabel(m.settings.password_new, { exact: true }).fill('short');
    await expect(pw.getByText(fill(m.settings.password_too_short, { min: 8 }))).toBeVisible();
    await pw.getByLabel(m.settings.password_new, { exact: true }).fill(PASSWORD);
    await expect(pw.getByText(m.settings.password_same)).toBeVisible();
    await pw.getByLabel(m.settings.password_new, { exact: true }).fill('a-new-secret');
    await pw.getByLabel(m.settings.password_confirm, { exact: true }).fill('a-new-secreT');
    await expect(pw.getByText(m.settings.password_mismatch)).toBeVisible();
    await expect(button).toBeDisabled();
    expect(router.calls.some((c) => c.method === 'password_set')).toBe(false);
  });
});

test.describe('settings: access from the WAN', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'settings', messages(testInfo).nav.settings);
  });

  test('shows the web UI open and SSH closed by default', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const wan = card(page, m.settings.wan_access);
    await expect(wan.getByRole('switch', { name: m.settings.wan_webui })).toBeChecked();
    await expect(wan.getByRole('switch', { name: m.settings.wan_ssh })).not.toBeChecked();
    await expect(wan.getByText(m.settings.wan_exposed)).toBeVisible();
    await expectPageQuality(page);
  });

  test('switches SSH and the web UI independently', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const wan = card(page, m.settings.wan_access);
    await wan.getByRole('switch', { name: m.settings.wan_ssh }).check();
    await expect(page.getByRole('status').filter({ hasText: m.common.applied })).toBeVisible();
    expect(router.wanAccess).toEqual({ webui: true, ssh: true });

    await wan.getByRole('switch', { name: m.settings.wan_webui }).uncheck();
    await expect.poll(() => router.wanAccess).toEqual({ webui: false, ssh: true });
    await wan.getByRole('switch', { name: m.settings.wan_ssh }).uncheck();
    await expect.poll(() => router.wanAccess).toEqual({ webui: false, ssh: false });
    await expect(wan.getByText(m.settings.wan_exposed)).toBeHidden();
  });

  test('a refused change puts the switch back', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.failNext('wan_access_set', { status: 0, data: { error: 'something_new' } });
    const wan = card(page, m.settings.wan_access);
    await wan.getByRole('switch', { name: m.settings.wan_ssh }).click();
    await expect(wan.getByRole('switch', { name: m.settings.wan_ssh })).not.toBeChecked();
    expect(router.wanAccess).toEqual({ webui: true, ssh: false });
  });
});

test.describe('maintenance', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await page.clock.install();
    await openPage(page, testInfo, 'maintenance', messages(testInfo).nav.maintenance);
  });

  const firmwareFile = { name: 'supacudy-sysupgrade.bin', mimeType: 'application/octet-stream', buffer: Buffer.alloc(64 * 1024, 7) };

  async function chooseFirmware(page: Page, label: string) {
    const chooser = page.waitForEvent('filechooser');
    await page.getByRole('button', { name: label }).click();
    await (await chooser).setFiles(firmwareFile);
  }

  test('shows the installed version and passes the quality checks', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await card(page, m.maintenance.advanced).getByRole('button', { name: m.maintenance.open_luci }).click();
    const warning = page.getByRole('dialog', { name: m.luci.title });
    await expect(warning).toContainText(m.luci.consequence);
    await warning.getByRole('button', { name: m.common.cancel }).click();
    await expect(card(page, m.maintenance.firmware)).toContainText('0.3.0-r1');
    await expect(card(page, m.maintenance.firmware)).toContainText('24.10.8');
    await expectPageQuality(page);
  });

  test('uploads, checks and installs firmware keeping the settings', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await chooseFirmware(page, m.maintenance.choose_file);
    const fw = card(page, m.maintenance.firmware);
    await expect(fw.getByText(m.maintenance.firmware_valid)).toBeVisible();
    await expect(fw).toContainText(firmwareFile.name);
    await expect(fw.getByRole('switch', { name: m.maintenance.keep_settings })).toBeChecked();
    await expectPageQuality(page);
    await fw.getByRole('button', { name: m.maintenance.upgrade }).click();

    const confirm = page.getByRole('dialog', { name: m.maintenance.upgrade });
    await expect(confirm).toContainText(fill(m.maintenance.upgrade_confirm, { name: firmwareFile.name }));
    await expect(confirm).toContainText(m.maintenance.upgrade_keep);
    await confirm.getByRole('button', { name: m.maintenance.upgrade }).click();

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.restart.title_upgrade);
    await expect(page.getByText(m.restart.keep_power)).toBeVisible();
    expect(router.restarts).toEqual(['upgrade-keep']);
    await expectPageQuality(page);
  });

  test('warns that installing without keeping settings erases them', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await chooseFirmware(page, m.maintenance.choose_file);
    const fw = card(page, m.maintenance.firmware);
    await fw.getByRole('switch', { name: m.maintenance.keep_settings }).uncheck();
    await fw.getByRole('button', { name: m.maintenance.upgrade }).click();
    const confirm = page.getByRole('dialog', { name: m.maintenance.upgrade });
    await expect(confirm).toContainText(m.maintenance.upgrade_erase);
    await confirm.getByRole('button', { name: m.common.cancel }).click();
    await expect(confirm).toBeHidden();
    expect(router.restarts).toEqual([]);
  });

  test('refuses a file that is not firmware for this router', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.nextFirmwareValid = false;
    await chooseFirmware(page, m.maintenance.choose_file);
    const fw = card(page, m.maintenance.firmware);
    await expect(fw.getByText(m.maintenance.firmware_invalid)).toBeVisible();
    await expect(fw.getByRole('button', { name: m.maintenance.upgrade })).toHaveCount(0);
    await fw.getByRole('button', { name: m.maintenance.choose_other }).click();
    await expect(fw.getByRole('button', { name: m.maintenance.choose_file })).toBeVisible();
    expect(router.firmware).toBeNull();
  });

  test('sends the user to log in when the upload is refused', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.sessions.clear();
    await chooseFirmware(page, m.maintenance.choose_file);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title);
    expect(router.firmware).toBeNull();
  });

  test('reboots after confirming and waits until the router is back', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await card(page, m.maintenance.reboot).getByRole('button', { name: m.maintenance.reboot }).click();
    const confirm = page.getByRole('dialog', { name: m.maintenance.reboot });
    await expect(confirm).toContainText(m.maintenance.reboot_consequence);
    await expectPageQuality(page);
    await confirm.getByRole('button', { name: m.maintenance.reboot }).click();

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.restart.title_reboot);
    expect(router.restarts).toEqual(['reboot']);
    await page.clock.fastForward(30_000);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.restart.back);
    await page.getByRole('button', { name: m.login.submit }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title);
  });

  test('factory reset states the consequences and explains how to reconnect', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await card(page, m.maintenance.reset).getByRole('button', { name: m.maintenance.reset }).click();
    const confirm = page.getByRole('dialog', { name: m.maintenance.reset });
    await expect(confirm).toContainText(m.maintenance.reset_consequence);
    await confirm.getByRole('button', { name: m.maintenance.reset }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.restart.title_reset);
    await expect(page.getByText(m.restart.reconnect)).toBeVisible();
    expect(router.restarts).toEqual(['reset']);
  });

  test('a failed reboot request keeps the page and says why', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.failNext('reboot', { status: 7 });
    await card(page, m.maintenance.reboot).getByRole('button', { name: m.maintenance.reboot }).click();
    await page.getByRole('dialog', { name: m.maintenance.reboot }).getByRole('button', { name: m.maintenance.reboot }).click();
    await expect(page.getByRole('alert')).toContainText(fill(m.errors.unknown, { code: 7 }));
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.nav.maintenance);
  });

  test('switches flow offloading', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const accel = page.getByRole('region', { name: m.maintenance.acceleration, exact: true });
    await accel.getByRole('radio', { name: m.maintenance.offload_hardware }).check();
    await expect.poll(() => router.offload).toBe('hardware');
    await expect(accel.getByText(m.maintenance.offload_note)).toBeVisible();
  });

  test('limits the CPU, 80% out of the box', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const cpu = page.getByRole('region', { name: m.maintenance.cpu_limit, exact: true });
    await expect(cpu.getByRole('radio', { name: '80%' })).toBeChecked();
    await expectPageQuality(page);
    await cpu.getByRole('radio', { name: '30%' }).check();
    await expect.poll(() => router.cpuLimit).toBe(30);
    await cpu.getByRole('radio', { name: '100%' }).check();
    await expect.poll(() => router.cpuLimit).toBe(100);
  });

  test('keeps the CPU limit when the router refuses a change', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.failNext('cpu_limit_set', { status: 0, data: { error: 'something_new' } });
    const cpu = page.getByRole('region', { name: m.maintenance.cpu_limit, exact: true });
    // Clicked, not checked: it goes back to 80% as soon as the router refuses.
    await cpu.getByRole('radio', { name: '50%' }).click();
    await expect(page.getByRole('alert')).toBeVisible();
    await expect(cpu.getByRole('radio', { name: '80%' })).toBeChecked();
    expect(router.cpuLimit).toBe(80);
  });
});
