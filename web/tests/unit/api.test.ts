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

  it('turns an {error} reply into a rejection with the reason and details', async () => {
    const api = await load(SID);
    stubFetch({ result: [0, { error: 'subnet_conflict', with: 'guest' }] });
    await expect(api.setLan({ ipaddr: '192.168.9.1', netmask: '255.255.255.0', dhcp_enabled: true, start: 100, limit: 50, leasetime: '12h' }))
      .rejects.toMatchObject({ code: 'rejected', reason: 'subnet_conflict', details: { with: 'guest' } });
    expect(api.hasSession()).toBe(true);
  });

  it('sends typed arguments to the plugin', async () => {
    const api = await load(SID);
    const fetchMock = stubFetch({ result: [0, { mac: 'aa:bb:cc:dd:ee:ff', up_limit: 10, down_limit: 0 }] });
    await api.setClientLimit('aa:bb:cc:dd:ee:ff', 10, 0);
    expect(sentBody(fetchMock).body.params).toEqual([SID, 'supacudy', 'client_limit', { mac: 'aa:bb:cc:dd:ee:ff', up: 10, down: 0 }]);
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

describe('verifyPassword', () => {
  beforeEach(() => vi.resetModules());

  it('logs in once with a throwaway session and destroys it, keeping the current one', async () => {
    const api = await load(SID);
    const temp = 'b'.repeat(32);
    const fetchMock = stubFetch({ result: [0, { ubus_rpc_session: temp }] }, { result: [0] });

    expect(await api.verifyPassword('secret')).toBe(true);

    expect(sentBody(fetchMock, 0).body.params).toEqual([ANON, 'session', 'login', { username: 'root', password: 'secret' }]);
    expect(sentBody(fetchMock, 1).body.params).toEqual([temp, 'session', 'destroy', {}]);
    expect(sessionStorage.getItem('supacudy.session')).toBe(SID);
  });

  it('answers false for a wrong password without logging the user out', async () => {
    const api = await load(SID);
    const expired = vi.fn();
    api.onSessionExpired(expired);
    stubFetch({ result: [6] });

    expect(await api.verifyPassword('wrong')).toBe(false);
    expect(expired).not.toHaveBeenCalled();
    expect(api.hasSession()).toBe(true);
  });

  it('reports an unreachable router as an error, not a wrong password', async () => {
    const api = await load(SID);
    stubFetch(new TypeError('Failed to fetch'));
    await expect(api.verifyPassword('secret')).rejects.toMatchObject({ code: 'network' });
  });
});

describe('routerReachable', () => {
  beforeEach(() => vi.resetModules());

  it('is true when the router answers, even with access denied', async () => {
    const api = await load();
    stubFetch({ error: { code: -32002 } });
    expect(await api.routerReachable()).toBe(true);
  });

  it('is false when the request fails', async () => {
    const api = await load();
    stubFetch(new TypeError('Failed to fetch'));
    expect(await api.routerReachable()).toBe(false);
  });
});

describe('uploadFile', () => {
  beforeEach(() => vi.resetModules());

  class FakeXhr {
    static last: FakeXhr;
    status = 0;
    responseText = '';
    url = '';
    body: FormData | null = null;
    upload: { onprogress?: (e: ProgressEvent) => void } = {};
    onload?: () => void;
    onerror?: () => void;
    constructor() {
      FakeXhr.last = this;
    }
    open(_method: string, url: string) {
      this.url = url;
    }
    send(body: FormData) {
      this.body = body;
    }
  }

  it('posts the session, target path and file to cgi-upload and reports progress', async () => {
    const api = await load(SID);
    vi.stubGlobal('XMLHttpRequest', FakeXhr);
    const progress = vi.fn();
    const done = api.uploadFile('/tmp/firmware.bin', new Blob(['abc']), progress);

    const xhr = FakeXhr.last;
    expect(xhr.url).toBe('/cgi-bin/cgi-upload');
    expect(xhr.body!.get('sessionid')).toBe(SID);
    expect(xhr.body!.get('filename')).toBe('/tmp/firmware.bin');
    expect(xhr.body!.get('filedata')).toBeInstanceOf(Blob);
    xhr.upload.onprogress!({ lengthComputable: true, loaded: 1, total: 4 } as ProgressEvent);
    expect(progress).toHaveBeenCalledWith(0.25);
    xhr.status = 200;
    xhr.responseText = '{"size":3,"checksum":"x"}';
    xhr.onload!();
    await expect(done).resolves.toBeUndefined();
  });

  it('treats cgi-io refusing the session (HTTP 200) as an expired session', async () => {
    const api = await load(SID);
    vi.stubGlobal('XMLHttpRequest', FakeXhr);
    const expired = vi.fn();
    api.onSessionExpired(expired);
    const done = api.uploadFile('/tmp/firmware.bin', new Blob(['abc']));
    FakeXhr.last.status = 200;
    FakeXhr.last.responseText = '{"message":"Upload permission denied","failure":[1,"Operation not permitted"]}';
    FakeXhr.last.onload!();
    await expect(done).rejects.toMatchObject({ code: 'denied' });
    expect(expired).toHaveBeenCalled();
  });

  it('fails an upload the ACL refuses without logging out', async () => {
    const api = await load(SID);
    vi.stubGlobal('XMLHttpRequest', FakeXhr);
    const expired = vi.fn();
    api.onSessionExpired(expired);
    const done = api.uploadFile('/etc/passwd', new Blob(['abc']));
    FakeXhr.last.status = 200;
    FakeXhr.last.responseText = '{"message":"Access to path denied by ACL","failure":[0,"No error information"]}';
    FakeXhr.last.onload!();
    await expect(done).rejects.toMatchObject({ code: 'unknown' });
    expect(expired).not.toHaveBeenCalled();
  });

  it('treats 403 as an expired session', async () => {
    const api = await load(SID);
    vi.stubGlobal('XMLHttpRequest', FakeXhr);
    const expired = vi.fn();
    api.onSessionExpired(expired);
    const done = api.uploadFile('/tmp/firmware.bin', new Blob(['abc']));
    FakeXhr.last.status = 403;
    FakeXhr.last.onload!();
    await expect(done).rejects.toMatchObject({ code: 'denied' });
    expect(expired).toHaveBeenCalled();
  });

  it('refuses to upload without a session', async () => {
    const api = await load();
    await expect(api.uploadFile('/tmp/firmware.bin', new Blob(['abc']))).rejects.toMatchObject({ code: 'denied' });
  });
});

describe('passwordError', () => {
  it.each([
    ['', 'too_short'],
    ['1234567', 'too_short'],
    ['12345678', null],
    ['密码密码密码密码', null],
    ['x'.repeat(128), null],
    ['x'.repeat(129), 'too_long'],
    ['tab\there', 'invalid'],
    ['new\nline!', 'invalid'],
  ])('%j -> %s', async (pw, expected) => {
    const api = await load();
    expect(api.passwordError(pw)).toBe(expected);
  });
});

describe('logs', () => {
  const entry = (level: string | null) => ({ time: 't', facility: 'daemon', level, source: 's', message: 'm' });

  it.each([['err', true], ['warning', true], ['warn', true], ['crit', true], ['notice', false], ['info', false], [null, false]])(
    'level %s is a problem: %s',
    async (level, expected) => {
      const api = await load();
      expect(api.isProblem(entry(level as string | null))).toBe(expected);
    },
  );

  it('writes the log back in logread format, unparsed lines as they were', async () => {
    const api = await load();
    expect(api.logText([entry('err'), { time: null, facility: null, level: null, source: null, message: 'raw' }])).toBe(
      't daemon.err s: m\nraw\n',
    );
  });
});

describe('macError', () => {
  it.each([
    ['02:5c:00:00:00:11', null],
    ['02-5C-00-00-00-11', null],
    [' 52:54:00:fa:02:01 ', null],
    ['01:00:5e:00:00:01', 'unusable'],
    ['00:00:00:00:00:00', 'unusable'],
    ['02:5c:00:00:00', 'format'],
    ['zz:5c:00:00:00:11', 'format'],
    ['', 'format'],
  ])('%j -> %s', async (mac, expected) => {
    const api = await load();
    expect(api.macError(mac)).toBe(expected);
  });

  it('sends a clone as a custom address', async () => {
    const api = await load(SID);
    const fetchMock = stubFetch({ result: [0, { applied: true, macaddr: '02:5c:00:00:00:11' }] });
    await api.setMac('wan', 'clone', '02:5c:00:00:00:11');
    expect(sentBody(fetchMock).body.params[3]).toEqual({ target: 'wan', mode: 'custom', macaddr: '02:5c:00:00:00:11' });
  });
});

describe('callerAddress', () => {
  beforeEach(() => vi.resetModules());

  it('returns the address the CGI reports', async () => {
    const api = await load();
    vi.stubGlobal('fetch', vi.fn(async () => ({ json: async () => ({ ip: '192.168.1.20' }) }) as Response));
    expect(await api.callerAddress()).toBe('192.168.1.20');
  });

  it('returns null when the CGI is missing or answers nonsense', async () => {
    const api = await load();
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('Failed to fetch'); }));
    expect(await api.callerAddress()).toBeNull();
    vi.stubGlobal('fetch', vi.fn(async () => ({ json: async () => ({ ip: 7 }) }) as Response));
    expect(await api.callerAddress()).toBeNull();
  });
});

