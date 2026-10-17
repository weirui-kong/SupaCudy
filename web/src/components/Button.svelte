<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon, { type IconName } from './Icon.svelte';

  type Variant = 'primary' | 'secondary' | 'danger' | 'ghost';

  let {
    variant = 'secondary',
    type = 'button',
    form,
    icon,
    busy = false,
    disabled = false,
    label,
    onclick,
    children,
  }: {
    variant?: Variant;
    type?: 'button' | 'submit';
    /** Submits a form outside the button, e.g. from a dialog footer. */
    form?: string;
    icon?: IconName;
    busy?: boolean;
    disabled?: boolean;
    /** Accessible name for icon-only buttons. */
    label?: string;
    onclick?: (event: MouseEvent) => void;
    children?: Snippet;
  } = $props();
</script>

<button
  {type}
  {form}
  class="button {variant}"
  class:icon-only={!children}
  disabled={disabled || busy}
  aria-busy={busy || undefined}
  aria-label={label}
  title={!children ? label : undefined}
  {onclick}
>
  {#if busy}
    <span class="spinner" aria-hidden="true"></span>
  {:else if icon}
    <Icon name={icon} size={18} />
  {/if}
  {#if children}<span>{@render children()}</span>{/if}
</button>

<style>
  .button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    min-height: var(--touch-target);
    min-width: var(--touch-target);
    padding: 0 var(--space-4);
    border: 1px solid transparent;
    border-radius: var(--radius-md);
    font-weight: 600;
    font-size: var(--font-size-sm);
    cursor: pointer;
    white-space: nowrap;
  }

  .button.icon-only {
    padding: 0;
  }

  .button:disabled {
    cursor: not-allowed;
    opacity: 0.6;
  }

  .button[aria-busy] {
    cursor: progress;
  }

  .primary {
    background: var(--color-accent);
    color: var(--color-on-accent);
  }

  .primary:hover:not(:disabled) {
    background: var(--color-accent-hover);
  }

  .secondary {
    background: var(--color-surface);
    border-color: var(--color-border);
    color: var(--color-text);
  }

  .secondary:hover:not(:disabled),
  .ghost:hover:not(:disabled) {
    background: var(--color-surface-muted);
  }

  .danger {
    background: var(--color-danger);
    color: var(--color-on-danger);
  }

  .ghost {
    background: none;
    color: var(--color-text-muted);
  }

  .spinner {
    width: 16px;
    height: 16px;
    border: 2px solid currentColor;
    border-right-color: transparent;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
