// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { beforeEach, describe, expect, it, vi } from 'vitest';

const ANON = '00000000000000000000000000000000';
const SID = 'a'.repeat(32);

type Reply = { result?: unknown[]; error?: { code: number; message?: string } } | Error | 'not-json';

function stubFetch(...replies: Reply[]) {
  const fetchMock = vi.fn(async () => {
    const reply = replies.shift();
    if (reply instanceof Error) throw reply;
    return {
      json: async () => {
        if (reply === 'not-json') throw new SyntaxError('Unexpected token');
        return reply;
      },
    } as Response;
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function sentBody(fetchMock: ReturnType<typeof stubFetch>, index = 0) {
  const [url, init] = fetchMock.mock.calls[index] as unknown as [string, RequestInit];
  return { url, body: JSON.parse(init.body as string) };
}

async function load(session: string | null = null) {
  vi.resetModules();
  if (session) sessionStorage.setItem('supacudy.session', session);
  return import('../../src/lib/api');
}

describe('login', () => {
  beforeEach(() => vi.resetModules());

  it('logs in with the anonymous session and stores the new one', async () => {
    const api = await load();
    const fetchMock = stubFetch({ result: [0, { ubus_rpc_session: SID }] });

    await api.login('secret');

    const { url, body } = sentBody(fetchMock);
    expect(url).toBe('/ubus');
    expect(body.params).toEqual([ANON, 'session', 'login', { username: 'root', password: 'secret' }]);
    expect(api.hasSession()).toBe(true);
    expect(sessionStorage.getItem('supacudy.session')).toBe(SID);
    expect(localStorage.length).toBe(0);
  });

  it('never puts the password in the URL', async () => {
    const api = await load();
    const fetchMock = stubFetch({ result: [0, { ubus_rpc_session: SID }] });
    await api.login('p@ss word');
    expect(sentBody(fetchMock).url).not.toContain('p@ss');
  });

  it('rejects a wrong password without firing the expiry listener', async () => {
    const api = await load();
    const expired = vi.fn();
    api.onSessionExpired(expired);
    stubFetch({ result: [6] });

    await expect(api.login('wrong')).rejects.toMatchObject({ code: 'denied' });
    expect(api.hasSession()).toBe(false);
    expect(expired).not.toHaveBeenCalled();
  });

  it('treats a login reply without a session id as an error', async () => {
    const api = await load();
    stubFetch({ result: [0, {}] });
    await expect(api.login('x')).rejects.toMatchObject({ code: 'unknown' });
    expect(api.hasSession()).toBe(false);
  });
});

describe('authenticated calls', () => {
  beforeEach(() => vi.resetModules());

  it('sends the stored session and returns the data', async () => {
    const api = await load(SID);
    const fetchMock = stubFetch({ result: [0, { model: 'TR3000' }] });

    await expect(api.getDeviceInfo()).resolves.toEqual({ model: 'TR3000' });
    expect(sentBody(fetchMock).body.params).toEqual([SID, 'supacudy', 'info', {}]);
  });

  it('returns an empty object when ubus sends no data', async () => {
    const api = await load(SID);
    stubFetch({ result: [0] });
    await expect(api.getSystemStatus()).resolves.toEqual({});
  });

  it('refuses to call without a session and sends nothing', async () => {
    const api = await load();
    const fetchMock = stubFetch();
    await expect(api.getDeviceInfo()).rejects.toMatchObject({ code: 'denied' });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it.each([
    ['ubus status 6', { result: [6] }],
    ['JSON-RPC access denied', { error: { code: -32002, message: 'Access denied' } }],
  ])('expires the session on %s', async (_name, reply) => {
    const api = await load(SID);
    const expired = vi.fn();
    api.onSessionExpired(expired);
    stubFetch(reply);

    await expect(api.getDeviceInfo()).rejects.toMatchObject({ code: 'denied' });
    expect(api.hasSession()).toBe(false);
    expect(sessionStorage.getItem('supacudy.session')).toBeNull();
    expect(expired).toHaveBeenCalledOnce();
  });

  it.each([
    [2, 'invalid'],
    [4, 'not_found'],
    [5, 'unknown'],
  ])('maps ubus status %i to %s and keeps the session', async (status, code) => {
    const api = await load(SID);
    stubFetch({ result: [status] });
    await expect(api.getDeviceInfo()).rejects.toMatchObject({ code, status });
    expect(api.hasSession()).toBe(true);
  });

  it('maps other JSON-RPC errors to unknown with the code', async () => {
    const api = await load(SID);
    stubFetch({ error: { code: -32601 } });
    await expect(api.getDeviceInfo()).rejects.toMatchObject({ code: 'unknown', status: -32601 });
  });

  it.each([
    ['a failed request', new TypeError('Failed to fetch')],
    ['a non-JSON reply', 'not-json' as const],
  ])('reports %s as a network error', async (_name, reply) => {
    const api = await load(SID);
    stubFetch(reply);
    await expect(api.getDeviceInfo()).rejects.toMatchObject({ code: 'network' });
    expect(api.hasSession()).toBe(true);
  });

  it('stops notifying a listener after it unsubscribes', async () => {
    const api = await load(SID);
    const expired = vi.fn();
    const unsubscribe = api.onSessionExpired(expired);
    unsubscribe();
    stubFetch({ result: [6] });
    await expect(api.getDeviceInfo()).rejects.toThrow();
    expect(expired).not.toHaveBeenCalled();
  });
});

describe('logout', () => {
  beforeEach(() => vi.resetModules());

  it('destroys the session on the router and forgets it locally', async () => {
    const api = await load(SID);
    const fetchMock = stubFetch({ result: [0] });

    await api.logout();

    expect(sentBody(fetchMock).body.params).toEqual([SID, 'session', 'destroy', {}]);
    expect(api.hasSession()).toBe(false);
    expect(sessionStorage.getItem('supacudy.session')).toBeNull();
  });

  it('forgets the session even when the router is unreachable', async () => {
    const api = await load(SID);
    stubFetch(new TypeError('Failed to fetch'));
    await expect(api.logout()).resolves.toBeUndefined();
    expect(api.hasSession()).toBe(false);
  });

  it('does nothing when not logged in', async () => {
    const api = await load();
    const fetchMock = stubFetch();
    await api.logout();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