describe('dohUrlError', () => {
  it.each([
    ['https://dns.alidns.com/dns-query', false],
    ['https://doh.example:8443/q?x=1', false],
    ['http://dns.example/dns-query', true],
    ['https://dns.example', true],
    ['https://dns example/dns-query', true],
    [`https://dns.example/${'a'.repeat(300)}`, true],
  ])('%s -> %s', async (url, bad) => {
    const api = await load();
    expect(api.dohUrlError(url)).toBe(bad);
  });

  it('knows its providers by id', async () => {
    const api = await load();
    expect(api.isKnownProvider('alidns')).toBe(true);
    expect(api.isKnownProvider('nextdns')).toBe(false);
  });
});

describe('WireGuard configuration', () => {
  const PRIVATE = 'oGwIsQXePkq1NIVJdElbnzYDLLHMwFq5A+5Ilruz11s=';
  const PUBLIC = 'qrYCfRcXMOaEA2xznhSAKdDiPRWAHe6VeBTg4Jqawzg=';
  const conf = (peer: string) => `# provider export\n[Interface]\nPrivateKey = ${PRIVATE}\nAddress = 10.2.0.2/32\nDNS = 10.2.0.1, search.example\nMTU = 1420\n\n${peer}`;

  it('reads a provider configuration', async () => {
    const api = await load();
    const r = api.parseWgConf(conf(`[Peer]\nPublicKey = ${PUBLIC}\nAllowedIPs = 0.0.0.0/0,::/0\nEndpoint = 203.0.113.5:51820 # tokyo\n`));
    expect(r).toEqual({
      profile: {
        private_key: PRIVATE, public_key: PUBLIC, preshared_key: '', addresses: ['10.2.0.2/32'], dns: ['10.2.0.1'],
        endpoint_host: '203.0.113.5', endpoint_port: 51820, allowed_ips: ['0.0.0.0/0', '::/0'], keepalive: 0, mtu: 1420,
      },
      extraPeers: 0,
    });
  });

  it('accepts IPv6 endpoints and counts extra peers', async () => {
    const api = await load();
    const peer = `[Peer]\nPublicKey = ${PUBLIC}\nEndpoint = [2001:db8::1]:443\n`;
    const r = api.parseWgConf(conf(peer + peer));
    expect(typeof r).toBe('object');
    if (typeof r === 'object') {
      expect(r.profile).toMatchObject({ endpoint_host: '2001:db8::1', endpoint_port: 443, allowed_ips: ['0.0.0.0/0'] });
      expect(r.extraPeers).toBe(1);
    }
  });

  it.each([
    ['', 'no_interface'],
    [`[Interface]\nPrivateKey = ${PRIVATE}\n`, 'no_peer'],
    [`[Interface]\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = ${PUBLIC}\nEndpoint = a.b:1\n`, 'missing_private_key'],
    [`[Interface]\nPrivateKey = ${PRIVATE}\n[Peer]\nEndpoint = a.b:1\n`, 'missing_public_key'],
    [`[Interface]\nPrivateKey = ${PRIVATE}\n[Peer]\nPublicKey = ${PUBLIC}\nEndpoint = a.b\n`, 'missing_endpoint'],
  ])('reports problems: %#', async (text, problem) => {
    const api = await load();
    expect(api.parseWgConf(text)).toBe(problem);
  });

  it.each([
    [PRIVATE, true],
    ['oGwIsQXePkq1NIVJdElbnzYDLLHMwFq5A+5Ilruz11s', false],
    ['oGwIsQXePkq1NIVJdElbnzYDLLHMwFq5A+5Ilruz11t=', false],
    ['', false],
  ])('key %s valid: %s', async (key, ok) => {
    const api = await load();
    expect(api.isWgKey(key)).toBe(ok);
  });

  it.each([
    ['10.0.0.2/32', true], ['0.0.0.0/0', true], ['::/0', true], ['fd00::2/128', true],
    ['10.0.0.2', false], ['10.0.0.2/33', false], ['fd00::2/129', false], ['host/24', false],
  ])('cidr %s valid: %s', async (cidr, ok) => {
    const api = await load();
    expect(api.isCidr(cidr)).toBe(ok);
  });

  it('formats and parses endpoints both ways', async () => {
    const api = await load();
    expect(api.formatEndpoint('2001:db8::1', 51820)).toBe('[2001:db8::1]:51820');
    expect(api.parseEndpoint(api.formatEndpoint('vpn.example.com', 443))).toEqual({ host: 'vpn.example.com', port: 443 });
    expect(api.parseEndpoint('vpn.example.com:0')).toBeNull();
    expect(api.parseEndpoint('vpn.example.com:70000')).toBeNull();
  });

  it('names the server of either profile type', async () => {
    const api = await load();
    expect(api.profileServer({ id: 'a', type: 'openvpn', name: 'x', remote: 'vpn.example.com:1194', username: '' })).toBe('vpn.example.com:1194');
    expect(
      api.profileServer({
        id: 'b', type: 'wireguard', name: 'y', addresses: [], dns: [], mtu: 0, public_key: '', has_preshared_key: false,
        endpoint_host: '2001:db8::1', endpoint_port: 51820, allowed_ips: [], keepalive: 0,
      }),
    ).toBe('[2001:db8::1]:51820');
  });

  it('checks an OpenVPN file before upload', async () => {
    const api = await load();
    expect(api.ovpnProblem('client\nremote vpn.example.com 1194\n')).toBeNull();
    expect(api.ovpnProblem('client\n  remote 203.0.113.5\n')).toBeNull();
    expect(api.ovpnProblem('client\n# remote commented\n')).toBe('no_remote');
    expect(api.ovpnProblem(`remote a 1\n${'x'.repeat(70_000)}`)).toBe('too_large');
  });
});

