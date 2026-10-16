// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/svelte';
import Login from '../../src/pages/Login.svelte';
import * as api from '../../src/lib/api';
import { setLocale } from '../../src/lib/i18n/index.svelte';

vi.mock('../../src/lib/api', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../src/lib/api')>()),
  login: vi.fn(),
}));

const login = vi.mocked(api.login);

async function submit(password: string) {
  await fireEvent.input(screen.getByLabelText('Admin password'), { target: { value: password } });
  await fireEvent.click(screen.getByRole('button', { name: 'Log in' }));
}

describe('Login page', () => {
  beforeEach(() => {
    setLocale('en');
    login.mockReset();
  });

  it('logs in and reports success to the parent', async () => {
    login.mockResolvedValue();
    const onlogin = vi.fn();
    render(Login, { onlogin });

    await submit('secret');

    expect(login).toHaveBeenCalledWith('secret');
    expect(onlogin).toHaveBeenCalledOnce();
  });

  it('shows a wrong-password message and marks the field invalid', async () => {
    login.mockRejectedValue(new api.ApiError('denied', 6));
    const onlogin = vi.fn();
    render(Login, { onlogin });

    await submit('nope');

    expect(await screen.findByRole('alert')).toHaveProperty('textContent', expect.stringContaining('Wrong password'));
    expect(screen.getByLabelText('Admin password').getAttribute('aria-invalid')).toBe('true');
    expect(onlogin).not.toHaveBeenCalled();
  });

  it('explains a network failure differently from a wrong password', async () => {
    login.mockRejectedValue(new api.ApiError('network'));
    render(Login, { onlogin: vi.fn() });

    await submit('secret');

    const alert = await screen.findByRole('alert');
    expect(alert.textContent).toContain('Cannot reach the router');
    expect(alert.textContent).not.toContain('Wrong password');
  });

  it('disables the form while logging in', async () => {
    let finish!: () => void;
    login.mockReturnValue(new Promise<void>((resolve) => (finish = resolve)));
    render(Login, { onlogin: vi.fn() });

    await submit('secret');

    expect(screen.getByRole('button', { name: 'Logging in…' })).toHaveProperty('disabled', true);
    finish();
  });

  it('toggles password visibility', async () => {
    render(Login, { onlogin: vi.fn() });
    const input = screen.getByLabelText('Admin password') as HTMLInputElement;
    expect(input.type).toBe('password');

    await fireEvent.click(screen.getByRole('button', { name: 'Show password' }));
    expect(input.type).toBe('text');

    await fireEvent.click(screen.getByRole('button', { name: 'Hide password' }));
    expect(input.type).toBe('password');
  });

  it('shows why the user was sent back to the login page', () => {
    render(Login, { onlogin: vi.fn(), notice: 'Your session has expired. Please log in again.' });
    expect(screen.getByRole('status').textContent).toContain('session has expired');
  });

  it('renders in Chinese', () => {
    setLocale('zh-CN');
    render(Login, { onlogin: vi.fn() });
    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('登录');
    expect(screen.getByLabelText('管理密码')).toBeTruthy();
  });
});
