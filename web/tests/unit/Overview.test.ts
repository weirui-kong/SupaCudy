// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/svelte';
import Overview from '../../src/pages/Overview.svelte';
import * as api from '../../src/lib/api';
import { setLocale } from '../../src/lib/i18n/index.svelte';

vi.mock('../../src/lib/api', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../src/lib/api')>()),
  getDeviceInfo: vi.fn(),
  getSystemStatus: vi.fn(),
  getInternetStatus: vi.fn(),
  listClients: vi.fn(),
}));

const getDeviceInfo = vi.mocked(api.getDeviceInfo);
const getSystemStatus = vi.mocked(api.getSystemStatus);
const getInternetStatus = vi.mocked(api.getInternetStatus);
const listClients = vi.mocked(api.listClients);

function internet(active: string | null, online: boolean) {
  return { active, internet: online, ethernet: {}, repeater: {}, time: 0 } as unknown as api.InternetStatus;
}

function clients(...online: boolean[]) {
  return { clients: online.map((o) => ({ online: o })) } as unknown as api.ClientList;
}

const topology = () => screen.getByRole('navigation', { name: 'Network map' });

const INFO: api.DeviceInfo = {
  version: '0.1.0-r1',
  openwrt: '24.10.8',
  revision: 'r29233-443ec4032a',
  board: 'cudy,tr3000-v1',
  model: 'Cudy TR3000 v1',
};

const STATUS: api.SystemStatus = {
  uptime: 2 * 86400 + 3 * 3600,
  load: [0.12, 0.3, 1.5],
  cpus: 2,
  memory: { total: 512 * 1024 ** 2, available: 384 * 1024 ** 2 },
  storage: { total: 100 * 1024 ** 2, available: 70 * 1024 ** 2 },
};

const value = (label: string) => screen.getByText(label).closest('.row')!.querySelector('dd')!.textContent!.trim();