describe('port ranges', () => {
  it.each([['80', false], ['8000-8010', false], ['65535', false], ['0', true], ['65536', true], ['10-5', true], ['a', true], ['', true]])(
    '%j invalid: %s',
    async (s, bad) => {
      const api = await load();
      expect(api.portRangeError(s)).toBe(bad);
    },
  );

  it('measures a range', async () => {
    const api = await load();
    expect(api.rangeSize('8000-8010')).toBe(11);
    expect(api.rangeSize('443')).toBe(1);
  });
});

describe('destinationKind', () => {
  it.each([
    ['example.com', 'domain'], ['sub.example.co.uk', 'domain'], ['203.0.113.0/24', 'network'], ['10.0.0.1', 'network'],
    ['300.0.0.1', null], ['10.0.0.0/33', null], ['localhost', null], ['bad_name.com', null], ['', null],
  ])('%j -> %s', async (s, kind) => {
    const api = await load();
    expect(api.destinationKind(s)).toBe(kind);
  });
});

describe('tailscale', () => {
  it.each([
    ['https://login.tailscale.com/a/abc123', true], ['http://login.tailscale.com/a/x', false],
    ['https://login.tailscale.com.evil.example/a', false], ['javascript:alert(1)', false], [null, false],
  ])('sign-in link %s offered: %s', async (url, offered) => {
    const api = await load();
    expect(api.safeLoginUrl(url)).toBe(offered ? url : null);
  });
});

