// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { test as base, expect, type Page, type TestInfo } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import en from '../../src/lib/i18n/en';
import zhCN from '../../src/lib/i18n/zh-CN';
import { MockRouter, PASSWORD } from './mock/router';

export { expect, PASSWORD };

// Every test gets its own mock router answering /ubus.
export const test = base.extend<{ router: MockRouter }>({
  router: [
    async ({ page }, use) => {
      const router = new MockRouter();
      await page.route('**/ubus', (route) => router.handle(route));
      await page.route('**/cgi-bin/cgi-upload', (route) => router.handleUpload(route));
      await page.route('**/cgi-bin/supacudy-login', (route) => router.handleLogin(route));
      await page.route('**/cgi-bin/supacudy-whoami', (route) =>
        route.fulfill({ contentType: 'application/json', body: JSON.stringify({ ip: router.callerIp }) }),
      );
      await use(router);
    },
    { auto: true },
  ],
});

export type Locale = 'en' | 'zh-CN';

export function projectLocale(testInfo: TestInfo): Locale {
  return testInfo.project.use.locale === 'zh-CN' ? 'zh-CN' : 'en';
}

export function messages(testInfo: TestInfo) {
  return projectLocale(testInfo) === 'zh-CN' ? zhCN : en;
}

export function otherMessages(testInfo: TestInfo) {
  return projectLocale(testInfo) === 'zh-CN' ? en : zhCN;
}

export function isMobile(testInfo: TestInfo): boolean {
  return testInfo.project.name.startsWith('mobile');
}

export function fill(template: string, params: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (match, name: string) => (name in params ? String(params[name]) : match));
}

export async function login(page: Page, testInfo: TestInfo, password = PASSWORD, path = './') {
  const m = messages(testInfo);
  await page.goto(path);
  await page.getByLabel(m.login.password, { exact: true }).fill(password);
  await page.getByRole('button', { name: m.login.submit, exact: true }).click();
}

export async function loginAndWait(page: Page, testInfo: TestInfo, path = './') {
  await login(page, testInfo, PASSWORD, path);
  await expect(page.getByRole('navigation', { name: messages(testInfo).nav.main }).filter({ visible: true })).toBeVisible();
}

export async function openPage(page: Page, testInfo: TestInfo, route: string, title: string) {
  await loginAndWait(page, testInfo, `./#/${route}`);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(title);
}

// The checks every page and dialog must pass in every viewport, theme and language.
export async function expectPageQuality(page: Page) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow, 'page scrolls horizontally').toBeLessThanOrEqual(0);

  const text = await page.locator('body').innerText();
  expect(text, 'a translation key is missing').not.toMatch(/⟦/);

  const { violations } = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)).toEqual([]);
}
