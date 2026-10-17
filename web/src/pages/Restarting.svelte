<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Icon from '../components/Icon.svelte';
  import { routerReachable } from '../lib/api';
  import { t } from '../lib/i18n/index.svelte';
  import type { RestartKind } from '../lib/restart.svelte';

  let {
    kind,
    ondone,
    graceMs = 20_000,
    pollMs = 3000,
    giveUpMs = 300_000,
  }: { kind: RestartKind; ondone: () => void; graceMs?: number; pollMs?: number; giveUpMs?: number } = $props();

  let back = $state(false);
  let slow = $state(false);

  $effect(() => {
    const started = Date.now();
    let timer: ReturnType<typeof setTimeout>;
    // The router keeps answering for a moment before it goes down, so only
    // start asking once it has had time to stop.
    const poll = async () => {
      if (Date.now() - started >= graceMs && (await routerReachable())) {
        back = true;
        return;
      }
      if (Date.now() - started > giveUpMs) slow = true;
      timer = setTimeout(poll, pollMs);
    };
    timer = setTimeout(poll, Math.min(graceMs, pollMs));
    return () => clearTimeout(timer);
  });
</script>

<main class="screen" id="main">
  <div class="panel" role="status" aria-live="polite">
    {#if back}
      <Icon name="check" size={40} />
      <h1>{t('restart.back')}</h1>
      <p>{t('restart.back_hint')}</p>
      <Button variant="primary" onclick={ondone}>{t('login.submit')}</Button>
    {:else}
      <span class="spinner" aria-hidden="true"></span>
      <h1>{t(`restart.title_${kind}`)}</h1>
      <p>{t(`restart.hint_${kind}`)}</p>
      {#if kind === 'upgrade'}
        <Banner kind="warning">{t('restart.keep_power')}</Banner>
      {/if}
      {#if kind === 'reset' || slow}
        <Banner kind="info">{t('restart.reconnect')}</Banner>
      {/if}
    {/if}
  </div>
</main>

<style>
  .screen {
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: var(--space-4);
    background: var(--color-bg);
  }

  .panel {
    max-width: 440px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-4);
    padding: var(--space-6) var(--space-5);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    background: var(--color-surface);
    text-align: center;
  }

  .panel > :global(svg) {
    color: var(--color-success);
  }

  h1 {
    font-size: var(--font-size-lg);
  }

  p {
    color: var(--color-text-muted);
  }

  .spinner {
    width: 40px;
    height: 40px;
    border: 4px solid var(--color-accent-soft);
    border-top-color: var(--color-accent);
    border-radius: 50%;
    animation: spin 1s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .spinner {
      animation-duration: 3s;
    }
  }
</style>
