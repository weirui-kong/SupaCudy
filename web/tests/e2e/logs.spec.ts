// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { readFile } from 'node:fs/promises';
import { expect, expectPageQuality, fill, messages, openPage, test } from './helpers';

test.describe('logs', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    await openPage(page, testInfo, 'logs', messages(testInfo).nav.logs);
  });

  test('shows the newest lines first and passes the quality checks', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    const lines = page.getByRole('list', { name: m.logs.system_log }).getByRole('listitem');
    await expect(page.getByText(fill(m.logs.count, { shown: 4, total: 4 }))).toBeVisible();
    await expect(lines.first()).toContainText('a line logread could not parse');
    await expect(lines.last()).toContainText("Interface 'wan' is now up");
    await expectPageQuality(page);
  });

  test('filters problems and kernel lines and searches', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('radio', { name: m.logs.filter_problems }).check();
    await expect(page.getByText(fill(m.logs.count, { shown: 1, total: 4 }))).toBeVisible();
    await expect(page.getByText('failed to bind DHCP server socket')).toBeVisible();

    await page.getByRole('radio', { name: m.logs.filter_kernel }).check();
    await expect(page.getByText('phy0-ap0: associated')).toBeVisible();
    await expect(page.getByText('failed to bind')).toHaveCount(0);

    await page.getByRole('radio', { name: m.logs.filter_all }).check();
    await page.getByLabel(m.logs.search, { exact: true }).fill('DNSMASQ');
    await expect(page.getByText(fill(m.logs.count, { shown: 1, total: 4 }))).toBeVisible();
    await page.getByLabel(m.logs.search, { exact: true }).fill('no such text');
    await expect(page.getByText(m.logs.none)).toBeVisible();
  });

  test('warns about private data before downloading the log', async ({ page }, testInfo) => {
    const m = messages(testInfo);
    await page.getByRole('button', { name: m.logs.export }).click();
    const confirm = page.getByRole('dialog', { name: m.logs.export });
    await expect(confirm).toContainText(m.logs.export_privacy);
    await expectPageQuality(page);
    const download = page.waitForEvent('download');
    await confirm.getByRole('button', { name: m.logs.export }).click();
    const file = await download;
    expect(file.suggestedFilename()).toMatch(/^supacudy-log-.*\.txt$/);
    const text = await readFile((await file.path())!, 'utf8');
    expect(text).toContain("Sat Oct 17 04:00:01 2026 daemon.notice netifd: Interface 'wan' is now up\n");
    expect(text).toContain('a line logread could not parse\n');
  });

  test('refreshes on demand', async ({ page, router }, testInfo) => {
    const m = messages(testInfo);
    router.log.push({ time: 'Sat Oct 17 04:01:00 2026', facility: 'user', level: 'notice', source: 'test', message: 'a brand new line' });
    await page.getByRole('button', { name: m.logs.refresh }).click();
    await expect(page.getByText('a brand new line')).toBeVisible();
  });
});
