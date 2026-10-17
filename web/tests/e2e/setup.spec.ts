// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, expectPageQuality, fill, login, messages, PASSWORD, test } from './helpers';

test.describe('first-run setup', () => {
  test.use({ timezoneId: 'Europe/Berlin' });

  test('greets a fresh router and walks through every step', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.setup = { setup_done: false, password_set: false, default_password: false };
    await page.goto('./');

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.setup.welcome);
    await expect(page.getByLabel(m.login.password, { exact: true })).toHaveCount(0);
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.setup.start }).click();

    // Password: required on a fresh router.
    await expect(page.getByText(m.setup.password_required)).toBeVisible();
    await expect(page).toHaveTitle(`${m.setup.welcome} · ${m.app.name}`);
    await expect(page.getByRole('button', { name: m.setup.keep_password })).toHaveCount(0);
    await expect(page.getByRole('list', { name: fill(m.setup.progress, { step: 1, total: 4 }) })).toBeVisible();
    await expectPageQuality(page);
    await page.getByLabel(m.settings.password_new, { exact: true }).fill('owner-secret');
    await page.getByLabel(m.settings.password_confirm, { exact: true }).fill('owner-secret');
    await page.getByRole('button', { name: m.setup.next }).click();
    await expect.poll(() => router.password).toBe('owner-secret');

    // Wi-Fi: one network for every band.
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.setup.step_wifi);
    await expect(page.getByLabel(m.wifi.ssid, { exact: true })).toHaveValue('Home-WiFi');
    await page.getByLabel(m.wifi.ssid, { exact: true }).fill('Family');
    await page.getByLabel(m.wifi.key, { exact: true }).fill('family-key-1');
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.setup.next }).click();

    // Internet: already online over Ethernet.
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.setup.step_internet);
    await expect(page.getByRole('status').filter({ hasText: m.internet.online })).toBeVisible();
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.setup.next }).click();

    // Done: nothing is applied to Wi-Fi until the user confirms.
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.setup.step_done);
    await expect(page.getByText(fill(m.setup.summary_wifi, { ssid: 'Family' }))).toBeVisible();
    expect(router.calls.some((c) => c.method === 'wifi_set')).toBe(false);
    await expect(page.getByLabel(m.settings.timezone, { exact: true })).toHaveValue('Europe/Berlin');
    await page.getByRole('button', { name: m.setup.finish }).click();
    const confirm = page.getByRole('dialog', { name: m.setup.finish });
    await expect(confirm).toContainText(fill(m.setup.wifi_reconnect, { ssid: 'Family' }));
    await expectPageQuality(page);
    await confirm.getByRole('button', { name: m.setup.finish }).click();

    await expect(page.getByRole('navigation', { name: m.nav.main }).filter({ visible: true })).toBeVisible();
    expect(router.setup.setup_done).toBe(true);
    for (const radio of router.wifi.radios) expect(radio.main).toMatchObject({ ssid: 'Family', key: 'family-key-1', enabled: true });
    expect(router.time.zonename).toBe('Europe/Berlin');
    // The mock clock is days off, so the browser clock is copied too.
    expect(Math.abs(router.time.time - Date.now() / 1000)).toBeLessThan(30);
  });

  test('shows the factory login and has it replaced everywhere', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.setup = { setup_done: false, password_set: true, default_password: true };
    await page.goto('./');

    await expect(page.getByText(fill(m.setup.default_hint, { password: 'supacudy' }))).toBeVisible();
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.setup.start }).click();

    await expect(page.getByText(m.setup.password_required)).toBeVisible();
    await expect(page.getByRole('button', { name: m.setup.keep_password })).toHaveCount(0);
    await page.getByLabel(m.settings.password_new, { exact: true }).fill('supacudy');
    await expect(page.getByText(m.settings.password_default)).toBeVisible();
    await page.getByLabel(m.settings.password_new, { exact: true }).fill('owner-secret');
    await page.getByLabel(m.settings.password_confirm, { exact: true }).fill('owner-secret');
    await page.getByRole('button', { name: m.setup.next }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.setup.step_wifi);
    expect(router.password).toBe('owner-secret');
    // AdGuard Home gets the same password, as a bcrypt hash.
    const { compare } = await import('bcryptjs');
    expect(await compare('owner-secret', router.adguard.webHash!)).toBe(true);
    expect(router.adguard.web.synced).toBe(true);
  });

  test('does not show the factory password once setup is done', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.setup = { setup_done: true, password_set: true, default_password: false };
    await page.goto('./');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title);
    await expect(page.getByText(fill(m.setup.default_hint, { password: 'supacudy' }))).toHaveCount(0);
  });

  test('lets an owner with a password keep it and skip unchanged Wi-Fi', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.setup = { setup_done: false, password_set: true, default_password: false };
    await login(page, testInfo);

    await expect(page.getByText(m.setup.password_optional)).toBeVisible();
    await page.getByRole('button', { name: m.setup.keep_password }).click();
    await page.getByRole('button', { name: m.setup.next }).click();
    await page.getByRole('button', { name: m.setup.next }).click();
    await expect(page.getByText(m.setup.summary_password_kept)).toBeVisible();
    await expect(page.getByText(fill(m.setup.wifi_reconnect, { ssid: 'Home-WiFi' })).filter({ visible: true })).toHaveCount(0);
    await page.getByLabel(m.settings.timezone, { exact: true }).selectOption('UTC');
    await page.getByRole('button', { name: m.setup.finish }).click();

    await expect(page.getByRole('navigation', { name: m.nav.main }).filter({ visible: true })).toBeVisible();
    expect(router.password).toBe(PASSWORD);
    expect(router.calls.some((c) => ['wifi_set', 'password_set', 'time_set'].includes(c.method))).toBe(false);
    expect(router.setup.setup_done).toBe(true);
  });

  test('blocks steps with invalid input and keeps answers when going back', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.setup = { setup_done: false, password_set: true, default_password: false };
    await login(page, testInfo);

    await page.getByLabel(m.settings.password_new, { exact: true }).fill('short');
    await expect(page.getByText(fill(m.settings.password_too_short, { min: 8 }))).toBeVisible();
    await expect(page.getByRole('button', { name: m.setup.next })).toBeDisabled();
    await page.getByRole('button', { name: m.setup.keep_password }).click();

    await page.getByLabel(m.wifi.key, { exact: true }).fill('short');
    await expect(page.getByText(m.wifi.key_too_short)).toBeVisible();
    await expect(page.getByRole('button', { name: m.setup.next })).toBeDisabled();
    await page.getByLabel(m.wifi.key, { exact: true }).fill('long-enough-key');
    await page.getByRole('button', { name: m.setup.next }).click();
    await page.getByRole('button', { name: m.internet.back }).click();
    await expect(page.getByLabel(m.wifi.key, { exact: true })).toHaveValue('long-enough-key');
  });

  test('an offline router can still finish setup', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.setup = { setup_done: false, password_set: true, default_password: false };
    router.wan.carrier = false;
    await login(page, testInfo);
    await page.getByRole('button', { name: m.setup.keep_password }).click();
    await page.getByRole('button', { name: m.setup.next }).click();
    await expect(page.getByRole('status').filter({ hasText: m.internet.offline })).toBeVisible();
    await page.getByRole('button', { name: m.setup.skip }).click();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.setup.step_done);
  });

  test('a router that finished setup goes straight to the overview', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await login(page, testInfo);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.overview.title);
    expect(router.calls.some((c) => c.method === 'setup_complete')).toBe(false);
  });
});