describe('ad blocking helpers', () => {
  it('splits text into trimmed non-empty lines', async () => {
    const api = await load();
    expect(api.lines(' a \n\n b\n')).toEqual(['a', 'b']);
  });

  it.each([['https://lists.example/x.txt', false], ['http://h:8080/l', false], ['ftp://h/x', true], ['https://h', true]])(
    'list url %s bad: %s',
    async (url, bad) => {
      const api = await load();
      expect(api.filterUrlError(url)).toBe(bad);
    },
  );

  it('sends the admin password with a matching bcrypt hash for AdGuard Home', async () => {
    const api = await load(SID);
    const fetchMock = stubFetch({ result: [0, { changed: true }] });
    await api.setAdminPassword('owner-secret');
    const [, , method, args] = sentBody(fetchMock).body.params as [string, string, string, { password: string; hash: string }];
    expect(method).toBe('password_set');
    expect(args.password).toBe('owner-secret');
    const { compare } = await import('bcryptjs');
    await expect(compare('owner-secret', args.hash)).resolves.toBe(true);
  });

  it('refuses the factory password as a new one', async () => {
    const api = await load();
    expect(api.passwordError(api.DEFAULT_PASSWORD)).toBe('default');
    expect(api.passwordError('owner-secret')).toBeNull();
  });

  it('names a list after its host', async () => {
    const api = await load();
    expect(api.listNameOf('https://lists.example:8443/a/b.txt')).toBe('lists.example:8443');
  });

  it('sends a bcrypt hash of the AdGuard Home page password that matches it', async () => {
    const api = await load(SID);
    const fetchMock = stubFetch({ result: [0, { applied: true }] });
    await api.setAdguardWeb(true, 'adguard-pass');
    const [, , method, args] = sentBody(fetchMock).body.params as [string, string, string, { enabled: boolean; password: string; hash: string }];
    expect(method).toBe('adguard_web_set');
    expect(args.enabled).toBe(true);
    expect(args.hash).toMatch(/^\$2[aby]\$10\$[./A-Za-z0-9]{53}$/);
    const { compare } = await import('bcryptjs');
    await expect(compare('adguard-pass', args.hash)).resolves.toBe(true);
    expect(sentBody(fetchMock).url).not.toContain('adguard-pass');
  });

  it('turns the AdGuard Home page off without a password', async () => {
    const api = await load(SID);
    const fetchMock = stubFetch({ result: [0, { applied: true }] });
    await api.setAdguardWeb(false);
    expect(sentBody(fetchMock).body.params).toEqual([SID, 'supacudy', 'adguard_web_set', { enabled: false, password: '', hash: '' }]);
  });
});
