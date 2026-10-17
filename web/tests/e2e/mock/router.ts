// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// An in-memory stand-in for the router's /ubus endpoint, so the UI tests run
// against realistic data without a device. It mirrors the reply shapes and
// the error convention of the real rpcd plugin; behaviour that only the real
// system can show (traffic really blocked, services restarting) is covered
// by the emulator tests instead.

import type { Route } from '@playwright/test';

const BCRYPT = /^\$2[aby]\$\d\d\$[./A-Za-z0-9]{53}$/;
const AG_LIST_1 = 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt';
const AG_CATALOG = [
  { name: 'AdGuard DNS filter', url: AG_LIST_1 },
  { name: 'AdAway Default Blocklist', url: 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt' },
];

export const PASSWORD = 'supacudy-test';
const ANON = '00000000000000000000000000000000';

const INVALID = 2;
const NOT_FOUND = 4;

type Args = Record<string, unknown>;
type Reply = { status: number; data?: unknown } | { jsonrpcError: number };

export interface MockClient {
  mac: string;
  ip: string | null;
  hostname: string | null;
  name: string | null;
  type: string | null;
  online: boolean;
  connection: 'wifi' | 'wired' | null;
  band: '2g' | '5g' | null;
  network: string;
  signal: number | null;
  random_mac: boolean;
  blocked: boolean;
  up_limit: number;
  down_limit: number;
  tx_bytes: number;
  rx_bytes: number;
  reserved_ip: string | null;
}

const MAC = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/;

function ipToInt(ip: string): number | null {
  const parts = ip.split('.');
  if (parts.length !== 4 || parts.some((p) => !/^\d{1,3}$/.test(p) || Number(p) > 255)) return null;
  return parts.reduce((n, p) => n * 256 + Number(p), 0);
}

function intToIp(n: number): string {
  return [24, 16, 8, 0].map((s) => Math.floor(n / 2 ** s) % 256).join('.');
}

function prefixOf(netmask: string): number | null {
  const n = ipToInt(netmask);
  if (n === null) return null;
  for (let p = 0; p <= 32; p++) if ((p === 0 ? 0 : (0xffffffff << (32 - p)) >>> 0) === n) return p;
  return null;
}

interface EapArgs {
  method: string;
  identity: string;
  anonymous_identity: string;
  password: string;
  phase2: string;
  validate: boolean;
  domain: string;
}

interface SavedRepeater {
  ssid: string;
  encryption: string;
  key: string;
  eap?: EapArgs | null;
  last_used: number;
}

export class MockRouter {
  sessions = new Set<string>();
  calls: { method: string; args: Args }[] = [];
  uptime = 2 * 86400 + 3 * 3600;

  info = {
    version: '0.3.0-r1',
    openwrt: '24.10.8',
    revision: 'r29233-443ec4032a',
    board: 'cudy,tr3000-v1',
    model: 'Cudy TR3000 v1',
  };

  clients: MockClient[] = [
    {
      mac: '02:5c:00:00:00:11', ip: '192.168.1.113', hostname: 'Work-Laptop', name: null, type: null,
      online: true, connection: 'wired', band: null, network: 'lan', signal: null, random_mac: false,
      blocked: false, up_limit: 0, down_limit: 0, tx_bytes: 1_200_000, rx_bytes: 9_800_000, reserved_ip: null,
    },
    {
      mac: '6a:00:00:00:02:00', ip: '192.168.1.110', hostname: 'Pixel-Phone', name: null, type: 'phone',
      online: true, connection: 'wifi', band: '5g', network: 'lan', signal: -48, random_mac: true,
      blocked: false, up_limit: 0, down_limit: 0, tx_bytes: 300_000, rx_bytes: 4_100_000, reserved_ip: null,
    },
    {
      mac: '00:11:32:aa:bb:12', ip: '192.168.1.50', hostname: 'Home-NAS', name: 'Home NAS', type: 'nas',
      online: true, connection: 'wired', band: null, network: 'lan', signal: null, random_mac: false,
      blocked: false, up_limit: 0, down_limit: 0, tx_bytes: 0, rx_bytes: 0, reserved_ip: '192.168.1.50',
    },
    {
      mac: '00:24:e4:00:00:31', ip: '192.168.1.140', hostname: 'Living-Room-TV', name: null, type: 'tv',
      online: false, connection: 'wired', band: null, network: 'lan', signal: null, random_mac: false,
      blocked: true, up_limit: 0, down_limit: 0, tx_bytes: 52_000, rx_bytes: 880_000, reserved_ip: null,
    },
  ];

  lan = {
    ipaddr: '192.168.1.1',
    prefix: 24,
    dhcp: { enabled: true, start: 100, limit: 150, leasetime: '12h' },
  };

  failures = new Map<string, Reply>();

  failNext(method: string, reply: Reply) {
    this.failures.set(method, reply);
  }

  async handle(route: Route) {
    const request = JSON.parse(route.request().postData() ?? '{}');
    const [session, object, method, args = {}] = request.params ?? [];
    const reply = this.dispatch(session, object, method, args);
    const body =
      'jsonrpcError' in reply
        ? { jsonrpc: '2.0', id: request.id, error: { code: reply.jsonrpcError, message: 'Access denied' } }
        : { jsonrpc: '2.0', id: request.id, result: reply.data === undefined ? [reply.status] : [reply.status, reply.data] };
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
  }

  // /cgi-bin/supacudy-login; session.login on /ubus is closed like on the router.
  loginAttempts = 0;

  async handleLogin(route: Route) {
    let password: unknown;
    try {
      password = JSON.parse(route.request().postData() ?? '{}').password;
    } catch {
      password = undefined;
    }
    const reply = (status: number, body: object) =>
      route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
    if (typeof password !== 'string') return reply(400, { error: 'invalid' });
    this.loginAttempts++;
    const expected = this.setup.default_password ? 'supacudy' : this.setup.password_set ? this.password : '';
    if (password !== expected) return reply(403, { error: 'wrong_password' });
    const id = Array.from({ length: 32 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
    this.sessions.add(id);
    return reply(200, { ubus_rpc_session: id, expires: 300 });
  }

  private dispatch(session: string, object: string, method: string, args: Args): Reply {
    if (session === ANON && object === 'supacudy' && method === 'setup_status') return this.m_setup_status();
    if (session === ANON || !this.sessions.has(session)) return { jsonrpcError: -32002 };
    if (object === 'session' && method === 'destroy') {
      this.sessions.delete(session);
      return { status: 0 };
    }
    if (object !== 'supacudy') return { status: NOT_FOUND };

    this.calls.push({ method, args });
    const failure = this.failures.get(method);
    if (failure) {
      this.failures.delete(method);
      return failure;
    }
    const handler = (this as unknown as Record<string, (a: Args) => Reply>)[`m_${method}`];
    return handler ? handler.call(this, args) : { status: NOT_FOUND };
  }

  private ok(data: unknown): Reply {
    return { status: 0, data };
  }

  private rejected(reason: string, details: Args = {}): Reply {
    return { status: 0, data: { ...details, error: reason } };
  }

  private client(mac: unknown): MockClient | undefined {
    return typeof mac === 'string' ? this.clients.find((c) => c.mac === mac) : undefined;
  }

  // Each poll advances time and counters so speeds are non-zero.
  private tick() {
    this.uptime += 3;
    for (const c of this.clients) {
      if (!c.online) continue;
      c.tx_bytes += c.connection === 'wifi' ? 24_000 : 9_000;
      c.rx_bytes += c.connection === 'wifi' ? 310_000 : 150_000;
    }
  }

  wifi = {
    encryptions: ['sae-mixed', 'psk2', 'sae', 'psk-mixed', 'none'],
    guest_subnet: null as string | null,
    radios: [
      {
        name: 'radio0', band: '2g', enabled: true, channel: 6 as number | 'auto', channels: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        width: 20, widths: [20, 40], txpower: 'max', locked: null as 'repeater' | null,
        main: { enabled: true, ssid: 'Home-WiFi', encryption: 'sae-mixed', key: 'correct-horse', hidden: false },
        guest: null as null | { enabled: boolean; ssid: string; encryption: string; key: string; hidden: boolean },
      },
      {
        name: 'radio1', band: '5g', enabled: true, channel: 'auto' as number | 'auto', channels: [36, 40, 44, 48, 149, 153, 157, 161],
        width: 80, widths: [20, 40, 80], txpower: 'max', locked: null as 'repeater' | null,
        main: { enabled: true, ssid: 'Home-WiFi-5G', encryption: 'sae-mixed', key: 'correct-horse', hidden: false },
        guest: null as null | { enabled: boolean; ssid: string; encryption: string; key: string; hidden: boolean },
      },
    ],
  };

  private radio(name: unknown) {
    return this.wifi.radios.find((r) => r.name === name);
  }

  private networkProblem(a: Args): string | null | 'invalid' {
    if (typeof a.ssid !== 'string' || typeof a.key !== 'string' || typeof a.hidden !== 'boolean' ||
        typeof a.enabled !== 'boolean' || typeof a.encryption !== 'string' || !this.wifi.encryptions.includes(a.encryption))
      return 'invalid';
    if (a.ssid.length < 1 || new TextEncoder().encode(a.ssid).length > 32) return 'ssid_length';
    if (a.encryption !== 'none' && (a.key.length < 8 || a.key.length > 63)) return 'key_invalid';
    return null;
  }

  m_wifi_get() {
    return this.ok({
      radios: this.wifi.radios.map((r) => ({ ...structuredClone(r), encryptions: this.wifi.encryptions })),
      guest_subnet: this.wifi.guest_subnet,
    });
  }

  m_wifi_set(a: Args) {
    const r = this.radio(a.radio);
    if (!r) return { status: NOT_FOUND };
    if (typeof a.channel !== 'string' || !Number.isInteger(a.width) || typeof a.txpower !== 'string') return { status: INVALID };
    const problem = a.enabled ? this.networkProblem(a) : null;
    if (problem === 'invalid') return { status: INVALID };
    if (problem) return this.rejected(problem);
    const channel = a.channel === 'auto' ? 'auto' : Number(a.channel);
    if (!r.locked && channel !== 'auto' && !r.channels.includes(channel)) return this.rejected('channel_unavailable');
    if (!r.locked && !r.widths.includes(a.width as number)) return this.rejected('width_unavailable');
    r.enabled = a.enabled as boolean;
    if (!r.locked) {
      r.channel = channel;
      r.width = a.width as number;
    }
    r.txpower = a.txpower;
    if (a.enabled) r.main = { enabled: true, ssid: a.ssid as string, encryption: a.encryption as string, key: a.key as string, hidden: a.hidden as boolean };
    return this.ok({ applied: true });
  }

  m_guest_set(a: Args) {
    const r = this.radio(a.radio);
    if (!r) return { status: NOT_FOUND };
    if (typeof a.enabled !== 'boolean') return { status: INVALID };
    if (a.enabled) {
      const problem = this.networkProblem(a);
      if (problem === 'invalid') return { status: INVALID };
      if (problem) return this.rejected(problem);
    }
    this.wifi.guest_subnet ??= '192.168.2.0/24';
    r.guest = { enabled: a.enabled, ssid: a.ssid as string, encryption: a.encryption as string, key: a.key as string, hidden: a.hidden as boolean };
    return this.ok({ applied: true, subnet: this.wifi.guest_subnet });
  }

  m_info() {
    return this.ok(this.info);
  }

  m_status() {
    return this.ok({
      uptime: this.uptime,
      load: [0.12, 0.3, 0.25],
      cpus: 2,
      memory: { total: 512 * 1024 ** 2, available: 384 * 1024 ** 2 },
      storage: { total: 100 * 1024 ** 2, available: 70 * 1024 ** 2 },
      temperature: { ...this.temperature },
    });
  }

  temperature = { cpu: 52.4 as number | null, wifi: 47 as number | null };
  cpuLimit = 80;

  m_cpu_limit_get() {
    return this.ok({ limit: this.cpuLimit });
  }

  m_cpu_limit_set(a: Args) {
    if (![30, 50, 80, 100].includes(a.limit as number)) return { status: INVALID };
    this.cpuLimit = a.limit as number;
    return this.ok({ applied: true });
  }

  m_clients_list() {
    this.tick();
    return this.ok({ clients: structuredClone(this.clients), time: this.uptime });
  }

  m_client_set(a: Args) {
    const c = this.client(a.mac);
    if (!c || typeof a.name !== 'string' || a.name.length > 64 || typeof a.type !== 'string') return { status: INVALID };
    c.name = a.name.trim() || null;
    c.type = a.type || null;
    return this.ok({ mac: c.mac, name: c.name, type: c.type });
  }

  m_client_block(a: Args) {
    const c = this.client(a.mac);
    if (!c || typeof a.blocked !== 'boolean') return { status: INVALID };
    c.blocked = a.blocked;
    return this.ok({ mac: c.mac, blocked: c.blocked });
  }

  m_client_limit(a: Args) {
    const c = this.client(a.mac);
    const valid = (v: unknown) => Number.isInteger(v) && (v as number) >= 0 && (v as number) <= 1_000_000;
    if (!c || !valid(a.up) || !valid(a.down)) return { status: INVALID };
    c.up_limit = a.up as number;
    c.down_limit = a.down as number;
    return this.ok({ mac: c.mac, up_limit: c.up_limit, down_limit: c.down_limit });
  }

  m_clients_forget_offline() {
    const before = this.clients.length;
    this.clients = this.clients.filter((c) => c.online);
    return this.ok({ forgotten: before - this.clients.length });
  }

  m_clients_reset_counters() {
    for (const c of this.clients) c.tx_bytes = c.rx_bytes = 0;
    return this.ok({ reset: true });
  }

  private network(): number {
    const size = 2 ** (32 - this.lan.prefix);
    return Math.floor(ipToInt(this.lan.ipaddr)! / size) * size;
  }

  private reservations() {
    return this.clients
      .filter((c) => c.reserved_ip)
      .map((c, i) => ({ id: `cfg${i}`, mac: c.mac, ip: c.reserved_ip, name: c.hostname }));
  }

  m_lan_get() {
    const net = this.network();
    const { start, limit } = this.lan.dhcp;
    return this.ok({
      ipaddr: this.lan.ipaddr,
      netmask: intToIp(this.lan.prefix === 0 ? 0 : (0xffffffff << (32 - this.lan.prefix)) >>> 0),
      prefix: this.lan.prefix,
      dhcp: { ...this.lan.dhcp, first: intToIp(net + start), last: intToIp(net + start + limit - 1) },
      reservations: this.reservations(),
    });
  }

  m_lan_set(a: Args) {
    if (typeof a.ipaddr !== 'string' || typeof a.netmask !== 'string' || typeof a.dhcp_enabled !== 'boolean' ||
        !Number.isInteger(a.start) || !Number.isInteger(a.limit) || typeof a.leasetime !== 'string')
      return { status: INVALID };
    const prefix = prefixOf(a.netmask);
    const ip = ipToInt(a.ipaddr);
    if (prefix === null || ip === null || prefix < 16 || prefix > 30) return this.rejected('invalid_subnet');
    if (!/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(a.ipaddr)) return this.rejected('not_private');
    const size = 2 ** (32 - prefix);
    if ((a.start as number) + (a.limit as number) > size - 1) return this.rejected('pool_out_of_range');
    const moved = a.ipaddr !== this.lan.ipaddr;
    this.lan = {
      ipaddr: a.ipaddr,
      prefix,
      dhcp: { enabled: a.dhcp_enabled, start: a.start as number, limit: a.limit as number, leasetime: a.leasetime },
    };
    return this.ok({ applied: true, address_changed: moved, ipaddr: a.ipaddr });
  }

  m_reservation_set(a: Args) {
    if (typeof a.mac !== 'string' || !MAC.test(a.mac) || typeof a.ip !== 'string' || ipToInt(a.ip) === null)
      return { status: INVALID };
    const size = 2 ** (32 - this.lan.prefix);
    const n = ipToInt(a.ip)!;
    if (n <= this.network() || n >= this.network() + size - 1) return this.rejected('outside_lan');
    if (a.ip === this.lan.ipaddr) return this.rejected('router_address');
    const other = this.clients.find((c) => c.reserved_ip === a.ip && c.mac !== a.mac);
    if (other) return this.rejected('ip_taken', { by: other.mac });
    let c = this.client(a.mac);
    if (!c) {
      c = {
        mac: a.mac, ip: null, hostname: null, name: null, type: null, online: false, connection: null, band: null,
        network: 'lan', signal: null, random_mac: false, blocked: false, up_limit: 0, down_limit: 0, tx_bytes: 0,
        rx_bytes: 0, reserved_ip: null,
      };
      this.clients.push(c);
    }
    c.reserved_ip = a.ip;
    return this.ok({ mac: c.mac, ip: a.ip, name: (a.name as string) || null });
  }

  m_reservation_delete(a: Args) {
    const c = this.client(a.mac);
    if (!c?.reserved_ip) return { status: NOT_FOUND };
    c.reserved_ip = null;
    return this.ok({ mac: c.mac, deleted: true });
  }

  wan = {
    proto: 'dhcp' as 'dhcp' | 'static' | 'pppoe',
    ipaddr: '', netmask: '255.255.255.0', gateway: '', dns: [] as string[], username: '', password: '',
    carrier: true,
  };

  repeater = {
    ssid: null as string | null,
    band: null as '2g' | '5g' | null,
    enabled: false,
    connected: false,
    auto_switch: true,
    force_20mhz: false,
    saved: [{ ssid: 'Cafe-Free', encryption: 'none', key: '', last_used: 1_760_000_000 }] as SavedRepeater[],
    // What the next join ends in, and how many status reads it takes.
    joinOutcome: 'connected' as 'connected' | 'wrong_key' | 'auth_failed' | 'certificate' | 'rejected' | 'not_found' | 'no_address' | 'timeout',
    joinPolls: 1,
    joinState: 'idle' as 'idle' | 'connecting' | 'connected' | 'failed',
    pollsLeft: 0,
  };

  scan = [
    { ssid: 'Hotel-WiFi', bssid: '02:00:00:00:00:a1', band: '2g', channel: 1, signal: -52, encryption: 'psk2' },
    { ssid: 'Hotel-WiFi', bssid: '02:00:00:00:00:a2', band: '5g', channel: 36, signal: -66, encryption: 'psk2' },
    { ssid: 'Cafe-Free', bssid: '02:00:00:00:00:b1', band: '2g', channel: 11, signal: -78, encryption: 'none' },
    { ssid: 'Corp-Secure', bssid: '02:00:00:00:00:c1', band: '5g', channel: 149, signal: -60, encryption: 'enterprise' },
    { ssid: 'Corp-Secure', bssid: '02:00:00:00:00:c2', band: '2g', channel: 6, signal: -58, encryption: 'enterprise' },
    { ssid: 'Old-Lab', bssid: '02:00:00:00:00:d1', band: '2g', channel: 3, signal: -82, encryption: 'wep' },
  ];

  m_internet_status() {
    const wanUp = this.wan.carrier;
    const wwanUp = this.repeater.enabled && this.repeater.connected;
    return this.ok({
      active: wanUp ? 'wan' : wwanUp ? 'wwan' : this.tethering.enabled && this.tethering.available ? 'tethering' : null,
      internet: wanUp || wwanUp || (this.tethering.enabled && this.tethering.available),
      ethernet: {
        configured: true, carrier: this.wan.carrier, up: wanUp, proto: this.wan.proto, uptime: wanUp ? 3600 : 0,
        ipaddr: wanUp ? (this.wan.proto === 'static' ? `${this.wan.ipaddr}/24` : '10.0.0.15/24') : null,
        gateway: wanUp ? (this.wan.gateway || '10.0.0.1') : null,
        dns: wanUp ? (this.wan.dns.length ? this.wan.dns : ['10.0.0.1']) : [],
      },
      repeater: {
        configured: this.repeater.ssid !== null, enabled: this.repeater.enabled, ssid: this.repeater.ssid,
        band: this.repeater.band, connected: this.repeater.connected, bssid: this.repeater.connected ? '02:00:00:00:00:a1' : null,
        signal: this.repeater.connected ? -52 : null, up: wwanUp, uptime: wwanUp ? 120 : 0,
        ipaddr: wwanUp ? '10.250.11.110/24' : null, gateway: wwanUp ? '10.250.11.1' : null, dns: wwanUp ? ['10.250.11.1'] : [],
      },
      tethering: {
        enabled: this.tethering.enabled, available: this.tethering.available, device: this.tethering.available ? 'usb0' : null,
        up: this.tethering.enabled && this.tethering.available, uptime: 30,
        ipaddr: this.tethering.enabled && this.tethering.available ? '192.168.42.20/24' : null,
        gateway: this.tethering.enabled && this.tethering.available ? '192.168.42.129' : null, dns: [],
      },
      time: this.uptime,
    });
  }

  tethering = { enabled: false, available: false };

  m_tethering_set(a: Args) {
    if (typeof a.enabled !== 'boolean') return { status: INVALID };
    this.tethering.enabled = a.enabled;
    return this.ok({ applied: true });
  }

  wanAsLan = false;

  m_wan_get() {
    const { password, ...wan } = structuredClone(this.wan);
    return this.ok({ ...wan, has_password: !!password, as_lan: this.wanAsLan, device: 'eth1', service: '' });
  }

  m_wan_port_set(a: Args) {
    if (typeof a.as_lan !== 'boolean') return { status: INVALID };
    this.wanAsLan = a.as_lan;
    return this.ok({ applied: true });
  }

  m_wan_set(a: Args) {
    if (!['dhcp', 'static', 'pppoe'].includes(a.proto as string) || !Array.isArray(a.dns) ||
        a.dns.some((d) => typeof d !== 'string' || ipToInt(d) === null))
      return { status: INVALID };
    if (a.proto === 'static') {
      const prefix = prefixOf(String(a.netmask));
      const ip = ipToInt(String(a.ipaddr));
      const gw = ipToInt(String(a.gateway));
      if (prefix === null || ip === null || prefix < 8 || prefix > 30) return this.rejected('invalid_address');
      const size = 2 ** (32 - prefix);
      const network = ip - (ip % size);
      if (gw === null || gw <= network || gw >= network + size - 1 || gw === ip) return this.rejected('gateway_outside');
      const lanSize = 2 ** (32 - this.lan.prefix);
      const lanNetwork = ipToInt(this.lan.ipaddr)! - (ipToInt(this.lan.ipaddr)! % lanSize);
      if (network < lanNetwork + lanSize && lanNetwork < network + size) return this.rejected('subnet_conflict', { with: 'lan' });
    }
    if (a.proto === 'pppoe' && (typeof a.username !== 'string' || !a.username)) return this.rejected('pppoe_credentials');
    Object.assign(this.wan, {
      proto: a.proto, ipaddr: a.proto === 'static' ? a.ipaddr : '', netmask: a.proto === 'static' ? a.netmask : '255.255.255.0',
      gateway: a.proto === 'static' ? a.gateway : '', dns: a.dns,
      username: a.proto === 'pppoe' ? a.username : '',
      password: a.proto === 'pppoe' ? (a.password as string) || (this.wan.proto === 'pppoe' ? this.wan.password : '') : '',
    });
    return this.ok({ applied: true });
  }

  m_repeater_scan() {
    const saved = new Set(this.repeater.saved.map((n) => n.ssid));
    return this.ok({
      networks: this.scan.map((n) => ({
        ...n, saved: saved.has(n.ssid), current: this.repeater.connected && this.repeater.ssid === n.ssid,
      })),
    });
  }

  m_repeater_connect(a: Args) {
    if (typeof a.ssid !== 'string' || typeof a.key !== 'string' || typeof a.save !== 'boolean' || typeof a.encryption !== 'string')
      return { status: INVALID };
    const saved = this.repeater.saved.find((n) => n.ssid === a.ssid);
    const key = a.key || saved?.key || '';
    let eap: EapArgs | null = null;
    if (a.encryption === 'enterprise') {
      eap = a.eap as EapArgs;
      const phase2: Record<string, string[]> = { peap: ['MSCHAPV2', 'GTC'], ttls: ['MSCHAPV2', 'PAP'] };
      if (!eap || !phase2[eap.method]?.includes(eap.phase2) || typeof eap.identity !== 'string' || !eap.identity ||
          typeof eap.password !== 'string' || typeof eap.anonymous_identity !== 'string' || typeof eap.validate !== 'boolean' ||
          typeof eap.domain !== 'string' || (eap.validate && !/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(eap.domain)))
        return { status: INVALID };
      eap = { ...eap, password: eap.password || saved?.eap?.password || '' };
      if (!eap.password) return this.rejected('eap_password_needed');
    } else if (a.encryption !== 'none' && a.encryption !== 'owe' && (key.length < 8 || key.length > 63)) {
      return this.rejected('key_invalid');
    }
    const band = (a.band || '2g') as '2g' | '5g';
    const ok = this.repeater.joinOutcome === 'connected';
    Object.assign(this.repeater, {
      ssid: a.ssid, band, enabled: true, connected: ok, joinState: 'connecting', pollsLeft: this.repeater.joinPolls,
    });
    for (const r of this.wifi.radios) r.locked = r.band === band ? 'repeater' : null;
    if (a.save) {
      const entry = { ssid: a.ssid, encryption: a.encryption, key: eap ? '' : key, eap, last_used: 1_760_000_100 };
      if (saved) Object.assign(saved, entry);
      else this.repeater.saved.push(entry);
    }
    return this.ok({ applied: true });
  }

  m_repeater_status() {
    const r = this.repeater;
    if (!r.enabled) return this.ok({ state: 'idle', ssid: null, reason: null, ipaddr: null });
    if (r.joinState === 'connecting' && r.pollsLeft-- <= 0) r.joinState = r.joinOutcome === 'connected' ? 'connected' : 'failed';
    return this.ok({
      state: r.joinState, ssid: r.ssid,
      reason: r.joinState === 'failed' ? r.joinOutcome : null,
      ipaddr: r.joinState === 'connected' ? '10.250.11.110/24' : null,
    });
  }

  m_repeater_disconnect() {
    Object.assign(this.repeater, { enabled: false, connected: false });
    for (const r of this.wifi.radios) r.locked = null;
    return this.ok({ applied: true });
  }

  m_repeater_saved() {
    return this.ok({
      networks: this.repeater.saved.map(({ ssid, encryption, last_used, eap }) => ({
        ssid, encryption, last_used, eap: eap ? { ...eap, password: '' } : null,
      })),
      auto_switch: this.repeater.auto_switch,
      force_20mhz: this.repeater.force_20mhz,
    });
  }

  m_repeater_forget(a: Args) {
    const i = this.repeater.saved.findIndex((n) => n.ssid === a.ssid);
    if (i < 0) return { status: NOT_FOUND };
    this.repeater.saved.splice(i, 1);
    return this.ok({ forgotten: true });
  }

  m_repeater_options(a: Args) {
    if (typeof a.auto_switch !== 'boolean' || typeof a.force_20mhz !== 'boolean') return { status: INVALID };
    this.repeater.auto_switch = a.auto_switch;
    this.repeater.force_20mhz = a.force_20mhz;
    return this.ok({ auto_switch: a.auto_switch, force_20mhz: a.force_20mhz });
  }

  password = PASSWORD;
  time = { time: 1_792_000_000, zonename: 'UTC', ntp: true, zones: ['UTC', 'America/New York', 'Asia/Shanghai', 'Europe/Berlin'] };
  restarts: string[] = [];
  firmware: { size: number; valid: boolean; allow_backup: boolean } | null = null;
  // What the next upload is judged to be.
  nextFirmwareValid = true;

  async handleUpload(route: Route) {
    const body = route.request().postDataBuffer() ?? Buffer.alloc(0);
    const text = body.toString('latin1');
    const session = /name="sessionid"\r\n\r\n([0-9a-f]+)/.exec(text)?.[1];
    // Like cgi-io: refusals are HTTP 200 with a message.
    const refuse = (message: string) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ message, failure: [1, 'Operation not permitted'] }) });
    if (!session || !this.sessions.has(session)) return refuse('Upload permission denied');
    if (!text.includes('name="filename"\r\n\r\n/tmp/firmware.bin')) return refuse('Access to path denied by ACL');
    this.firmware = { size: body.length, valid: this.nextFirmwareValid, allow_backup: this.nextFirmwareValid };
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ size: body.length }) });
  }

  m_time_get() {
    return this.ok(structuredClone(this.time));
  }

  m_time_set(a: Args) {
    if (typeof a.zonename !== 'string' || !this.time.zones.includes(a.zonename) || typeof a.ntp !== 'boolean' ||
        typeof a.time !== 'number' || !Number.isInteger(a.time))
      return { status: INVALID };
    Object.assign(this.time, { zonename: a.zonename, ntp: a.ntp });
    if (a.time) this.time.time = a.time;
    return this.ok({ applied: true });
  }

  m_password_set(a: Args) {
    if (typeof a.password !== 'string' || typeof a.hash !== 'string' || !BCRYPT.test(a.hash)) return { status: INVALID };
    if (a.password.length < 8 || a.password.length > 128) return this.rejected('password_invalid');
    this.password = a.password;
    this.setup.password_set = true;
    this.setup.default_password = false;
    // One password for every login: AdGuard Home gets the same one.
    this.adguard.webHash = a.hash;
    this.adguard.web.synced = true;
    return this.ok({ changed: true });
  }

  m_reboot() {
    this.restarts.push('reboot');
    return this.ok({ rebooting: true });
  }

  m_factory_reset() {
    this.restarts.push('reset');
    return this.ok({ resetting: true });
  }

  m_firmware_check() {
    if (!this.firmware) return { status: NOT_FOUND };
    return this.ok({ ...this.firmware, forceable: false });
  }

  m_firmware_upgrade(a: Args) {
    if (typeof a.keep_settings !== 'boolean') return { status: INVALID };
    if (!this.firmware) return { status: NOT_FOUND };
    if (!this.firmware.valid) return this.rejected('firmware_invalid');
    this.restarts.push(a.keep_settings ? 'upgrade-keep' : 'upgrade-erase');
    return this.ok({ upgrading: true });
  }

  m_firmware_discard() {
    this.firmware = null;
    return this.ok({ discarded: true });
  }

  setup = { setup_done: true, password_set: true, default_password: false };

  rescue = { active: false, address: null as string | null, ssid: null as string | null, since: null as number | null };

  m_setup_status() {
    return this.ok({ ...this.setup, rescue: { ...this.rescue } });
  }

  m_rescue_get() {
    return this.ok({ ...this.rescue });
  }

  m_setup_complete() {
    this.setup.setup_done = true;
    return this.ok({ setup_done: true });
  }

  log = [
    { time: 'Sat Oct 17 04:00:01 2026', facility: 'daemon', level: 'notice', source: 'netifd', message: "Interface 'wan' is now up" },
    { time: 'Sat Oct 17 04:00:02 2026', facility: 'kern', level: 'info', source: 'kernel', message: '[ 12.3] phy0-ap0: associated' },
    { time: 'Sat Oct 17 04:00:03 2026', facility: 'daemon', level: 'err', source: 'dnsmasq[812]', message: 'failed to bind DHCP server socket' },
    { time: null, facility: null, level: null, source: null, message: 'a line logread could not parse' },
  ];

  m_log_get(a: Args) {
    if (typeof a.lines !== 'number' || a.lines < 1 || a.lines > 2000) return { status: INVALID };
    return this.ok({ entries: this.log.slice(-a.lines) });
  }

  mac = { wanCustom: null as string | null, repeaterCustom: null as string | null };
  // The address /cgi-bin/supacudy-whoami reports for the browser.
  callerIp: string | null = '192.168.1.113';

  m_mac_get() {
    return this.ok({
      wan: { device: 'eth1', current: this.mac.wanCustom ?? '52:54:00:fa:02:01', custom: this.mac.wanCustom, factory: '52:54:00:fa:02:01' },
      repeater: { configured: this.repeater.ssid !== null, custom: this.mac.repeaterCustom },
    });
  }

  m_mac_set(a: Args) {
    if (!['wan', 'repeater'].includes(a.target as string) || !['default', 'custom', 'random'].includes(a.mode as string) ||
        typeof a.macaddr !== 'string')
      return { status: INVALID };
    let mac: string | null = null;
    if (a.mode === 'custom') {
      mac = a.macaddr.toLowerCase().replace(/-/g, ':');
      if (!MAC.test(mac)) return { status: INVALID };
      if (parseInt(mac.slice(0, 2), 16) & 1) return this.rejected('mac_not_unicast');
    } else if (a.mode === 'random') mac = '06:11:22:33:44:55';
    if (a.target === 'repeater') {
      if (this.repeater.ssid === null) return this.rejected('repeater_not_configured');
      this.mac.repeaterCustom = mac;
    } else this.mac.wanCustom = mac;
    return this.ok({ applied: true, macaddr: mac });
  }

  dns = {
    mode: 'auto', servers: [] as string[], provider: 'alidns', url: '', encrypted_available: true, rebind_protection: true,
    hosts: [] as { id: string; name: string; ip: string }[],
  };

  m_dns_rebind_set(a: Args) {
    if (typeof a.enabled !== 'boolean') return { status: INVALID };
    this.dns.rebind_protection = a.enabled;
    return this.ok({ applied: true });
  }

  m_host_set(a: Args) {
    if (typeof a.id !== 'string' || typeof a.name !== 'string' || typeof a.ip !== 'string' || ipToInt(a.ip) === null) return { status: INVALID };
    if (this.dns.hosts.some((h) => h.id !== a.id && h.name.toLowerCase() === (a.name as string).toLowerCase())) return this.rejected('host_exists');
    const id = a.id || `host${this.dns.hosts.length + 1}`;
    const i = this.dns.hosts.findIndex((h) => h.id === a.id);
    if (i >= 0) this.dns.hosts[i] = { id, name: a.name, ip: a.ip };
    else this.dns.hosts.push({ id, name: a.name, ip: a.ip });
    return this.ok({ id });
  }

  m_host_delete(a: Args) {
    const i = this.dns.hosts.findIndex((h) => h.id === a.id);
    if (i < 0) return { status: NOT_FOUND };
    this.dns.hosts.splice(i, 1);
    return this.ok({ deleted: true });
  }

  m_dns_get() {
    return this.ok({ ...structuredClone(this.dns), providers: ['alidns', 'cloudflare', 'google', 'quad9', 'adguard', 'dnspod'] });
  }

  m_dns_set(a: Args) {
    if (!['auto', 'manual', 'encrypted'].includes(a.mode as string) || !Array.isArray(a.servers) ||
        a.servers.some((x) => typeof x !== 'string' || ipToInt(x) === null) || typeof a.provider !== 'string' ||
        typeof a.url !== 'string' || (a.mode === 'manual' && a.servers.length === 0))
      return { status: INVALID };
    if (a.mode === 'encrypted' && !this.dns.encrypted_available) return this.rejected('encrypted_unavailable');
    if (a.mode === 'encrypted' && a.provider === 'custom' && !a.url.startsWith('https://')) return this.rejected('doh_url_invalid');
    Object.assign(this.dns, { mode: a.mode, servers: a.servers });
    if (a.mode === 'encrypted') Object.assign(this.dns, { provider: a.provider, url: a.url });
    return this.ok({ applied: true });
  }

  vpn = {
    profiles: [] as Array<Record<string, unknown> & { id: string; name: string; private_key: string; preshared_key: string }>,
    active: null as string | null,
    kill_switch: false,
    allow_lan: true,
    route_mode: 'all' as 'all' | 'selected',
    devices: [] as string[],
    destinations: [] as string[],
    domains_supported: true,
    // Whether a connected tunnel completes its handshake.
    reachable: true,
  };

  private vpnProfileView(p: (typeof this.vpn.profiles)[number]) {
    if (p.type === 'openvpn') {
      const { config: _c, password: _p, ...rest } = p;
      return rest;
    }
    const { private_key: _pk, preshared_key: psk, ...rest } = p;
    return { ...rest, type: 'wireguard', has_preshared_key: !!psk };
  }

  m_vpn_get() {
    const up = this.vpn.active !== null;
    const now = 1_792_000_000;
    return this.ok({
      profiles: this.vpn.profiles.map((p) => this.vpnProfileView(p)),
      active: this.vpn.active,
      kill_switch: this.vpn.kill_switch,
      allow_lan: this.vpn.allow_lan,
      route_mode: this.vpn.route_mode,
      devices: [...this.vpn.devices],
      destinations: [...this.vpn.destinations],
      domains_supported: this.vpn.domains_supported,
      status: {
        up, connected: up && this.vpn.reachable, addresses: up ? ['10.250.30.2/32'] : [], uptime: up ? 60 : 0,
        endpoint: up ? '203.0.113.5:51820' : null,
        handshake: up && this.vpn.reachable ? now - 20 : 0,
        rx_bytes: up && this.vpn.reachable ? 120_000 : 0, tx_bytes: up ? 30_000 : 0,
      },
      ipv6: !up ? null
        : ((this.vpn.profiles.find((p) => p.id === this.vpn.active)?.addresses as string[] | undefined) ?? []).some((a) => a.includes(':'))
          ? 'tunnel' : 'blocked',
      time: now,
    });
  }

  m_vpn_profile_set(a: Args) {
    const key = /^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw480]=$/;
    if (typeof a.id !== 'string' || typeof a.name !== 'string' || !Array.isArray(a.addresses) || !Array.isArray(a.allowed_ips))
      return { status: INVALID };
    const existing = this.vpn.profiles.find((p) => p.id === a.id);
    if (a.id && !existing) return { status: NOT_FOUND };
    if (!key.test(String(a.public_key))) return this.rejected('profile_invalid', { field: 'public_key' });
    if (!a.id && !key.test(String(a.private_key))) return this.rejected('profile_invalid', { field: 'private_key' });
    const id = existing?.id ?? `cfg${this.vpn.profiles.length + 1}`;
    const next = {
      id, name: a.name, addresses: a.addresses, dns: a.dns, mtu: a.mtu, public_key: a.public_key,
      endpoint_host: a.endpoint_host, endpoint_port: a.endpoint_port, allowed_ips: a.allowed_ips, keepalive: a.keepalive,
      private_key: (a.private_key as string) || existing?.private_key || '',
      preshared_key: a.preshared_key === '-' ? '' : (a.preshared_key as string) || existing?.preshared_key || '',
    };
    if (existing) Object.assign(existing, next);
    else this.vpn.profiles.push(next);
    return this.ok({ id });
  }

  m_vpn_ovpn_set(a: Args) {
    if (typeof a.id !== 'string' || typeof a.name !== 'string' || typeof a.config !== 'string' ||
        typeof a.username !== 'string' || typeof a.password !== 'string')
      return { status: INVALID };
    const existing = this.vpn.profiles.find((p) => p.id === a.id);
    if (a.id && !existing) return { status: NOT_FOUND };
    const unsafe = /^\s*(up|down|script-security|plugin)\b/m.exec(a.config);
    if (unsafe) return this.rejected('ovpn_unsafe', { directive: unsafe[1] });
    const remote = /^\s*remote\s+(\S+)(?:\s+(\d+))?/m.exec(a.config);
    if (!existing && !remote) return this.rejected('profile_invalid', { field: 'config' });
    const id = existing?.id ?? `cfg${this.vpn.profiles.length + 1}`;
    const next = {
      id, type: 'openvpn', name: a.name,
      remote: remote ? (remote[2] ? `${remote[1]}:${remote[2]}` : remote[1]) : existing!.remote,
      config: a.config || (existing?.config as string), username: a.username || (existing?.username as string) || '',
      password: a.password || (existing?.password as string) || '', private_key: '', preshared_key: '',
    };
    if (existing) Object.assign(existing, next);
    else this.vpn.profiles.push(next);
    return this.ok({ id });
  }

  m_vpn_profile_delete(a: Args) {
    const i = this.vpn.profiles.findIndex((p) => p.id === a.id);
    if (i < 0) return { status: NOT_FOUND };
    if (this.vpn.active === a.id) return this.rejected('profile_active');
    this.vpn.profiles.splice(i, 1);
    return this.ok({ deleted: true });
  }

  m_vpn_connect(a: Args) {
    if (!this.vpn.profiles.some((p) => p.id === a.id)) return { status: NOT_FOUND };
    this.vpn.active = a.id as string;
    return this.ok({ applied: true });
  }

  m_vpn_disconnect() {
    this.vpn.active = null;
    return this.ok({ applied: true });
  }

  m_vpn_options(a: Args) {
    if (typeof a.kill_switch !== 'boolean' || typeof a.allow_lan !== 'boolean' || !['all', 'selected'].includes(a.route_mode as string) ||
        !Array.isArray(a.devices) || a.devices.some((d) => typeof d !== 'string' || !MAC.test(d)))
      return { status: INVALID };
    if (!Array.isArray(a.destinations)) return { status: INVALID };
    Object.assign(this.vpn, { kill_switch: a.kill_switch, allow_lan: a.allow_lan, route_mode: a.route_mode, devices: a.devices, destinations: a.destinations });
    return this.ok({ applied: true });
  }


  fw = {
    forwards: [] as Record<string, unknown>[],
    open_ports: [] as Record<string, unknown>[],
    dmz: { enabled: false, ip: '' },
  };

  private portsOverlap(a: string, b: string) {
    const [a1, a2 = a1] = a.split('-').map(Number);
    const [b1, b2 = b1] = b.split('-').map(Number);
    return a1 <= b2 && b1 <= a2;
  }

  m_firewall_get() {
    return this.ok({ ...structuredClone(this.fw), lan: { ipaddr: this.lan.ipaddr, prefix: this.lan.prefix }, offload: this.offload });
  }

  m_forward_set(a: Args) {
    if (typeof a.id !== 'string' || typeof a.name !== 'string' || typeof a.external_port !== 'string' || typeof a.internal_ip !== 'string')
      return { status: INVALID };
    const clash = this.fw.forwards.find((f) => f.id !== a.id && this.portsOverlap(f.external_port as string, a.external_port as string));
    if (clash) return this.rejected('port_in_use');
    const id = a.id || `fwd${this.fw.forwards.length + 1}`;
    const next = { ...a, id };
    const i = this.fw.forwards.findIndex((f) => f.id === a.id);
    if (a.id && i < 0) return { status: NOT_FOUND };
    if (i >= 0) this.fw.forwards[i] = next;
    else this.fw.forwards.push(next);
    return this.ok({ id });
  }

  m_forward_delete(a: Args) {
    const i = this.fw.forwards.findIndex((f) => f.id === a.id);
    if (i < 0) return { status: NOT_FOUND };
    this.fw.forwards.splice(i, 1);
    return this.ok({ deleted: true });
  }

  m_open_port_set(a: Args) {
    if (typeof a.id !== 'string' || typeof a.port !== 'string') return { status: INVALID };
    const id = a.id || `open${this.fw.open_ports.length + 1}`;
    const i = this.fw.open_ports.findIndex((f) => f.id === a.id);
    if (i >= 0) this.fw.open_ports[i] = { ...a, id };
    else this.fw.open_ports.push({ ...a, id });
    return this.ok({ id });
  }

  m_open_port_delete(a: Args) {
    const i = this.fw.open_ports.findIndex((f) => f.id === a.id);
    if (i < 0) return { status: NOT_FOUND };
    this.fw.open_ports.splice(i, 1);
    return this.ok({ deleted: true });
  }

  m_dmz_set(a: Args) {
    if (typeof a.enabled !== 'boolean' || typeof a.ip !== 'string') return { status: INVALID };
    this.fw.dmz = { enabled: a.enabled, ip: a.ip };
    return this.ok({ applied: true });
  }

  wanAccess = { webui: true, ssh: false };

  guard = {
    enabled: true, attempts: 3, window: 30, ban: 120,
    banned: [{ ip: '203.0.113.50', expires: 5400 }] as { ip: string; expires: number | null }[],
  };

  m_guard_get() {
    return this.ok(structuredClone(this.guard));
  }

  m_guard_set(a: Args) {
    const within = (v: unknown, min: number, max: number) => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
    if (typeof a.enabled !== 'boolean' || !within(a.attempts, 1, 20) || !within(a.window, 1, 1440) || !within(a.ban, 1, 10080))
      return { status: INVALID };
    Object.assign(this.guard, { enabled: a.enabled, attempts: a.attempts, window: a.window, ban: a.ban });
    if (!a.enabled) this.guard.banned = [];
    return this.ok({ applied: true });
  }

  m_guard_unban(a: Args) {
    if (typeof a.ip !== 'string') return { status: INVALID };
    const before = this.guard.banned.length;
    this.guard.banned = this.guard.banned.filter((b) => b.ip !== a.ip);
    return before === this.guard.banned.length ? { status: NOT_FOUND } : this.ok({ applied: true });
  }

  m_wan_access_get() {
    return this.ok({ ...this.wanAccess });
  }

  m_wan_access_set(a: Args) {
    if (typeof a.webui !== 'boolean' || typeof a.ssh !== 'boolean') return { status: INVALID };
    this.wanAccess = { webui: a.webui, ssh: a.ssh };
    return this.ok({ applied: true });
  }

  offload = 'off';

  m_offload_set(a: Args) {
    if (!['off', 'software', 'hardware'].includes(a.mode as string)) return { status: INVALID };
    this.offload = a.mode as string;
    return this.ok({ applied: true });
  }

  schedules = {
    reboot: { enabled: false, days: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'], start: '04:00', end: '07:00' },
    wifi_off: { enabled: false, days: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'], start: '23:00', end: '07:00' },
    parental: [] as Record<string, unknown>[],
  };

  m_schedule_get() {
    return this.ok(structuredClone(this.schedules));
  }

  m_schedule_set(a: Args) {
    const time = /^([01]\d|2[0-3]):[0-5]\d$/;
    if (!['reboot', 'wifi_off'].includes(a.kind as string) || typeof a.enabled !== 'boolean' || !Array.isArray(a.days) ||
        !a.days.length || !time.test(String(a.start)))
      return { status: INVALID };
    const kind = a.kind as 'reboot' | 'wifi_off';
    this.schedules[kind] = { enabled: a.enabled, days: a.days as string[], start: a.start as string, end: (a.end as string) || this.schedules[kind].end };
    return this.ok({ applied: true });
  }

  m_parental_set(a: Args) {
    if (typeof a.id !== 'string' || typeof a.name !== 'string' || !Array.isArray(a.macs) || !a.macs.length || !Array.isArray(a.days) ||
        !a.days.length || a.start === a.end)
      return { status: INVALID };
    const id = a.id || `sc_parental_${this.schedules.parental.length + 1}`;
    const i = this.schedules.parental.findIndex((r) => r.id === a.id);
    if (a.id && i < 0) return { status: NOT_FOUND };
    if (i >= 0) this.schedules.parental[i] = { ...a, id };
    else this.schedules.parental.push({ ...a, id });
    return this.ok({ id });
  }

  m_parental_delete(a: Args) {
    const i = this.schedules.parental.findIndex((r) => r.id === a.id);
    if (i < 0) return { status: NOT_FOUND };
    this.schedules.parental.splice(i, 1);
    return this.ok({ deleted: true });
  }

  ddns = { enabled: false, service: '', domain: '', username: '', password: '' };

  m_ddns_get() {
    const { password, ...d } = this.ddns;
    return this.ok({
      ...d, has_password: !!password, available: true, services: ['cloudflare.com-v4', 'dnspod.cn-v3', 'duckdns.org'],
      last_update: this.ddns.enabled ? 1_792_000_000 : 0, ip: this.ddns.enabled ? '203.0.113.7' : null,
    });
  }

  m_ddns_set(a: Args) {
    if (typeof a.enabled !== 'boolean' || typeof a.domain !== 'string' || typeof a.password !== 'string') return { status: INVALID };
    if (a.enabled && !a.password && !this.ddns.password) return this.rejected('ddns_password_missing');
    Object.assign(this.ddns, { enabled: a.enabled, service: a.service, domain: a.domain, username: a.username, password: (a.password as string) || this.ddns.password });
    return this.ok({ applied: true });
  }

  netmode = { mode: 'router' as 'router' | 'ap', saved: null as null | { ipaddr: string } };

  m_netmode_get() {
    return this.ok({
      mode: this.netmode.mode,
      lan: { ipaddr: this.lan.ipaddr, netmask: '255.255.255.0', gateway: this.netmode.mode === 'ap' ? '10.0.0.1' : null },
      upstream: this.wan.carrier && this.netmode.mode === 'router' ? { ipaddr: '10.0.0.15', prefix: 24, gateway: '10.0.0.1', dns: ['10.0.0.1'] } : null,
    });
  }

  m_netmode_set(a: Args) {
    if (!['router', 'ap'].includes(a.mode as string)) return { status: INVALID };
    if (a.mode === 'ap') {
      if (this.wanAsLan) return this.rejected('wan_as_lan_on');
      if (ipToInt(String(a.ipaddr)) === null || ipToInt(String(a.gateway)) === null) return this.rejected('invalid_address');
      this.netmode = { mode: 'ap', saved: { ipaddr: this.lan.ipaddr } };
      this.lan.ipaddr = a.ipaddr as string;
    } else if (this.netmode.saved) {
      this.lan.ipaddr = this.netmode.saved.ipaddr;
      this.netmode = { mode: 'router', saved: null };
    }
    return this.ok({ applied: true });
  }

  adguard = {
    installed: true, enabled: true, protection: true, fallback: false, locked: false,
    filters: [{ name: 'AdGuard DNS filter', url: AG_LIST_1, enabled: true, rules: 185651 as number | null }],
    rules: [] as string[],
    web: { enabled: false, user: 'root' as string | null, port: 3000, synced: false },
    webHash: null as string | null,
    logging: { statistics: false, querylog: false },
  };

  m_adguard_get() {
    const a = this.adguard;
    const up = a.enabled && !a.fallback && !a.locked;
    return this.ok({
      installed: a.installed, enabled: a.enabled, running: up, fallback: a.fallback, locked: a.locked,
      protection: up ? a.protection : null,
      filters: up ? structuredClone(a.filters) : null,
      suggested: AG_CATALOG.filter((c) => !a.filters.some((f) => f.url === c.url)),
      rules: up ? [...a.rules] : null,
      web: { ...a.web },
      logging: up ? { ...a.logging } : null,
      stats: up ? {
        queries: 12345, blocked: 1234, avg_ms: 7,
        top_blocked: [{ name: 'ads.example.com', count: 420 }, { name: 'tracker.example.net', count: 99 }],
        top_clients: [{ name: '192.168.200.110', count: 5000 }],
      } : null,
    });
  }

  m_adguard_set(a: Args) {
    if (typeof a.enabled !== 'boolean') return { status: INVALID };
    this.adguard.enabled = a.enabled;
    return this.ok({ applied: true });
  }

  private agReady() {
    return this.adguard.enabled && !this.adguard.fallback && !this.adguard.locked;
  }

  m_adguard_protection(a: Args) {
    if (typeof a.enabled !== 'boolean') return { status: INVALID };
    if (!this.agReady()) return this.rejected('adguard_not_running');
    this.adguard.protection = a.enabled;
    return this.ok({ applied: true });
  }

  m_adguard_list_add(a: Args) {
    if (typeof a.url !== 'string' || !/^https?:\/\/[A-Za-z0-9.-]+(:\d+)?\/[!-~]*$/.test(a.url))
      return this.rejected('filter_url_invalid', { value: String(a.url) });
    if (typeof a.name !== 'string' || !a.name) return { status: INVALID };
    if (!this.agReady()) return this.rejected('adguard_not_running');
    if (this.adguard.filters.some((f) => f.url === a.url) || a.url.includes('unreachable')) return this.rejected('adguard_refused');
    this.adguard.filters.push({ name: a.name, url: a.url, enabled: true, rules: 100 });
    return this.ok({ applied: true });
  }

  m_adguard_list_set(a: Args) {
    if (typeof a.url !== 'string' || typeof a.name !== 'string' || typeof a.enabled !== 'boolean') return { status: INVALID };
    if (!this.agReady()) return this.rejected('adguard_not_running');
    const f = this.adguard.filters.find((x) => x.url === a.url);
    if (!f) return this.rejected('adguard_refused');
    Object.assign(f, { name: a.name, enabled: a.enabled });
    return this.ok({ applied: true });
  }

  m_adguard_list_remove(a: Args) {
    if (typeof a.url !== 'string') return { status: INVALID };
    if (!this.agReady()) return this.rejected('adguard_not_running');
    const before = this.adguard.filters.length;
    this.adguard.filters = this.adguard.filters.filter((f) => f.url !== a.url);
    return before === this.adguard.filters.length ? this.rejected('adguard_refused') : this.ok({ applied: true });
  }

  m_adguard_logging_set(a: Args) {
    if (typeof a.statistics !== 'boolean' || typeof a.querylog !== 'boolean') return { status: INVALID };
    if (!this.agReady()) return this.rejected('adguard_not_running');
    this.adguard.logging = { statistics: a.statistics, querylog: a.querylog };
    return this.ok({ applied: true });
  }

  m_adguard_rules_set(a: Args) {
    if (!Array.isArray(a.rules)) return { status: INVALID };
    const bad = (a.rules as string[]).find((r) => typeof r !== 'string' || !r || /[\n\r]/.test(r));
    if (bad !== undefined) return this.rejected('rule_invalid', { value: String(bad) });
    if (!this.agReady()) return this.rejected('adguard_not_running');
    this.adguard.rules = [...(a.rules as string[])];
    return this.ok({ applied: true });
  }

  m_adguard_web_set(a: Args) {
    if (typeof a.enabled !== 'boolean' || typeof a.password !== 'string' || typeof a.hash !== 'string') return { status: INVALID };
    if (a.password && (a.password.length < 8 || !BCRYPT.test(a.hash))) return { status: INVALID };
    if (!this.adguard.enabled) return this.rejected('adguard_not_running');
    if (a.password) {
      if (a.password !== this.password) return this.rejected('password_mismatch_test');
      this.adguard.webHash = a.hash;
      this.adguard.web.synced = true;
    } else if (a.enabled && !this.adguard.web.synced) {
      return this.rejected('password_needed');
    }
    this.adguard.web.enabled = a.enabled;
    return this.ok({ applied: true });
  }


  tailscale = {
    installed: true, enabled: false, share_lan: false, signedIn: false,
    loginUrl: 'https://login.tailscale.com/a/abc123',
  };

  m_tailscale_get() {
    const ts = this.tailscale;
    const running = ts.enabled && ts.signedIn;
    return this.ok({
      installed: ts.installed, enabled: ts.enabled, share_lan: ts.share_lan,
      state: !ts.enabled ? null : running ? 'Running' : 'NeedsLogin',
      login_url: ts.enabled && !ts.signedIn ? ts.loginUrl : null,
      addresses: running ? ['100.101.102.103', 'fd7a:115c:a1e0::1'] : [],
      name: running ? 'supacudy' : null,
      tailnet: running ? 'example.ts.net' : null,
      lan: '192.168.200.0/24',
    });
  }

  m_tailscale_set(a: Args) {
    if (typeof a.enabled !== 'boolean' || typeof a.share_lan !== 'boolean') return { status: INVALID };
    if (a.enabled && !this.tailscale.installed) return this.rejected('tailscale_missing');
    Object.assign(this.tailscale, { enabled: a.enabled, share_lan: a.share_lan });
    return this.ok({ applied: true });
  }

  m_tailscale_logout() {
    if (!this.tailscale.enabled) return this.rejected('tailscale_not_running');
    this.tailscale.signedIn = false;
    return this.ok({ applied: true });
  }

  uplinks = {
    order: ['wired', 'repeater', 'tethering'] as string[],
    reset_connections: true,
    targets4: ['223.5.5.5', '1.1.1.1', '8.8.8.8'],
    targets6: ['2400:3200::1', '2606:4700:4700::1111', '2001:4860:4860::8888'],
    watching: true,
    active_v4: 'wired' as string | null,
    active_v6: 'wired' as string | null,
  };

  m_uplinks_get() {
    const u = this.uplinks;
    const fam = (connected: boolean, online: boolean) => ({ connected, online, checked: connected ? 1_792_000_000 : null });
    return this.ok({
      ...structuredClone(u),
      online_v4: u.watching ? u.active_v4 !== null : null,
      online_v6: u.watching ? u.active_v6 !== null : null,
      uplinks: u.order.map((name) => ({
        name,
        configured: name !== 'repeater',
        v4: name === 'repeater' ? fam(false, false) : fam(true, name === u.active_v4 || name === 'tethering'),
        v6: name === 'wired' ? fam(true, u.active_v6 === 'wired') : fam(name === 'tethering', name === 'tethering'),
      })),
    });
  }

  m_uplinks_set(a: Args) {
    const names = ['wired', 'repeater', 'tethering'];
    if (!Array.isArray(a.order) || a.order.length !== 3 || !names.every((n) => (a.order as string[]).includes(n)) ||
        typeof a.reset_connections !== 'boolean')
      return { status: INVALID };
    const v4 = /^(\d{1,3}\.){3}\d{1,3}$/;
    if (!Array.isArray(a.targets4) || !a.targets4.length || !(a.targets4 as string[]).every((t) => v4.test(t)))
      return this.rejected('target_invalid', { family: 'ipv4' });
    if (!Array.isArray(a.targets6) || !a.targets6.length || !(a.targets6 as string[]).every((t) => t.includes(':')))
      return this.rejected('target_invalid', { family: 'ipv6' });
    Object.assign(this.uplinks, {
      order: a.order, reset_connections: a.reset_connections, targets4: a.targets4, targets6: a.targets6,
    });
    return this.ok({ applied: true });
  }
}
