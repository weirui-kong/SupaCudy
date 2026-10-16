// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// The only module that talks to the router. Components call the typed
// functions at the bottom, never fetch() or JSON-RPC directly.

export type ApiErrorCode = 'denied' | 'invalid' | 'not_found' | 'network' | 'unknown';

export class ApiError extends Error {
  readonly code: ApiErrorCode;
  readonly status: number | null;

  constructor(code: ApiErrorCode, status: number | null = null) {
    super(code);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
  }
}

const ANONYMOUS_SESSION = '00000000000000000000000000000000';
const SESSION_KEY = 'supacudy.session';
const ENDPOINT = '/ubus';

// ubus status codes (libubus UBUS_STATUS_*) that the UI distinguishes.
const UBUS_INVALID_ARGUMENT = 2;
const UBUS_NOT_FOUND = 4;
const UBUS_PERMISSION_DENIED = 6;
// rpcd answers with this JSON-RPC error when the session lacks the ACL.
const JSONRPC_ACCESS_DENIED = -32002;

let sessionId: string | null = readSession();
const expiredListeners = new Set<() => void>();
let requestId = 0;

function readSession(): string | null {
  try {
    return sessionStorage.getItem(SESSION_KEY);
  } catch {
    return null;
  }
}

function storeSession(id: string | null): void {
  sessionId = id;
  try {
    if (id) sessionStorage.setItem(SESSION_KEY, id);
    else sessionStorage.removeItem(SESSION_KEY);
  } catch {
    // Private mode: the session then only lives in memory.
  }
}

export function hasSession(): boolean {
  return sessionId !== null;
}

export function onSessionExpired(listener: () => void): () => void {
  expiredListeners.add(listener);
  return () => expiredListeners.delete(listener);
}

function expire(): void {
  storeSession(null);
  for (const listener of expiredListeners) listener();
}

async function call<T>(object: string, method: string, args: object = {}, anonymous = false): Promise<T> {
  const session = anonymous ? ANONYMOUS_SESSION : sessionId;
  if (!session) throw new ApiError('denied');

  let body: { result?: [number, T?]; error?: { code: number } };
  try {
    const response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: ++requestId,
        method: 'call',
        params: [session, object, method, args],
      }),
    });
    body = await response.json();
  } catch {
    throw new ApiError('network');
  }

  if (body.error) {
    if (body.error.code === JSONRPC_ACCESS_DENIED) {
      if (!anonymous) expire();
      throw new ApiError('denied');
    }
    throw new ApiError('unknown', body.error.code);
  }

  const [status, data] = body.result ?? [-1];
  switch (status) {
    case 0:
      return (data ?? {}) as T;
    case UBUS_PERMISSION_DENIED:
      if (!anonymous) expire();
      throw new ApiError('denied', status);
    case UBUS_INVALID_ARGUMENT:
      throw new ApiError('invalid', status);
    case UBUS_NOT_FOUND:
      throw new ApiError('not_found', status);
    default:
      throw new ApiError('unknown', status);
  }
}

export async function login(password: string): Promise<void> {
  const result = await call<{ ubus_rpc_session?: string }>(
    'session', 'login', { username: 'root', password }, true,
  );
  if (!result.ubus_rpc_session) throw new ApiError('unknown');
  storeSession(result.ubus_rpc_session);
}

export async function logout(): Promise<void> {
  if (!sessionId) return;
  try {
    // rpcd fills in the caller's own session id, so no arguments are needed.
    await call('session', 'destroy');
  } catch {
    // A failed remote cleanup only means the server-side session times out
    // on its own.
  } finally {
    storeSession(null);
  }
}

export interface DeviceInfo {
  version: string | null;
  openwrt: string | null;
  revision: string | null;
  board: string | null;
  model: string | null;
}

export interface SystemStatus {
  uptime: number;
  load: [number, number, number];
  cpus: number;
  memory: { total: number; available: number };
}

export const getDeviceInfo = () => call<DeviceInfo>('supacudy', 'info');
export const getSystemStatus = () => call<SystemStatus>('supacudy', 'status');
