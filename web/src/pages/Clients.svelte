<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Icon from '../components/Icon.svelte';
  import InfoTip from '../components/InfoTip.svelte';
  import Select from '../components/Select.svelte';
  import Switch from '../components/Switch.svelte';
  import ClientDialog from './clients/ClientDialog.svelte';
  import {
    clientLabel, forgetOfflineClients, listClients, resetClientCounters, setClientBlocked,
    type Client, type ClientList,
  } from '../lib/api';
  import { SORT_KEYS, clientIcon, rates, samples, sortClients, type Rate, type Sample, type SortKey } from '../lib/clients';
  import { errorMessage } from '../lib/errors';
  import { formatBytes } from '../lib/format';
  import { locale, t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';
  import { readPreference, writePreference } from '../lib/preferences';

  let { refreshMs = 3000 }: { refreshMs?: number } = $props();

  let list = $state<ClientList | null>(null);
  let error = $state<string | null>(null);
  let speeds = $state(new Map<string, Rate>());
  let previous = new Map<string, Sample>();
  let sort = $state<SortKey>(readPreference('clients.sort', SORT_KEYS, 'name'));
  let editing = $state<Client | null>(null);
  let dialogOpen = $state(false);
  let confirmReset = $state(false);
  let confirmForget = $state(false);
  let busy = $state(false);

  const online = $derived(list ? sortClients(list.clients.filter((c) => c.online), sort, speeds, locale()) : []);
  const offline = $derived(list ? sortClients(list.clients.filter((c) => !c.online), 'name', speeds, locale()) : []);

  async function refresh() {
    try {
      const next = await listClients();
      speeds = rates(previous, next);
      previous = samples(next);
      list = next;
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    refresh();
    const timer = setInterval(refresh, refreshMs);
    return () => clearInterval(timer);
  });

  function edit(client: Client) {
    editing = client;
    dialogOpen = true;
  }

  // Optimistic: the switch moves at once and moves back if the router refuses.
  async function toggleBlock(client: Client, blocked: boolean) {
    const name = clientLabel(client);
    client.blocked = blocked;
    const done = await apply(() => setClientBlocked(client.mac, blocked),
      blocked ? t('clients.blocked_done', { name }) : t('clients.unblocked_done', { name }));
    if (!done) client.blocked = !blocked;
    refresh();
  }

  async function resetCounters() {
    busy = true;
    if (await apply(resetClientCounters)) previous = new Map();
    busy = false;
    confirmReset = false;
    refresh();
  }

  async function forgetOffline() {
    busy = true;
    await apply(forgetOfflineClients);
    busy = false;
    confirmForget = false;
    refresh();
  }

  const rate = (bytesPerSecond: number | undefined) =>
    bytesPerSecond === undefined ? t('common.unavailable') : `${formatBytes(bytesPerSecond, locale())}/s`;

  const connectionText = (c: Client) =>
    c.connection === 'wifi'
      ? t('clients.via_wifi', { band: c.band ? t(`bands.${c.band}`) : '' })
      : c.connection === 'wired' ? t('clients.via_wired') : t('common.unavailable');

  const sortOptions = $derived(SORT_KEYS.map((value) => ({ value, label: t(`clients.sort_${value}`) })));
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

<div class="toolbar">
  <div class="sort">
    <Select label={t('clients.sort')} bind:value={sort} options={sortOptions} onchange={(v) => writePreference('clients.sort', v)} />
  </div>
  <Button icon="refresh" variant="ghost" onclick={() => (confirmReset = true)}>{t('clients.reset_counters')}</Button>
</div>

{#snippet section(title: string, items: Client[], isOnline: boolean)}
  <section class="section" aria-labelledby="clients-{isOnline ? 'online' : 'offline'}">
    <header>
      <h2 id="clients-{isOnline ? 'online' : 'offline'}">{title} <span class="count">({items.length})</span></h2>
      {#if !isOnline && items.length > 0}
        <Button icon="trash" variant="ghost" onclick={() => (confirmForget = true)}>{t('clients.forget_offline')}</Button>
      {/if}
    </header>

    {#if !list}
      <p class="empty">{t('common.loading')}</p>
    {:else if items.length === 0}
      <p class="empty">{isOnline ? t('clients.none_online') : t('clients.none_offline')}</p>
    {:else}
      <div class="table" role="table" aria-label={title}>
        <div class="row head" role="row">
          <span role="columnheader">{t('clients.name')}</span>
          <span role="columnheader">{t('clients.address')}</span>
          <span role="columnheader">{t('clients.connection')}</span>
          <span role="columnheader">{t('clients.speed')} <InfoTip text={t('clients.speed_hint')} /></span>
          <span role="columnheader">{t('clients.traffic')}</span>
          <span role="columnheader">{t('clients.block_short')}</span>
          <span role="columnheader"><span class="visually-hidden">{t('common.actions')}</span></span>
        </div>
        {#each items as client (client.mac)}
          {@const speed = speeds.get(client.mac)}
          <div class="row" role="row" class:blocked={client.blocked}>
            <span role="cell" class="name">
              <span class="icon"><Icon name={clientIcon(client)} /></span>
              <span class="label">
                <button type="button" class="link" onclick={() => edit(client)}>{clientLabel(client)}</button>
                {#if client.blocked}<span class="badge danger"><Icon name="block" size={14} />{t('clients.blocked')}</span>{/if}
                {#if client.up_limit || client.down_limit}<span class="badge"><Icon name="speed" size={14} />{t('clients.limited')}</span>{/if}
                {#if client.reserved_ip}<span class="badge"><Icon name="pin" size={14} />{t('clients.fixed')}</span>{/if}
              </span>
            </span>
            <span role="cell" class="address">
              <span>{client.ip ?? t('common.unavailable')}</span>
              <span class="mac">{client.mac.toUpperCase()}{#if client.random_mac}<InfoTip text={t('clients.random_mac_hint')} />{/if}</span>
            </span>
            <span role="cell" class="connection">
              <Icon name={client.connection === 'wifi' ? 'wifi' : 'ethernet'} size={18} />
              <span>{connectionText(client)}</span>
            </span>
            <span role="cell" class="rates">
              {#if isOnline}
                <span><Icon name="arrow-up" size={14} /><span class="visually-hidden">{t('clients.upload')}</span>{rate(speed?.up)}</span>
                <span><Icon name="arrow-down" size={14} /><span class="visually-hidden">{t('clients.download')}</span>{rate(speed?.down)}</span>
              {:else}
                <span>{t('common.unavailable')}</span>
              {/if}
            </span>
            <span role="cell" class="rates traffic">
              <span><Icon name="arrow-up" size={14} /><span class="visually-hidden">{t('clients.upload')}</span>{formatBytes(client.tx_bytes, locale())}</span>
              <span><Icon name="arrow-down" size={14} /><span class="visually-hidden">{t('clients.download')}</span>{formatBytes(client.rx_bytes, locale())}</span>
            </span>
            <span role="cell" class="block">
              <Switch
                label={t('clients.block_named', { name: clientLabel(client) })}
                hideLabel
                checked={client.blocked}
                onchange={(value) => toggleBlock(client, value)}
              />
            </span>
            <span role="cell" class="actions">
              <Button icon="more" variant="ghost" label={t('clients.manage_named', { name: clientLabel(client) })} onclick={() => edit(client)} />
            </span>
          </div>
        {/each}
      </div>
    {/if}
  </section>
{/snippet}

{@render section(t('clients.online'), online, true)}
{@render section(t('clients.offline'), offline, false)}

{#if editing}
  <ClientDialog bind:open={dialogOpen} client={editing} onsaved={refresh} />
{/if}

<ConfirmDialog
  bind:open={confirmReset}
  title={t('clients.reset_counters')}
  message={t('clients.reset_counters_confirm')}
  confirmLabel={t('clients.reset_counters')}
  {busy}
  onconfirm={resetCounters}
/>

<ConfirmDialog
  bind:open={confirmForget}
  title={t('clients.forget_offline')}
  message={t('clients.forget_offline_confirm', { count: offline.length })}
  confirmLabel={t('clients.forget_offline')}
  danger
  {busy}
  onconfirm={forgetOffline}
/>

<style>
  .toolbar {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-end;
    justify-content: space-between;
    gap: var(--space-3);
    margin-bottom: var(--space-4);
  }

  .sort {
    min-width: 180px;
  }

  .section {
    margin-bottom: var(--space-5);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    overflow: hidden;
  }

  .section header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-2) var(--space-2) var(--space-4);
    border-bottom: 1px solid var(--color-border);
    min-height: 56px;
  }

  h2 {
    font-size: var(--font-size-md);
  }

  .count {
    color: var(--color-text-muted);
    font-weight: 400;
  }

  .empty {
    padding: var(--space-5) var(--space-4);
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  /* Phone: each client is a card; the header row is hidden. */
  .row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    grid-template-areas:
      "name actions"
      "address block"
      "connection block"
      "rates rates";
    gap: var(--space-1) var(--space-3);
    padding: var(--space-3) var(--space-2) var(--space-3) var(--space-4);
    border-top: 1px solid var(--color-border);
    align-items: center;
  }

  .row:nth-child(2) {
    border-top: 0;
  }

  .row.head {
    display: none;
  }

  .name {
    grid-area: name;
    display: flex;
    align-items: center;
    gap: var(--space-3);
    min-width: 0;
  }

  .icon {
    flex: none;
    display: flex;
    color: var(--color-text-muted);
  }

  .label {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-1) var(--space-2);
    min-width: 0;
  }

  .link {
    min-height: var(--touch-target);
    padding: 0;
    border: 0;
    background: none;
    color: var(--color-text);
    font-weight: 600;
    text-align: left;
    cursor: pointer;
    overflow-wrap: anywhere;
  }

  .link:hover {
    color: var(--color-accent);
    text-decoration: underline;
  }

  .badge {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    padding: 1px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-surface-muted);
    border: 1px solid var(--color-border);
    color: var(--color-text-muted);
    font-size: var(--font-size-xs);
  }

  .badge.danger {
    color: var(--color-danger);
    border-color: var(--color-danger);
    background: var(--color-danger-soft);
  }

  .address {
    grid-area: address;
    display: flex;
    flex-direction: column;
    font-size: var(--font-size-sm);
    font-variant-numeric: tabular-nums;
  }

  .mac {
    display: inline-flex;
    align-items: center;
    color: var(--color-text-muted);
    font-size: var(--font-size-xs);
  }

  .connection {
    grid-area: connection;
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--font-size-sm);
    color: var(--color-text-muted);
  }

  .rates {
    grid-area: rates;
    display: flex;
    gap: var(--space-4);
    font-size: var(--font-size-sm);
    font-variant-numeric: tabular-nums;
  }

  .rates > span {
    display: inline-flex;
    align-items: center;
    gap: 2px;
  }

  .traffic {
    display: none;
  }

  .block {
    grid-area: block;
  }

  .actions {
    grid-area: actions;
  }

  .row.blocked .name .icon {
    color: var(--color-danger);
  }

  /* Wide screens: a real table. */
  @media (min-width: 1024px) {
    .row,
    .row.head {
      display: grid;
      grid-template-columns: minmax(180px, 2fr) minmax(150px, 1.4fr) minmax(110px, 1fr) minmax(110px, 1fr) minmax(100px, 1fr) 64px 52px;
      grid-template-areas: none;
      padding: var(--space-2) var(--space-2) var(--space-2) var(--space-4);
    }

    .row > * {
      grid-area: auto;
    }

    .row.head {
      font-size: var(--font-size-xs);
      font-weight: 600;
      color: var(--color-text-muted);
      text-transform: uppercase;
      letter-spacing: 0.03em;
      border-top: 0;
      background: var(--color-surface-muted);
    }

    .row.head span {
      display: flex;
      align-items: center;
    }

    .row:nth-child(2) {
      border-top: 1px solid var(--color-border);
    }

    .rates {
      flex-direction: column;
      gap: 0;
    }

    .traffic {
      display: flex;
    }
  }
</style>
