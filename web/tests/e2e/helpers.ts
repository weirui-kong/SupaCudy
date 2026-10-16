// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { expect, type Page, type TestInfo } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import en from '../../src/lib/i18n/en';
import zhCN from '../../src/lib/i18n/zh-CN';

export const PASSWORD = process.env.E2E_PASSWORD ?? 'supacudy-test';

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

export async function login(page: Page, testInfo: TestInfo, password = PASSWORD) {
  const m = messages(testInfo);
  await page.goto('./');
  await page.getByLabel(m.login.password, { exact: true }).fill(password);
  await page.getByRole('button', { name: m.login.submit, exact: true }).click();
}

export async function loginAndWait(page: Page, testInfo: TestInfo) {
  await login(page, testInfo);
  await expect(page.getByRole('heading', { level: 1, name: messages(testInfo).overview.title })).toBeVisible();
}

// The checks every page must pass in every viewport, theme and language.
export async function expectPageQuality(page: Page) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow, 'page scrolls horizontally').toBeLessThanOrEqual(0);

  const text = await page.locator('body').innerText();
  expect(text, 'a translation key is missing').not.toMatch(/⟦/);

  const { violations } = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)).toEqual([]);
}
