// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// The only code that talks to the router. Components import the typed
// functions from lib/api (index.ts), never fetch() or JSON-RPC directly.

export type ApiErrorCode = 'denied' | 'invalid' | 'not_found' | 'network' | 'rejected' | 'unknown';

export class ApiError extends Error {
  readonly code: ApiErrorCode;
  readonly status: number | null;
  // For 'rejected': the router's reason code and any details it sent.
  readonly reason: string | null;
  readonly details: Record<string, unknown>;

  constructor(code: ApiErrorCode, status: number | null = null, reason: string | null = null, details: Record<string, unknown> = {}) {
    super(reason ?? code);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
    this.reason = reason;
    this.details = details;
  }
}

const ANONYMOUS_SESSION = '00000000000000000000000000000000';
const SESSION_KEY = 'supacudy.session';
const ENDPOINT = '/ubus';
const UPLOAD_ENDPOINT = '/cgi-bin/cgi-upload';
const WHOAMI_ENDPOINT = '/cgi-bin/supacudy-whoami';

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

export async function call<T>(object: string, method: string, args: object = {}, anonymous = false): Promise<T> {
  return callAs<T>(anonymous ? ANONYMOUS_SESSION : sessionId, object, method, args);
}

async function callAs<T>(session: string | null, object: string, method: string, args: object): Promise<T> {
  const anonymous = session === ANONYMOUS_SESSION;
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
    case 0: {
      // The router refused a well-formed request; see util.uc on the router.
      const reply = (data ?? {}) as Record<string, unknown>;
      if (typeof reply.error === 'string') {
        const { error, ...details } = reply;
        throw new ApiError('rejected', null, error, details);
      }
      return reply as T;
    }
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

// Checks a password without touching the current session: the router
// cannot verify it itself (no crypt in ucode), so log in once and drop it.
export async function verifyPassword(password: string): Promise<boolean> {
  let result: { ubus_rpc_session?: string };
  try {
    result = await call('session', 'login', { username: 'root', password }, true);
  } catch (err) {
    if (err instanceof ApiError && err.code === 'denied') return false;
    throw err;
  }
  if (result.ubus_rpc_session) await callAs(result.ubus_rpc_session, 'session', 'destroy', {}).catch(() => {});
  return true;
}

// True once the router answers again, e.g. after a reboot.
export async function routerReachable(): Promise<boolean> {
  try {
    await call('session', 'access', {}, true);
    return true;
  } catch (err) {
    return !(err instanceof ApiError && err.code === 'network');
  }
}

// Uploads go through LuCI's cgi-io, which checks the session's "file" ACL.
export function uploadFile(path: string, file: Blob, onprogress?: (fraction: number) => void): Promise<void> {
  return new Promise((resolve, reject) => {
    if (!sessionId) return reject(new ApiError('denied'));
    const form = new FormData();
    form.append('sessionid', sessionId);
    form.append('filename', path);
    form.append('filemode', '0600');
    form.append('filedata', file);
    const xhr = new XMLHttpRequest();
    xhr.open('POST', UPLOAD_ENDPOINT);
    xhr.upload.onprogress = (e) => e.lengthComputable && onprogress?.(e.loaded / e.total);
    // cgi-io reports refusals as HTTP 200 with {message, failure}; only a
    // reply carrying the stored size is a completed upload.
    xhr.onload = () => {
      let reply: { size?: number; message?: string } = {};
      try {
        reply = JSON.parse(xhr.responseText);
      } catch {
        // Not JSON: handled below by the missing size.
      }
      if (xhr.status === 200 && typeof reply.size === 'number') resolve();
      else if (xhr.status === 403 || reply.message === 'Upload permission denied') {
        expire();
        reject(new ApiError('denied', xhr.status));
      } else reject(new ApiError('unknown', xhr.status));
    };
    xhr.onerror = () => reject(new ApiError('network'));
    xhr.send(form);
  });
}

// The address this browser reaches the router from, or null if unknown.
export async function callerAddress(): Promise<string | null> {
  try {
    const reply = await (await fetch(WHOAMI_ENDPOINT, { cache: 'no-store' })).json();
    return typeof reply.ip === 'string' ? reply.ip : null;
  } catch {
    return null;
  }
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

export const supacudy = <T>(method: string, args: object = {}) => call<T>('supacudy', method, args);
