// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { Page } from '@playwright/test';
import { expect, expectPageQuality, loginAndWait, messages, otherMessages, projectLocale, test } from './helpers';

// Must match --color-bg in src/styles/tokens.css.
const BACKGROUND = { light: 'rgb(243, 244, 246)', dark: 'rgb(15, 17, 21)' };

const background = (page: Page) => page.evaluate(() => getComputedStyle(document.body).backgroundColor);

test.describe('appearance', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await loginAndWait(page, testInfo);
    await page.goto('./#/settings');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(messages(testInfo).settings.title);
  });

  test('settings page passes the quality checks', async ({ page }) => {
    await expectPageQuality(page);
  });

  test('follows the system color scheme by default', async ({ page }, testInfo) => {
    const scheme = testInfo.project.use.colorScheme as 'light' | 'dark';
    expect(await background(page)).toBe(BACKGROUND[scheme]);
    await expect(page.getByRole('radio', { name: messages(testInfo).settings.theme_system })).toBeChecked();
  });

  test('overrides the system theme and remembers it', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const scheme = testInfo.project.use.colorScheme as 'light' | 'dark';
    const opposite = scheme === 'light' ? 'dark' : 'light';
    const label = opposite === 'dark' ? m.settings.theme_dark : m.settings.theme_light;

    await page.getByRole('radio', { name: label }).check();
    expect(await background(page)).toBe(BACKGROUND[opposite]);
    await expectPageQuality(page);

    await page.reload();
    expect(await background(page)).toBe(BACKGROUND[opposite]);
    await expect(page.getByRole('radio', { name: label })).toBeChecked();

    await page.getByRole('radio', { name: m.settings.theme_system }).check();
    expect(await background(page)).toBe(BACKGROUND[scheme]);
  });

  test('switches language and remembers it', async ({ page }, testInfo) => {
    const other = otherMessages(testInfo);
    const otherLocale = projectLocale(testInfo) === 'en' ? 'zh-CN' : 'en';

    await page.getByRole('radio', { name: other.languages[otherLocale] }).check();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(other.settings.title);
    await expect(page.locator('html')).toHaveAttribute('lang', otherLocale);
    await expectPageQuality(page);

    await page.reload();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(other.settings.title);
  });

  test('can switch language from the login page too', async ({ page, context }, testInfo) => {
    await context.clearCookies();
    await page.evaluate(() => sessionStorage.clear());
    await page.reload();
    const other = otherMessages(testInfo);
    const otherLocale = projectLocale(testInfo) === 'en' ? 'zh-CN' : 'en';

    await page.getByRole('radio', { name: other.languages[otherLocale] }).check();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(other.login.title);
  });
});
