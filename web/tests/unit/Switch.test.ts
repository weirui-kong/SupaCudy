// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/svelte';
import Switch from '../../src/components/Switch.svelte';

describe('Switch', () => {
  it('moves back when the parent keeps its value', async () => {
    const onchange = vi.fn(async () => {});
    render(Switch, { label: 'Feature', checked: false, onchange });
    const input = screen.getByRole('switch') as HTMLInputElement;
    await fireEvent.click(input);
    expect(onchange).toHaveBeenCalledWith(true);
    await vi.waitFor(() => expect(input.checked).toBe(false));
  });

  it('keeps the new position once the parent takes it', async () => {
    const view = render(Switch, { label: 'Feature', checked: false, onchange: async () => {} });
    const input = screen.getByRole('switch') as HTMLInputElement;
    await view.rerender({ label: 'Feature', checked: true, onchange: async () => {} });
    expect(input.checked).toBe(true);
  });

  it('shows the new position while the change is being applied', async () => {
    let finish = () => {};
    render(Switch, { label: 'Feature', checked: false, onchange: () => new Promise<void>((r) => (finish = r)) });
    const input = screen.getByRole('switch') as HTMLInputElement;
    await fireEvent.click(input);
    expect(input.checked).toBe(true);
    finish();
    await vi.waitFor(() => expect(input.checked).toBe(false));
  });

  it('without a handler it simply toggles', async () => {
    render(Switch, { label: 'Feature', checked: false });
    const input = screen.getByRole('switch') as HTMLInputElement;
    await fireEvent.click(input);
    expect(input.checked).toBe(true);
  });
});
