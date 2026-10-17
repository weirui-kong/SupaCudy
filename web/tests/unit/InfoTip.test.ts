// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/svelte';
import InfoTip from '../../src/components/InfoTip.svelte';

function at(element: HTMLElement, top: number) {
  element.getBoundingClientRect = () => ({ top, bottom: top + 20, left: 10, right: 30, width: 20, height: 20, x: 10, y: top, toJSON: () => ({}) });
}

describe('InfoTip', () => {
  it('stays open and follows its trigger while it is on screen', async () => {
    render(InfoTip, { text: 'Helpful' });
    const trigger = screen.getByRole('button');
    at(trigger, 100);
    await fireEvent.click(trigger);
    expect(trigger.getAttribute('aria-expanded')).toBe('true');

    at(trigger, 40);
    await fireEvent.scroll(window);
    expect(trigger.getAttribute('aria-expanded')).toBe('true');
  });

  it('closes once scrolling moves the trigger off screen', async () => {
    render(InfoTip, { text: 'Helpful' });
    const trigger = screen.getByRole('button');
    at(trigger, 100);
    await fireEvent.click(trigger);

    at(trigger, -50);
    await fireEvent.scroll(window);
    expect(trigger.getAttribute('aria-expanded')).toBe('false');
  });

  it('closes with Escape', async () => {
    render(InfoTip, { text: 'Helpful' });
    const trigger = screen.getByRole('button');
    await fireEvent.click(trigger);
    await fireEvent.keyDown(trigger, { key: 'Escape' });
    expect(trigger.getAttribute('aria-expanded')).toBe('false');
  });
});
