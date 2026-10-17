<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import DataRow from '../components/DataRow.svelte';
  import Icon from '../components/Icon.svelte';
  import Segmented from '../components/Segmented.svelte';
  import Switch from '../components/Switch.svelte';
  import OvpnDialog from './vpn/OvpnDialog.svelte';
  import ProfileDialog from './vpn/ProfileDialog.svelte';
  import {
    clientLabel, connectVpn, destinationKind, deleteVpnProfile, disconnectVpn, getVpn, listClients, profileServer,
    setVpnOptions, vpnOptionsOf, type Client, type OvpnProfile, type VpnOptions, type VpnProfile, type VpnRouteMode, type VpnState, type WgProfile,
  } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { formatBytes, formatDuration } from '../lib/format';
  import { locale, t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';

  let { refreshMs = 5000 }: { refreshMs?: number } = $props();

  let vpn = $state<VpnState | null>(null);
  let error = $state<string | null>(null);
  let editing = $state<WgProfile | null>(null);
  let dialogOpen = $state(false);
  let editingOvpn = $state<OvpnProfile | null>(null);
  let ovpnOpen = $state(false);
  let deleting = $state<VpnProfile | null>(null);
  let deleteOpen = $state(false);
  let busy = $state<string | null>(null);
  let clients = $state<Client[]>([]);
  let destinationsText = $state('');
  let destinationsLoaded = false;

  async function refresh() {
    try {
      vpn = await getVpn();
      if (!destinationsLoaded) {
        destinationsText = vpn.destinations.join('\n');
        destinationsLoaded = true;
      }
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    listClients().then((l) => (clients = l.clients)).catch(() => {});
  });

  $effect(() => {
    refresh();
    const timer = setInterval(refresh, refreshMs);
    return () => clearInterval(timer);
  });

  // Changes apply a moment after the reply; look again once they have.
  const later = () => setTimeout(refresh, 4000);

  const active = $derived(vpn?.profiles.find((p) => p.id === vpn?.active) ?? null);
  const connected = $derived(!!active && !!vpn?.status.connected);
  // OpenVPN carries every device; choosing devices needs WireGuard.
  const ovpnActive = $derived(active?.type === 'openvpn');

  async function run(key: string, action: () => Promise<unknown>) {
    busy = key;
    const ok = await apply(action);
    busy = null;
    if (ok) {
      await refresh();
      later();
    }
  }

  function setOptions(change: Partial<VpnOptions>) {
    if (!vpn) return;
    const next = { ...vpnOptionsOf(vpn), ...change };
    return run('options', () => setVpnOptions(next));
  }

  function toggleDevice(mac: string, on: boolean) {
    if (!vpn) return;
    return setOptions({ devices: on ? [...vpn.devices, mac] : vpn.devices.filter((d) => d !== mac) });
  }

  const destinationLines = $derived(destinationsText.split(/[\s,]+/).filter(Boolean));
  const badDestination = $derived(
    destinationLines.find((d) => {
      const kind = destinationKind(d);
      return !kind || (kind === 'domain' && !vpn?.domains_supported);
    }) ?? null,
  );
  const destinationsChanged = $derived(!!vpn && destinationLines.join() !== vpn.destinations.join());

  const routeOptions = $derived([
    { value: 'all' as VpnRouteMode, label: t('vpn.route_all') },
    { value: 'selected' as VpnRouteMode, label: t('vpn.route_selected') },
  ]);
  // Devices chosen earlier stay listed even while they are offline.
  const routeDevices = $derived.by(() => {
    const known = new Map(clients.map((c) => [c.mac, clientLabel(c)]));
    for (const mac of vpn?.devices ?? []) if (!known.has(mac)) known.set(mac, mac.toUpperCase());
    return [...known].map(([mac, label]) => ({ mac, label }));
  });

  function add() {
    editing = null;
    dialogOpen = true;
  }

  function edit(p: VpnProfile) {
    if (p.type === 'openvpn') {
      editingOvpn = p;
      ovpnOpen = true;
    } else {
      editing = p;
      dialogOpen = true;
    }
  }

  function addOvpn() {
    editingOvpn = null;
    ovpnOpen = true;
  }

  function askDelete(p: VpnProfile) {
    deleting = p;
    deleteOpen = true;
  }

  async function remove() {
    if (!deleting) return;
    const target = deleting;
    await run(`delete-${target.id}`, () => deleteVpnProfile(target.id));
    deleteOpen = false;
  }
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

{#if vpn}
  <div class="grid">
    <Card title={t('vpn.status')}>
      <div class="state" class:on={connected}>
        <Icon name={connected ? 'shield' : active ? 'warning' : 'info'} size={24} />
        <div>
          <strong>
            {connected ? t('vpn.connected', { name: active!.name })
              : active ? t('vpn.connecting', { name: active.name })
                : t('vpn.not_connected')}
          </strong>
          <span>
            {connected ? t('vpn.connected_hint')
              : active ? t('vpn.connecting_hint')
                : t('vpn.not_connected_hint')}
          </span>
        </div>
      </div>
      {#if active}
        <dl>
          <DataRow label={t('vpn.endpoint')}>{vpn.status.endpoint ?? profileServer(active)}</DataRow>
          <DataRow label={t('vpn.tunnel_address')}>{vpn.status.addresses.join(', ') || t('common.unavailable')}</DataRow>
          {#if active.type === 'wireguard'}
            <DataRow label={t('vpn.last_handshake')}>
              {vpn.status.handshake ? t('vpn.ago', { time: formatDuration(Math.max(0, vpn.time - vpn.status.handshake), t) }) : t('vpn.never')}
            </DataRow>
          {/if}
          {#if vpn.ipv6}
            <DataRow label={t('vpn.ipv6')}>{vpn.ipv6 === 'tunnel' ? t('vpn.ipv6_tunnel') : t('vpn.ipv6_blocked')}</DataRow>
          {/if}
          <DataRow label={t('vpn.traffic')}>
            {t('vpn.traffic_value', { rx: formatBytes(vpn.status.rx_bytes, locale()), tx: formatBytes(vpn.status.tx_bytes, locale()) })}
          </DataRow>
        </dl>
        <div class="actions">
          <Button icon="power" busy={busy === 'disconnect'} onclick={() => run('disconnect', disconnectVpn)}>{t('vpn.disconnect')}</Button>
        </div>
      {/if}
    </Card>

    <Card title={t('vpn.options')}>
      <div class="options">
        {#if ovpnActive}
          <p class="lead">{t('vpn.route_ovpn')}</p>
        {:else}
          <Segmented
            label={t('vpn.route_mode')}
            options={routeOptions}
            value={vpn.route_mode}
            onchange={(v: VpnRouteMode) => setOptions({ route_mode: v })}
          />
          {#if vpn.route_mode === 'selected'}
            <fieldset class="devices">
              <legend>{t('vpn.route_devices')}</legend>
              {#if routeDevices.length === 0}
                <p class="lead">{t('clients.none_online')}</p>
              {/if}
              {#each routeDevices as d (d.mac)}
                <Switch label={d.label} checked={vpn.devices.includes(d.mac)} onchange={(on) => toggleDevice(d.mac, on)} />
              {/each}
              <p class="lead">{t('vpn.route_selected_dns')}</p>
            </fieldset>
            <label class="area">
              <span>{t('vpn.destinations')}</span>
              <span class="lead">{vpn.domains_supported ? t('vpn.destinations_hint') : t('vpn.destinations_hint_ip')}</span>
              <textarea bind:value={destinationsText} rows="4" spellcheck="false" autocomplete="off" aria-invalid={badDestination ? 'true' : undefined}></textarea>
            </label>
            {#if badDestination}
              <p class="bad" role="alert">{t('vpn.destination_bad', { value: badDestination })}</p>
            {/if}
            <div class="actions">
              <Button
                disabled={!destinationsChanged || !!badDestination}
                busy={busy === 'options'}
                onclick={() => setOptions({ destinations: destinationLines })}
              >
                {t('common.apply')}
              </Button>
            </div>
          {/if}
        {/if}
        <Switch
          label={t('vpn.kill_switch')}
          description={!ovpnActive && vpn.route_mode === 'selected' ? t('vpn.kill_switch_selected_hint') : t('vpn.kill_switch_hint')}
          checked={vpn.kill_switch}
          onchange={(v) => setOptions({ kill_switch: v })}
        />
        <Switch
          label={t('vpn.allow_lan')}
          description={t('vpn.allow_lan_hint')}
          checked={vpn.allow_lan}
          disabled={!vpn.kill_switch}
          onchange={(v) => setOptions({ allow_lan: v })}
        />
      </div>
    </Card>

    <Card title={t('vpn.profiles')}>
      {#if vpn.profiles.length === 0}
        <p class="lead">{t('vpn.no_profiles')}</p>
      {:else}
        <ul class="profiles">
          {#each vpn.profiles as p (p.id)}
            <li class:current={p.id === vpn.active}>
              <span class="label">
                <strong>{p.name}</strong>
                <span>
                  {p.type === 'openvpn' ? 'OpenVPN' : 'WireGuard'} · {profileServer(p)}{p.id === vpn.active ? ` · ${t('vpn.in_use')}` : ''}
                </span>
              </span>
              <span class="buttons">
                {#if p.id !== vpn.active}
                  <Button variant="primary" busy={busy === `connect-${p.id}`} disabled={!!busy} onclick={() => run(`connect-${p.id}`, () => connectVpn(p.id))}>
                    {t('vpn.connect')}
                  </Button>
                {/if}
                <Button variant="ghost" icon="edit" label={t('common.edit_named', { name: p.name })} onclick={() => edit(p)} />
                <Button
                  variant="ghost"
                  icon="trash"
                  label={t('common.delete_named', { name: p.name })}
                  disabled={p.id === vpn.active}
                  onclick={() => askDelete(p)}
                />
              </span>
            </li>
          {/each}
        </ul>
      {/if}
      <div class="actions">
        <Button icon="plus" onclick={add}>{t('vpn.add_profile')}</Button>
        <Button icon="plus" onclick={addOvpn}>{t('vpn.add_openvpn')}</Button>
      </div>
    </Card>
  </div>
{:else if !error}
  <p>{t('common.loading')}</p>
{/if}

<ProfileDialog bind:open={dialogOpen} profile={editing} onsaved={refresh} />
<OvpnDialog bind:open={ovpnOpen} profile={editingOvpn} onsaved={refresh} />
<ConfirmDialog
  bind:open={deleteOpen}
  title={t('vpn.delete_profile')}
  message={t('vpn.delete_confirm', { name: deleting?.name ?? '' })}
  confirmLabel={t('common.delete')}
  danger
  busy={busy?.startsWith('delete-') ?? false}
  onconfirm={remove}
/>

<style>
  .grid {
    display: grid;
    gap: var(--space-4);
    align-items: start;
  }

  .state {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3);
    margin-bottom: var(--space-3);
    border-radius: var(--radius-md);
    background: var(--color-surface-muted);
  }

  .state.on {
    background: var(--color-success-soft);
  }

  .state.on :global(svg) {
    color: var(--color-success);
  }

  .state div {
    display: flex;
    flex-direction: column;
  }

  .state span,
  .lead {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  dl {
    margin: 0 0 var(--space-3);
  }

  .options {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .devices {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin: 0;
    padding: var(--space-3) 0 0;
    border: 0;
    border-top: 1px solid var(--color-border);
  }

  legend {
    font-weight: 600;
  }

  .area {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    font-weight: 600;
  }

  .area .lead {
    font-weight: 400;
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
  }

  .profiles {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .profiles li {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
  }

  .label {
    display: flex;
    flex-direction: column;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .label span {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .buttons {
    display: flex;
    align-items: center;
    gap: var(--space-1);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-3);
    justify-content: flex-end;
    margin-top: var(--space-3);
  }

  @media (min-width: 1200px) {
    .grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .grid > :global(:last-child) {
      grid-column: 1 / -1;
    }
  }
</style>
