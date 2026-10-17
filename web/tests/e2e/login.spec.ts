// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { PASSWORD, expect, expectPageQuality, login, loginAndWait, messages, projectLocale, test } from './helpers';

test.describe('login', () => {
  test('is shown in the browser language and passes the quality checks', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.goto('./');

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title);
    await expect(page.locator('html')).toHaveAttribute('lang', projectLocale(testInfo));
    await expectPageQuality(page);
  });

  test('rejects a wrong password with a clear message', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await login(page, testInfo, 'definitely-wrong');

    await expect(page.getByRole('alert')).toContainText(m.login.wrong_password);
    await expect(page.getByLabel(m.login.password, { exact: true })).toHaveAttribute('aria-invalid', 'true');
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title);
    await expectPageQuality(page);
  });

  test('rejects an empty password', async ({ page }, testInfo) => {
    await login(page, testInfo, '');
    await expect(page.getByRole('alert')).toContainText(messages(testInfo).login.wrong_password);
  });

  test('opens the overview after a correct password', async ({ page }, testInfo) => {
    await loginAndWait(page, testInfo);
    await expect(page).toHaveTitle(`${messages(testInfo).overview.title} · SupaCudy`);
  });

  test('keeps the session across a reload but not in localStorage', async ({ page }, testInfo) => {
    await loginAndWait(page, testInfo);
    await page.reload();

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(messages(testInfo).overview.title);
    expect(await page.evaluate(() => Object.keys(localStorage).filter((k) => /session/i.test(k)))).toEqual([]);
  });

  test('never puts the password or session in the URL', async ({ page }, testInfo) => {
    const urls: string[] = [];
    page.on('request', (request) => urls.push(request.url()));
    await loginAndWait(page, testInfo);

    const session = await page.evaluate(() => sessionStorage.getItem('supacudy.session'));
    for (const url of urls) {
      expect(url).not.toContain(PASSWORD);
      expect(url).not.toContain(session!);
    }
  });

  test('logs out and stays logged out after a reload', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await loginAndWait(page, testInfo);
    await page.goto('./#/settings');
    await page.getByRole('main').getByRole('button', { name: m.nav.logout }).click();

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title);
    await page.reload();
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title);
  });

  test('sends the user back to login with an explanation when the session expires', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await loginAndWait(page, testInfo);
    await page.evaluate(() => sessionStorage.setItem('supacudy.session', 'f'.repeat(32)));
    await page.reload();

    await expect(page.getByRole('heading', { level: 1 })).toHaveText(m.login.title);
    await expect(page.getByRole('status')).toContainText(m.errors.denied);
  });
});
