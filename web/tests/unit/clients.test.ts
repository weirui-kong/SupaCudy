// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { clientLabel, type Client, type ClientList } from '../../src/lib/api';
import { clientIcon, rates, samples, sortClients } from '../../src/lib/clients';

function client(overrides: Partial<Client>): Client {
  return {
    mac: '02:00:00:00:00:01', ip: '192.168.1.10', hostname: null, name: null, type: null, online: true,
    connection: 'wired', band: null, network: 'lan', signal: null, random_mac: false, blocked: false,
    up_limit: 0, down_limit: 0, tx_bytes: 0, rx_bytes: 0, reserved_ip: null,
    ...overrides,
  };
}

const list = (time: number, clients: Client[]): ClientList => ({ time, clients });

describe('clientLabel', () => {
  it('prefers the custom name, then the hostname, then the MAC', () => {
    expect(clientLabel(client({ name: 'Office', hostname: 'pc' }))).toBe('Office');
    expect(clientLabel(client({ hostname: 'pc' }))).toBe('pc');
    expect(clientLabel(client({ mac: 'aa:bb:cc:dd:ee:ff' }))).toBe('AA:BB:CC:DD:EE:FF');
  });
});

describe('clientIcon', () => {
  it('uses the chosen type', () => {
    expect(clientIcon({ type: 'tv', connection: 'wifi' })).toBe('tv');
    expect(clientIcon({ type: 'gateway', connection: 'wired' })).toBe('router');
  });

  it('guesses from the connection when no type is set', () => {
    expect(clientIcon({ type: null, connection: 'wifi' })).toBe('phone');
    expect(clientIcon({ type: null, connection: 'wired' })).toBe('desktop');
    expect(clientIcon({ type: null, connection: null })).toBe('desktop');
  });
});

describe('rates', () => {
  const a = { mac: 'aa:aa:aa:aa:aa:aa' };

  it('derives bytes per second from two samples', () => {
    const first = samples(list(100, [client({ ...a, tx_bytes: 1000, rx_bytes: 5000 })]));
    const speeds = rates(first, list(104, [client({ ...a, tx_bytes: 3000, rx_bytes: 13000 })]));
    expect(speeds.get(a.mac)).toEqual({ up: 500, down: 2000 });
  });

  it('gives no rate without a previous sample', () => {
    expect(rates(new Map(), list(100, [client(a)])).has(a.mac)).toBe(false);
  });

  it('gives no rate when the counters went backwards (reset or reboot)', () => {
    const first = samples(list(100, [client({ ...a, tx_bytes: 9000, rx_bytes: 9000 })]));
    expect(rates(first, list(103, [client({ ...a, tx_bytes: 10, rx_bytes: 10 })])).has(a.mac)).toBe(false);
  });

  it('gives no rate when no time has passed', () => {
    const first = samples(list(100, [client({ ...a, tx_bytes: 1 })]));
    expect(rates(first, list(100, [client({ ...a, tx_bytes: 2 })])).has(a.mac)).toBe(false);
  });
});

describe('sortClients', () => {
  const clients = [
    client({ mac: '01', name: 'beta', ip: '192.168.1.20' }),
    client({ mac: '02', name: 'Alpha', ip: '192.168.1.3' }),
    client({ mac: '03', hostname: 'gamma', ip: null }),
  ];
  const speeds = new Map([['01', { up: 10, down: 900 }], ['02', { up: 50, down: 100 }]]);

  it('sorts by name case-insensitively', () => {
    expect(sortClients(clients, 'name', speeds, 'en').map((c) => c.mac)).toEqual(['02', '01', '03']);
  });

  it('sorts by IP numerically, unknown addresses last', () => {
    expect(sortClients(clients, 'ip', speeds, 'en').map((c) => c.mac)).toEqual(['02', '01', '03']);
  });

  it('sorts by speed, fastest first', () => {
    expect(sortClients(clients, 'upload', speeds, 'en').map((c) => c.mac)).toEqual(['02', '01', '03']);
    expect(sortClients(clients, 'download', speeds, 'en').map((c) => c.mac)).toEqual(['01', '02', '03']);
  });

  it('does not modify the input', () => {
    const copy = [...clients];
    sortClients(clients, 'ip', speeds, 'en');
    expect(clients).toEqual(copy);
  });
});