describe('Overview page', () => {
  beforeEach(() => {
    setLocale('en');
    getDeviceInfo.mockReset();
    getSystemStatus.mockReset();
    getInternetStatus.mockReset().mockReturnValue(new Promise(() => {}));
    listClients.mockReset().mockReturnValue(new Promise(() => {}));
  });

  it('shows placeholders, never fake numbers, while loading', () => {
    getDeviceInfo.mockReturnValue(new Promise(() => {}));
    getSystemStatus.mockReturnValue(new Promise(() => {}));
    render(Overview);

    for (const label of ['Model', 'OpenWrt', 'Up time', 'Memory']) expect(value(label)).toBe('—');
    expect(screen.queryByRole('meter')).toBeNull();
  });

  it('shows device information and system status', async () => {
    getDeviceInfo.mockResolvedValue(INFO);
    getSystemStatus.mockResolvedValue(STATUS);
    render(Overview);

    await waitFor(() => expect(value('Model')).toBe('Cudy TR3000 v1'));
    expect(value('OpenWrt')).toBe('24.10.8 (r29233-443ec4032a)');
    expect(value('SupaCudy')).toBe('0.1.0-r1');
    expect(value('Up time')).toBe('2 d 3 h');
    expect(value('Load average')).toBe('0.12 / 0.30 / 1.50');
    expect(value('CPU cores')).toBe('2');
    expect(value('Memory')).toBe('128 MB of 512 MB used');
    expect(screen.getByRole('meter', { name: 'Memory' }).getAttribute('aria-valuetext')).toBe('25%');
    expect(value('Storage')).toBe('30.0 MB of 100 MB used');
    expect(screen.getByRole('meter', { name: 'Storage' }).getAttribute('aria-valuetext')).toBe('30%');
  });

  it('shows a dash for storage the router cannot read', async () => {
    getDeviceInfo.mockResolvedValue(INFO);
    getSystemStatus.mockResolvedValue({ ...STATUS, storage: null });
    render(Overview);

    await waitFor(() => expect(value('Up time')).toBe('2 d 3 h'));
    expect(value('Storage')).toBe('—');
    expect(screen.queryByRole('meter', { name: 'Storage' })).toBeNull();
  });

  it('shows a dash for fields the router does not report', async () => {
    getDeviceInfo.mockResolvedValue({ ...INFO, model: null, revision: null });
    getSystemStatus.mockResolvedValue(STATUS);
    render(Overview);

    await waitFor(() => expect(value('OpenWrt')).toBe('24.10.8'));
    expect(value('Model')).toBe('—');
  });

  it('explains the error when the first load fails', async () => {
    getDeviceInfo.mockRejectedValue(new api.ApiError('network'));
    getSystemStatus.mockRejectedValue(new api.ApiError('network'));
    render(Overview);

    expect((await screen.findByRole('alert')).textContent).toContain('Cannot reach the router');
    expect(value('Up time')).toBe('—');
  });

  it('keeps the last values and warns when a later refresh fails', async () => {
    getDeviceInfo.mockResolvedValue(INFO);
    getSystemStatus.mockResolvedValueOnce(STATUS).mockRejectedValue(new api.ApiError('network'));
    render(Overview, { refreshMs: 20 });

    await waitFor(() => expect(value('Up time')).toBe('2 d 3 h'));
    expect((await screen.findByRole('status')).textContent).toContain('Retrying automatically');
    expect(value('Up time')).toBe('2 d 3 h');
  });

  it('refreshes the status periodically', async () => {
    getDeviceInfo.mockResolvedValue(INFO);
    getSystemStatus.mockResolvedValueOnce(STATUS).mockResolvedValue({ ...STATUS, uptime: 3 * 86400 });
    render(Overview, { refreshMs: 20 });

    await waitFor(() => expect(value('Up time')).toBe('3 d 0 h'));
    expect(getSystemStatus.mock.calls.length).toBeGreaterThanOrEqual(2);
  });

  it('flags memory usage above 90% in text, not only by color', async () => {
    getDeviceInfo.mockResolvedValue(INFO);
    getSystemStatus.mockResolvedValue({ ...STATUS, memory: { total: 1000, available: 50 } });
    render(Overview);

    await waitFor(() => expect(screen.getByText('95%')).toBeTruthy());
    expect(screen.getByText('95%').classList.contains('high')).toBe(true);
  });

  it('renders in Chinese', async () => {
    setLocale('zh-CN');
    getDeviceInfo.mockResolvedValue(INFO);
    getSystemStatus.mockResolvedValue(STATUS);
    render(Overview);

    await waitFor(() => expect(value('运行时间')).toBe('2 天 3 小时'));
    expect(value('内存')).toBe('已用 128 MB，共 512 MB');
  });

  describe('network map', () => {
    beforeEach(() => {
      getDeviceInfo.mockResolvedValue(INFO);
      getSystemStatus.mockResolvedValue(STATUS);
    });

    it('shows the internet source and online client count, linking to their pages', async () => {
      getInternetStatus.mockResolvedValue(internet('wwan', true));
      listClients.mockResolvedValue(clients(true, true, false));
      render(Overview);

      const internetLink = await screen.findByRole('link', { name: /Internet.*Repeater/ });
      expect(internetLink.getAttribute('href')).toBe('#/internet');
      const clientsLink = await screen.findByRole('link', { name: /Clients.*2 online/ });
      expect(clientsLink.getAttribute('href')).toBe('#/clients');
    });

    it('says offline in text, not only by color', async () => {
      getInternetStatus.mockResolvedValue(internet(null, false));
      listClients.mockResolvedValue(clients());
      render(Overview);

      await waitFor(() => expect(topology().textContent).toContain('Offline'));
      expect(topology().textContent).toContain('0 online');
    });

    it('shows dashes when the status cannot be read', async () => {
      getInternetStatus.mockRejectedValue(new api.ApiError('network'));
      listClients.mockRejectedValue(new api.ApiError('network'));
      render(Overview);

      await waitFor(() => expect(getInternetStatus).toHaveBeenCalled());
      await waitFor(() => expect(topology().textContent!.match(/—/g)?.length).toBe(2));
    });
  });
});
