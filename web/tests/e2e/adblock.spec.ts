// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, PASSWORD, test } from './helpers';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

test.describe('ad blocking', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'adblock', messages(testInfo).nav.adblock);
  });

  test('is on by default, with statistics and the query log off', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await expect(page.getByRole('switch', { name: m.adblock.enable })).toBeChecked();
    const stats = card(page, m.adblock.stats);
    await expect(stats.getByRole('switch', { name: m.adblock.keep_stats })).not.toBeChecked();
    await expect(stats.getByRole('switch', { name: m.adblock.keep_querylog })).not.toBeChecked();
    await expect(stats.getByText(m.adblock.stats_off)).toBeVisible();
    await expect(stats).not.toContainText('ads.example.com');
    await expectPageQuality(page);
  });

  test('turns statistics and the query log on separately and shows what AdGuard Home reports', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const stats = card(page, m.adblock.stats);
    await stats.getByRole('switch', { name: m.adblock.keep_stats }).check();
    await expect(stats.getByRole('switch', { name: m.adblock.keep_stats })).toBeChecked();
    expect(router.adguard.logging).toEqual({ statistics: true, querylog: false });
    await expect(stats).toContainText('ads.example.com');
    const nf = new Intl.NumberFormat(testInfo.project.use.locale);
    await expect(stats).toContainText(fill(m.adblock.blocked_value, { count: nf.format(1234), pct: 10 }));
    await expect(page.getByText(fill(m.adblock.rules_count, { count: nf.format(185651) }))).toBeVisible();
    await expectPageQuality(page);

    await stats.getByRole('switch', { name: m.adblock.keep_querylog }).check();
    await expect.poll(() => router.adguard.logging).toEqual({ statistics: true, querylog: true });
    await stats.getByRole('switch', { name: m.adblock.keep_stats }).uncheck();
    await expect.poll(() => router.adguard.logging).toEqual({ statistics: false, querylog: true });
    await expect(stats.getByText(m.adblock.stats_off)).toBeVisible();
  });

  test('shows a list added on the AdGuard Home page', async ({ page, router }) => {
    router.adguard.filters.push({ name: 'Added natively', url: 'https://lists.example/native.txt', enabled: false, rules: null });
    await page.reload();
    await expect(page.getByRole('switch', { name: 'Added natively' })).not.toBeChecked();
    await page.getByRole('switch', { name: 'Added natively' }).check();
    await expect.poll(() => router.adguard.filters[1].enabled).toBe(true);
  });

  test('adds, removes and suggests lists', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('switch', { name: 'AdAway Default Blocklist' }).check();
    await expect.poll(() => router.adguard.filters.map((f) => f.name)).toEqual(['AdGuard DNS filter', 'AdAway Default Blocklist']);
    await expect(page.getByRole('button', { name: fill(m.common.delete_named, { name: 'AdAway Default Blocklist' }) })).toBeVisible();

    const field = page.getByLabel(m.adblock.add_list);
    await field.fill('ftp://lists.example/x');
    await expect(page.getByText(fill(m.adblock.url_bad, { value: 'ftp://lists.example/x' }))).toBeVisible();
    await expect(page.getByRole('button', { name: m.adblock.add, exact: true })).toBeDisabled();
    await field.fill('https://lists.example/block.txt');
    await expectPageQuality(page);
    await page.getByRole('button', { name: m.adblock.add, exact: true }).click();
    await expect.poll(() => router.adguard.filters.at(-1)?.url).toBe('https://lists.example/block.txt');
    expect(router.adguard.filters.at(-1)?.name).toBe('lists.example');
    await expect(field).toHaveValue('');

    await page.getByRole('button', { name: fill(m.common.delete_named, { name: 'AdGuard DNS filter' }) }).click();
    await expect.poll(() => router.adguard.filters.some((f) => f.name === 'AdGuard DNS filter')).toBe(false);
    await expect(page.getByRole('switch', { name: 'AdGuard DNS filter' })).not.toBeChecked();
  });

  test('says why a list could not be added', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.getByLabel(m.adblock.add_list).fill('https://unreachable.example/list.txt');
    await page.getByRole('button', { name: m.adblock.add, exact: true }).click();
    await expect(page.getByText(m.errors.reasons.adguard_refused)).toBeVisible();
    await expect(page.getByLabel(m.adblock.add_list)).toHaveValue('https://unreachable.example/list.txt');
  });

  test('saves custom rules and rejects malformed ones', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const rules = card(page, m.adblock.rules);
    await expect(rules.getByRole('button', { name: m.common.apply })).toBeDisabled();
    await rules.getByLabel(m.adblock.rules).fill('||ads.test^\n\n@@||ok.example^');
    await rules.getByRole('button', { name: m.common.apply }).click();
    await expect.poll(() => router.adguard.rules).toEqual(['||ads.test^', '@@||ok.example^']);
    await expect(rules.getByLabel(m.adblock.rules)).toHaveValue('||ads.test^\n@@||ok.example^');
  });

  test('keeps the switches as they are when AdGuard Home refuses', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.failNext('adguard_logging_set', { status: 0, data: { error: 'adguard_refused' } });
    const stats = card(page, m.adblock.stats);
    await stats.getByRole('switch', { name: m.adblock.keep_querylog }).click();
    await expect(page.getByRole('alert')).toContainText(m.errors.reasons.adguard_refused);
    await expect(stats.getByRole('switch', { name: m.adblock.keep_querylog })).not.toBeChecked();
    expect(router.adguard.logging).toEqual({ statistics: false, querylog: false });
  });

  test('pauses blocking', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('switch', { name: m.adblock.protection }).uncheck();
    await expect.poll(() => router.adguard.protection).toBe(false);
  });

  test('shows nothing it cannot read from AdGuard Home', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.adguard.locked = true;
    await page.reload();
    await expect(page.getByText(m.adblock.locked)).toBeVisible();
    await expect(page.getByRole('switch', { name: m.adblock.protection })).toHaveCount(0);
    await expect(card(page, m.adblock.lists)).toHaveCount(0);
    await expect(card(page, m.adblock.stats)).toHaveCount(0);
  });

  test('opens the AdGuard Home page with the admin password', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    const web = card(page, m.adblock.web_title);
    await web.getByRole('button', { name: m.adblock.web_on }).click();
    const dialog = page.getByRole('dialog', { name: m.adblock.web_title });
    await expect(dialog.getByLabel(m.adblock.web_user)).toHaveValue('root');
    await dialog.getByLabel(m.adblock.web_password, { exact: true }).fill('not-the-password');
    await dialog.getByRole('button', { name: m.common.continue }).click();
    await expect(dialog.getByText(m.login.wrong_password)).toBeVisible();
    expect(router.adguard.web.enabled).toBe(false);
    await dialog.getByLabel(m.adblock.web_password, { exact: true }).fill(PASSWORD);
    await expectPageQuality(page);
    await dialog.getByRole('button', { name: m.common.continue }).click();
    await expect.poll(() => router.adguard.web.enabled).toBe(true);
    const { compare } = await import('bcryptjs');
    expect(await compare(PASSWORD, router.adguard.webHash!)).toBe(true);
    await expect(dialog).toBeHidden();

    await page.reload();
    await expect(card(page, m.adblock.web_title)).toContainText(m.adblock.web_password_same);
    const link = card(page, m.adblock.web_title).getByRole('link', { name: m.adblock.web_open });
    await expect(link).toHaveAttribute('href', /^http:\/\/[^/]+:3000\/$/);
    await expect(link).toHaveAttribute('target', '_blank');

    await card(page, m.adblock.web_title).getByRole('button', { name: m.adblock.web_off }).click();
    const confirm = page.getByRole('dialog', { name: m.adblock.web_off });
    await expect(confirm).toContainText(m.adblock.web_off_consequence);
    await confirm.getByRole('button', { name: m.adblock.web_off }).click();
    await expect.poll(() => router.adguard.web.enabled).toBe(false);

    // AdGuard Home already has the password now, so it is not asked again.
    await card(page, m.adblock.web_title).getByRole('button', { name: m.adblock.web_on }).click();
    await expect.poll(() => router.adguard.web.enabled).toBe(true);
    await expect(page.getByRole('dialog', { name: m.adblock.web_title })).toBeHidden();
  });

  test('asks for the admin password after it was changed outside SupaCudy', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.adguard.web = { enabled: true, user: 'root', port: 3000, synced: false };
    await page.reload();
    const web = card(page, m.adblock.web_title);
    await expect(web.getByText(m.adblock.web_unsynced)).toBeVisible();
    await web.getByRole('button', { name: m.adblock.web_sync }).click();
    const dialog = page.getByRole('dialog', { name: m.adblock.web_title });
    await dialog.getByLabel(m.adblock.web_password, { exact: true }).fill(PASSWORD);
    await dialog.getByRole('button', { name: m.common.continue }).click();
    await expect.poll(() => router.adguard.web.synced).toBe(true);
    await expect(web.getByText(m.adblock.web_unsynced)).toHaveCount(0);
  });

  test('warns before turning AdGuard Home off', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    // The switch stays on until the user confirms.
    await page.getByRole('switch', { name: m.adblock.enable }).click();
    const confirm = page.getByRole('dialog', { name: m.adblock.disable_title });
    await expect(confirm).toContainText(m.adblock.disable_consequence);
    await expect(page.getByRole('switch', { name: m.adblock.enable })).toBeChecked();
    await confirm.getByRole('button', { name: m.adblock.disable }).click();
    await expect.poll(() => router.adguard.enabled).toBe(false);
  });

  test('says so when AdGuard Home is not installed', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.adguard.installed = false;
    await page.reload();
    await expect(page.getByText(m.adblock.missing)).toBeVisible();
  });

  test('explains the DNS fallback while AdGuard Home is down', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.adguard.fallback = true;
    await page.reload();
    await expect(page.getByText(m.adblock.fallback)).toBeVisible();
    await expect(page.getByText(m.adblock.not_running)).toHaveCount(0);
  });
});
