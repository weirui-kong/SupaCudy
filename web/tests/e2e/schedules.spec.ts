// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

test.describe('schedules', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'schedules', messages(testInfo).nav.schedules);
  });

  test('keeps a device offline at bedtime on school nights', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.schedules.add_parental }).click();
    const dialog = page.getByRole('dialog', { name: m.schedules.add_parental });
    await expect(dialog.getByLabel(m.vpn.name, { exact: true })).toHaveValue(m.schedules.bedtime);
    await expect(dialog.getByRole('button', { name: m.common.save })).toBeDisabled();
    await dialog.getByRole('switch', { name: 'Pixel-Phone' }).check();
    for (const d of ['sat', 'sun'] as const) await dialog.getByRole('button', { name: m.days[`long_${d}`] }).click();
    await dialog.getByLabel(m.schedules.offline_from, { exact: true }).fill('21:30');
    await dialog.getByLabel(m.schedules.offline_until, { exact: true }).fill('06:45');
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.save }).click();
    await expect(dialog).toBeHidden();
    expect(router.schedules.parental[0]).toMatchObject({
      name: m.schedules.bedtime, macs: ['6a:00:00:00:02:00'], days: ['mon', 'tue', 'wed', 'thu', 'fri'], start: '21:30', end: '06:45', enabled: true,
    });
    await expect(card(page, m.schedules.parental_title)).toContainText('21:30–06:45');
  });

  test('refuses a window that starts and ends at the same time', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.schedules.add_parental }).click();
    const dialog = page.getByRole('dialog', { name: m.schedules.add_parental });
    await dialog.getByRole('switch', { name: 'Work-Laptop' }).check();
    await dialog.getByLabel(m.schedules.offline_from, { exact: true }).fill('07:00');
    await dialog.getByLabel(m.schedules.offline_until, { exact: true }).fill('07:00');
    await expect(dialog.getByText(m.schedules.end_invalid)).toBeVisible();
    await expect(dialog.getByRole('button', { name: m.common.save })).toBeDisabled();
  });

  test('deletes a time limit', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.schedules.parental.push({ id: 'sc_parental_1', name: 'Homework', macs: ['02:5c:00:00:00:11'], days: ['mon'], start: '16:00', end: '18:00', enabled: true });
    await page.reload();
    await page.getByRole('button', { name: fill(m.common.delete_named, { name: 'Homework' }) }).click();
    await expect.poll(() => router.schedules.parental.length).toBe(0);
  });

  test('turns Wi-Fi off at night on weekdays', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const wifi = card(page, m.schedules.wifi_off_title);
    await wifi.getByRole('switch', { name: m.schedules.wifi_off_enable }).check();
    await expect(wifi.getByText(m.schedules.wifi_off_note)).toBeVisible();
    for (const d of ['sat', 'sun'] as const) await wifi.getByRole('button', { name: m.days[`long_${d}`] }).click();
    await wifi.getByLabel(m.schedules.off_at, { exact: true }).fill('00:30');
    await wifi.getByLabel(m.schedules.on_at, { exact: true }).fill('06:00');
    await expectPageQuality(page);
    await wifi.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.schedules.wifi_off).toEqual({ enabled: true, days: ['mon', 'tue', 'wed', 'thu', 'fri'], start: '00:30', end: '06:00' });
  });

  test('needs at least one day', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const reboot = card(page, m.schedules.reboot_title);
    await reboot.getByRole('switch', { name: m.schedules.reboot_enable }).check();
    for (const d of ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const) await reboot.getByRole('button', { name: m.days[`long_${d}`] }).click();
    await expect(reboot.getByText(m.schedules.days_required)).toBeVisible();
    await expect(reboot.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await reboot.getByRole('button', { name: m.days.long_sun }).click();
    await reboot.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.schedules.reboot).toMatchObject({ enabled: true, days: ['sun'], start: '04:00' });
  });
});
