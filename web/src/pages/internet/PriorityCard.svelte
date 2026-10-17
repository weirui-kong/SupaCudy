<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import Icon, { type IconName } from '../../components/Icon.svelte';
  import Switch from '../../components/Switch.svelte';
  import {
    badTarget, getUplinks, lines, moveUplink, setUplinks, TARGETS_MAX,
    type Uplink, type UplinkName, type UplinkSettings, type UplinksState,
  } from '../../lib/api';
  import { errorMessage } from '../../lib/errors';
  import { t, type Key } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let { refreshMs = 10_000 }: { refreshMs?: number } = $props();

  const LABEL: Record<UplinkName, Key> = {
    wired: 'internet.ethernet',
    repeater: 'internet.repeater',
    tethering: 'tethering.title',
  };
  const ICON: Record<UplinkName, IconName> = { wired: 'ethernet', repeater: 'wifi', tethering: 'phone' };

  let uplinks = $state<UplinksState | null>(null);
  let error = $state<string | null>(null);
  let order = $state<UplinkName[]>([]);
  let reset = $state(true);
  let targets4 = $state('');
  let targets6 = $state('');
  let busy = $state(false);

  function fill(s: UplinksState) {
    order = [...s.order];
    reset = s.reset_connections;
    targets4 = s.targets4.join('\n');
    targets6 = s.targets6.join('\n');
  }

  const settings = $derived<UplinkSettings>({
    order, reset_connections: reset, targets4: lines(targets4), targets6: lines(targets6),
  });
  const changed = $derived(
    !!uplinks && JSON.stringify(settings) !== JSON.stringify({
      order: uplinks.order, reset_connections: uplinks.reset_connections, targets4: uplinks.targets4, targets6: uplinks.targets6,
    }),
  );

  // Edits are kept while the status refreshes underneath them.
  async function load() {
    try {
      const next = await getUplinks();
      if (!uplinks || !changed) fill(next);
      uplinks = next;
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load();
    const timer = setInterval(load, refreshMs);
    return () => clearInterval(timer);
  });

  function targetError(text: string, family: 'v4' | 'v6'): string | null {
    const list = lines(text);
    if (!list.length || list.length > TARGETS_MAX) return t('uplinks.targets_count', { max: TARGETS_MAX });
    const bad = badTarget(list, family);
    return bad ? t(family === 'v4' ? 'uplinks.target_bad4' : 'uplinks.target_bad6', { value: bad }) : null;
  }
  const error4 = $derived(targetError(targets4, 'v4'));
  const error6 = $derived(targetError(targets6, 'v6'));

  async function save() {
    busy = true;
    const ok = await apply(() => setUplinks(settings));
    busy = false;
    if (ok) {
      await load();
      setTimeout(load, 1500);
    }
  }

  function uplinkOf(name: UplinkName): Uplink | undefined {
    return uplinks?.uplinks.find((u) => u.name === name);
  }

  // Status is spelled out, never shown by color alone.
  function statusOf(u: Uplink | undefined, family: 'v4' | 'v6'): { text: string; tone: 'ok' | 'warn' | 'off' } {
    if (!u || !u.configured) return { text: t('uplinks.not_set_up'), tone: 'off' };
    const f = u[family];
    const active = family === 'v4' ? uplinks?.active_v4 : uplinks?.active_v6;
    if (!f.connected) return { text: t('uplinks.not_connected'), tone: 'off' };
    if (!f.online) return { text: t('uplinks.no_internet'), tone: 'warn' };
    return { text: active === u.name ? t('uplinks.in_use') : t('uplinks.standby'), tone: 'ok' };
  }
</script>

<Card title={t('uplinks.title')}>
  <div class="stack">
    <p class="hint">{t('uplinks.hint')}</p>
    {#if error}<Banner kind="error">{error}</Banner>{/if}
    {#if uplinks && !uplinks.watching}<Banner kind="info">{t('uplinks.starting')}</Banner>{/if}

    <ol class="order">
      {#each order as name, i (name)}
        {@const u = uplinkOf(name)}
        {@const v4 = statusOf(u, 'v4')}
        {@const v6 = statusOf(u, 'v6')}
        <li>
          <span class="rank">{i + 1}</span>
          <Icon name={ICON[name]} />
          <span class="what">
            <strong>{t(LABEL[name])}</strong>
            <span class="status">
              <span class={v4.tone}>{t('uplinks.ipv4')}: {v4.text}</span>
              <span class={v6.tone}>{t('uplinks.ipv6')}: {v6.text}</span>
            </span>
          </span>
          <span class="moves">
            <Button variant="ghost" icon="arrow-up" label={t('uplinks.move_up', { name: t(LABEL[name]) })}
              disabled={busy || i === 0} onclick={() => (order = moveUplink(order, name, -1))} />
            <Button variant="ghost" icon="arrow-down" label={t('uplinks.move_down', { name: t(LABEL[name]) })}
              disabled={busy || i === order.length - 1} onclick={() => (order = moveUplink(order, name, 1))} />
          </span>
        </li>
      {/each}
    </ol>

    <Switch label={t('uplinks.reset')} description={t('uplinks.reset_hint')} checked={reset} disabled={busy}
      onchange={(v) => (reset = v)} />

    <details>
      <summary>{t('uplinks.targets')}</summary>
      <div class="stack targets">
        <p class="hint">{t('uplinks.targets_hint')}</p>
        <label class="area">
          <span>{t('uplinks.targets4')}</span>
          <textarea bind:value={targets4} rows="3" spellcheck="false" autocomplete="off"
            aria-invalid={error4 ? 'true' : undefined}></textarea>
          {#if error4}<span class="bad" role="alert">{error4}</span>{/if}
        </label>
        <label class="area">
          <span>{t('uplinks.targets6')}</span>
          <textarea bind:value={targets6} rows="3" spellcheck="false" autocomplete="off"
            aria-invalid={error6 ? 'true' : undefined}></textarea>
          {#if error6}<span class="bad" role="alert">{error6}</span>{/if}
        </label>
      </div>
    </details>

    <div class="actions">
      <Button variant="primary" {busy} disabled={!changed || !!error4 || !!error6} onclick={save}>{t('common.apply')}</Button>
    </div>
  </div>
</Card>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .order {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .order li {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
  }

  .rank {
    min-width: 1.5em;
    color: var(--color-text-muted);
    font-weight: 600;
    text-align: center;
  }

  .what {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: var(--space-1);
    min-width: 0;
  }

  .status {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-1) var(--space-3);
    font-size: var(--font-size-sm);
  }

  .ok {
    color: var(--color-success);
  }

  .warn {
    color: var(--color-warning);
  }

  .off {
    color: var(--color-text-muted);
  }

  .moves {
    display: flex;
  }

  summary {
    display: flex;
    align-items: center;
    min-height: var(--touch-target);
    font-weight: 600;
    cursor: pointer;
  }

  .targets {
    padding-top: var(--space-2);
  }

  .area {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    font-weight: 600;
  }

  textarea {
    width: 100%;
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface);
    color: var(--color-text);
    font-family: var(--font-mono);
    font-size: var(--font-size-sm);
    font-weight: 400;
    resize: vertical;
  }

  textarea:focus-visible {
    outline: 2px solid var(--color-focus);
    outline-offset: 1px;
  }

  .bad {
    color: var(--color-danger);
    font-size: var(--font-size-sm);
    font-weight: 400;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
