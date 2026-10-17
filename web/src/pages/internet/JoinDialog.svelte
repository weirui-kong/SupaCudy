<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Icon from '../../components/Icon.svelte';
  import SignalBars from '../../components/SignalBars.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import { connectRepeater, joinable, needsPassword, scanNetworks, type ScannedNetwork } from '../../lib/api';
  import { errorMessage } from '../../lib/errors';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let { open = $bindable(false), onjoined }: { open?: boolean; onjoined: () => void } = $props();

  let networks = $state<ScannedNetwork[]>([]);
  let scanning = $state(false);
  let scanError = $state<string | null>(null);
  let chosen = $state<ScannedNetwork | null>(null);
  let key = $state('');
  let save = $state(true);
  let busy = $state(false);
  const uid = $props.id();
  const formId = `join-${uid}`;

  async function scan() {
    scanning = true;
    scanError = null;
    try {
      networks = (await scanNetworks()).networks;
    } catch (err) {
      scanError = errorMessage(err);
    }
    scanning = false;
  }

  $effect(() => {
    if (!open) return;
    chosen = null;
    key = '';
    save = true;
    scan();
  });

  // One entry per name: the strongest access point stands for the network.
  const grouped = $derived.by(() => {
    const best = new Map<string, ScannedNetwork>();
    for (const n of networks) {
      const prev = best.get(n.ssid);
      if (!prev || (n.signal ?? -999) > (prev.signal ?? -999)) best.set(n.ssid, n);
    }
    return [...best.values()];
  });

  const keyError = $derived(
    chosen && needsPassword(chosen.encryption) && !(chosen.saved && key === '')
      ? key.length < 8 ? t('wifi.key_too_short') : key.length > 63 ? t('wifi.key_too_long') : null
      : null,
  );

  function pick(n: ScannedNetwork) {
    if (!joinable(n.encryption)) return;
    chosen = n;
    key = '';
  }

  async function join(event: SubmitEvent) {
    event.preventDefault();
    if (!chosen || keyError) return;
    busy = true;
    const target = chosen;
    const ok = await apply(
      () => connectRepeater({ ssid: target.ssid, bssid: '', encryption: target.encryption, key, band: target.band, save }),
      t('internet.joining', { ssid: target.ssid }),
    );
    busy = false;
    if (ok) {
      open = false;
      onjoined();
    }
  }
</script>

<Dialog bind:open title={chosen ? t('internet.join_named', { ssid: chosen.ssid }) : t('internet.choose_network')}>
  {#if !chosen}
    <div class="scan-bar">
      <p class="hint" aria-live="polite">{scanning ? t('internet.scanning') : t('internet.found', { count: grouped.length })}</p>
      <Button icon="refresh" variant="ghost" onclick={scan} busy={scanning}>{t('internet.rescan')}</Button>
    </div>
    {#if scanError}<Banner kind="error">{scanError}</Banner>{/if}
    <ul class="networks">
      {#each grouped as n (n.bssid)}
        <li>
          <button type="button" onclick={() => pick(n)} disabled={!joinable(n.encryption)} aria-current={n.current || undefined}>
            <SignalBars dbm={n.signal} />
            <span class="ssid">
              <strong>{n.ssid}</strong>
              <span class="meta">
                {t(`bands.${n.band}`)}
                {#if n.current}· {t('internet.current')}{:else if n.saved}· {t('internet.saved')}{/if}
                {#if !joinable(n.encryption)}· {t('internet.unsupported')}{/if}
              </span>
            </span>
            {#if needsPassword(n.encryption)}
              <span class="lock"><Icon name="lock" size={16} /><span class="visually-hidden">{t('internet.secured')}</span></span>
            {:else}
              <span class="open">{t('internet.open')}</span>
            {/if}
          </button>
        </li>
      {/each}
    </ul>
  {:else}
    <form id={formId} onsubmit={join}>
      {#if needsPassword(chosen.encryption)}
        <TextField
          label={t('wifi.key')}
          type="password"
          revealable
          bind:value={key}
          autocomplete="off"
          placeholder={chosen.saved ? t('internet.saved_password') : ''}
          error={key || !chosen.saved ? keyError : null}
        />
      {:else}
        <Banner kind="warning">{t('internet.open_upstream')}</Banner>
      {/if}
      <Switch label={t('internet.remember')} description={t('internet.remember_hint')} bind:checked={save} />
      <Banner kind="info">{t('internet.join_hint')}</Banner>
    </form>
  {/if}
  {#snippet footer()}
    {#if chosen}
      <Button onclick={() => (chosen = null)} disabled={busy}>{t('internet.back')}</Button>
      <Button variant="primary" type="submit" form={formId} {busy} disabled={!!keyError}>{t('internet.join')}</Button>
    {:else}
      <Button onclick={() => (open = false)}>{t('common.cancel')}</Button>
    {/if}
  {/snippet}
</Dialog>

<style>
  .scan-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .networks {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .networks button {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    width: 100%;
    min-height: 56px;
    padding: var(--space-2);
    border: 0;
    border-top: 1px solid var(--color-border);
    border-radius: 0;
    background: none;
    text-align: left;
    cursor: pointer;
  }

  .networks li:first-child button {
    border-top: 0;
  }

  .networks button:hover:not(:disabled) {
    background: var(--color-surface-muted);
  }

  .networks button:disabled {
    cursor: not-allowed;
    color: var(--color-text-muted);
  }

  .ssid {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .meta {
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
  }

  .lock,
  .open {
    color: var(--color-text-muted);
    font-size: var(--font-size-xs);
    display: inline-flex;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }
</style>
