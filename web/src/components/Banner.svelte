<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon from './Icon.svelte';

  type Kind = 'info' | 'warning' | 'error' | 'success';

  let { kind = 'info', children }: { kind?: Kind; children: Snippet } = $props();

  const ICONS = { info: 'info', warning: 'warning', error: 'error', success: 'check' } as const;
</script>

<!-- Errors are announced immediately; the rest politely. -->
<div class="banner {kind}" role={kind === 'error' ? 'alert' : 'status'}>
  <span class="icon"><Icon name={ICONS[kind]} /></span>
  <div class="text">{@render children()}</div>
</div>

<style>
  .banner {
    display: flex;
    gap: var(--space-3);
    align-items: flex-start;
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-md);
    font-size: var(--font-size-sm);
    color: var(--color-text);
  }

  .icon {
    flex: none;
    display: flex;
    padding-top: 1px;
  }

  .text {
    min-width: 0;
  }

  .info {
    background: var(--color-info-soft);
  }

  .info .icon {
    color: var(--color-accent);
  }

  .warning {
    background: var(--color-warning-soft);
  }

  .warning .icon {
    color: var(--color-warning);
  }

  .error {
    background: var(--color-danger-soft);
  }

  .error .icon {
    color: var(--color-danger);
  }

  .success {
    background: var(--color-success-soft);
  }

  .success .icon {
    color: var(--color-success);
  }
</style>
