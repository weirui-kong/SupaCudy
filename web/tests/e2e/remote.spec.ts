// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

const card = (page: Page, title: string) => page.getByRole('region', { name: title, exact: true });

test.describe('remote access', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'remote', messages(testInfo).nav.remote);
  });

  test('turns Tailscale on and offers the sign-in link', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    await expect(page.getByRole('switch', { name: m.remote.enable })).not.toBeChecked();
    await expectPageQuality(page);
    await page.getByRole('switch', { name: m.remote.enable }).check();
    await expect.poll(() => router.tailscale.enabled).toBe(true);
    const link = page.getByRole('link', { name: m.remote.login });
    await expect(link).toHaveAttribute('href', 'https://login.tailscale.com/a/abc123');
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(page.getByText(m.remote.state_login)).toBeVisible();
    await expectPageQuality(page);
  });

  test('shows the connection once signed in and shares the network', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.tailscale, { enabled: true, signedIn: true });
    await page.reload();
    const main = card(page, m.remote.tailscale);
    await expect(main).toContainText(m.remote.state_running);
    await expect(main).toContainText('100.101.102.103');
    await expect(main).toContainText('example.ts.net');
    await expect(page.getByRole('link', { name: m.remote.login })).toHaveCount(0);
    await expect(card(page, m.remote.share_title)).toContainText(fill(m.remote.share_hint, { lan: '192.168.200.0/24' }));
    await page.getByRole('switch', { name: m.remote.share_lan }).check();
    await expect.poll(() => router.tailscale.share_lan).toBe(true);
    await expectPageQuality(page);
  });

  test('signs out after confirming', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.tailscale, { enabled: true, signedIn: true });
    await page.reload();
    await card(page, m.remote.share_title).getByRole('button', { name: m.remote.logout }).click();
    const confirm = page.getByRole('dialog', { name: m.remote.logout });
    await expect(confirm).toContainText(m.remote.logout_consequence);
    await confirm.getByRole('button', { name: m.remote.logout }).click();
    await expect.poll(() => router.tailscale.signedIn).toBe(false);
  });

  test('never links to a sign-in page outside Tailscale', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    Object.assign(router.tailscale, { enabled: true, loginUrl: 'https://evil.example/login' });
    await page.reload();
    await expect(page.getByText(m.remote.state_login)).toBeVisible();
    await expect(page.getByRole('link', { name: m.remote.login })).toHaveCount(0);
  });

  test('says so when Tailscale is not installed', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.tailscale.installed = false;
    await page.reload();
    await expect(page.getByText(m.remote.missing)).toBeVisible();
  });
});
