<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Select from '../components/Select.svelte';
  import Switch from '../components/Switch.svelte';
  import TextField from '../components/TextField.svelte';
  import ModeCard from './lan/ModeCard.svelte';
  import ReservationDialog from './lan/ReservationDialog.svelte';
  import {
    clientLabel, deleteReservation, getLan, listClients, setLan,
    type Client, type LanConfig, type Reservation,
  } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';
  import { intToIpv4, ipv4ToInt, isIPv4, prefixToNetmask } from '../lib/validate';

  const PREFIXES = [24, 23, 22, 21, 20, 16] as const;
  const LEASES = ['1h', '6h', '12h', '24h', '7d'] as const;

  let config = $state<LanConfig | null>(null);
  let clients = $state<Client[]>([]);
  let loadError = $state<string | null>(null);

  let ipaddr = $state('');
  let prefix = $state('24');
  let dhcpEnabled = $state(true);
  let start = $state('');
  let limit = $state('');
  let leasetime = $state<string>('12h');
  let busy = $state(false);
  let confirmMove = $state(false);
  let movedTo = $state<string | null>(null);

  let reservationOpen = $state(false);
  let editing = $state<Reservation | null>(null);
  let deleting = $state<Reservation | null>(null);
  let confirmDelete = $state(false);

  function fill(c: LanConfig) {
    ipaddr = c.ipaddr;
    prefix = String(c.prefix);
    dhcpEnabled = c.dhcp.enabled;
    start = String(c.dhcp.start);
    limit = String(c.dhcp.limit);
    leasetime = c.dhcp.leasetime;
  }

  async function load() {
    try {
      config = await getLan();
      fill(config);
      loadError = null;
    } catch (err) {
      loadError = errorMessage(err);
    }
    listClients().then((l) => (clients = l.clients)).catch(() => {});
  }

  $effect(() => {
    load();
  });

  const prefixNum = $derived(Number(prefix));
  const size = $derived(2 ** (32 - prefixNum));
  const network = $derived(isIPv4(ipaddr) ? intToIpv4(Math.floor(ipv4ToInt(ipaddr) / size) * size) : '');

  const errors = $derived.by(() => {
    const out: Record<string, string | null> = { ipaddr: null, start: null, limit: null };
    if (!isIPv4(ipaddr)) out.ipaddr = t('validation.ipv4');
    else {
      const offset = ipv4ToInt(ipaddr) - ipv4ToInt(network);
      if (offset === 0 || offset === size - 1) out.ipaddr = t('lan.ip_network_or_broadcast');
      else if (!/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(ipaddr)) out.ipaddr = t('lan.ip_not_private');
    }
    const s = Number(start);
    const l = Number(limit);
    if (!Number.isInteger(s) || s < 1 || s >= size - 1) out.start = t('lan.start_invalid', { max: size - 2 });
    if (!Number.isInteger(l) || l < 1 || s + l > size - 1) out.limit = t('lan.limit_invalid', { max: Math.max(1, size - 1 - s) });
    return out;
  });
  const valid = $derived(Object.values(errors).every((e) => e === null));

  const dirty = $derived(
    config !== null &&
      (ipaddr !== config.ipaddr || prefixNum !== config.prefix || dhcpEnabled !== config.dhcp.enabled ||
        Number(start) !== config.dhcp.start || Number(limit) !== config.dhcp.limit || leasetime !== config.dhcp.leasetime),
  );
  const addressChanged = $derived(config !== null && (ipaddr !== config.ipaddr || prefixNum !== config.prefix));
  const range = $derived(
    valid && network
      ? `${intToIpv4(ipv4ToInt(network) + Number(start))} – ${intToIpv4(ipv4ToInt(network) + Number(start) + Number(limit) - 1)}`
      : null,
  );

  function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!valid || !dirty) return;
    if (addressChanged) confirmMove = true;
    else save();
  }

  async function save() {
    busy = true;
    const result = await apply(() =>
      setLan({
        ipaddr,
        netmask: prefixToNetmask(prefixNum),
        dhcp_enabled: dhcpEnabled,
        start: Number(start),
        limit: Number(limit),
        leasetime,
      }),
    );
    busy = false;
    confirmMove = false;
    if (!result) return;
    if (result.address_changed) movedTo = result.ipaddr;
    // The network restarts a moment after the reply; read back afterwards.
    setTimeout(load, 3000);
  }

  async function removeReservation() {
    if (!deleting) return;
    busy = true;
    await apply(() => deleteReservation(deleting!.mac));
    busy = false;
    confirmDelete = false;
    load();
  }

  const prefixOptions = PREFIXES.map((p) => ({ value: String(p), label: `/${p} (${prefixToNetmask(p)})` }));
  const leaseOptions = $derived(LEASES.map((value) => ({ value, label: t(`lan.lease_${value}`) })));
  const reservationClients = $derived(clients.filter((c) => !c.reserved_ip));
  const taken = $derived(new Map((config?.reservations ?? []).map((r) => [r.ip, r.mac])));
  const nameFor = (mac: string) => {
    const client = clients.find((c) => c.mac === mac);
    return client ? clientLabel(client) : null;
  };
  const onRouterAddress = $derived(config !== null && location.hostname === config.ipaddr);
</script>

{#if loadError}<Banner kind="error">{loadError}</Banner>{/if}

{#if movedTo}
  <Banner kind="warning">
    {t('lan.moved', { ip: movedTo })}
    <a href={`http://${movedTo}/supacudy/`}>{`http://${movedTo}/supacudy/`}</a>
  </Banner>
{/if}

<div class="grid">
  <Card title={t('lan.addressing')}>
    {#if config}
      <form class="form" onsubmit={submit}>
        <p class="lead">{t('lan.addressing_hint')}</p>
        <div class="pair">
          <TextField label={t('lan.router_ip')} bind:value={ipaddr} inputmode="decimal" error={errors.ipaddr} required />
          <Select label={t('lan.netmask')} bind:value={prefix} options={prefixOptions} />
        </div>

        <Switch label={t('lan.dhcp')} description={t('lan.dhcp_hint')} bind:checked={dhcpEnabled} />
        {#if dhcpEnabled}
          <div class="pair">
            <TextField label={t('lan.start')} bind:value={start} inputmode="numeric" error={errors.start} hint={t('lan.start_hint')} />
            <TextField label={t('lan.limit')} bind:value={limit} inputmode="numeric" error={errors.limit} hint={t('lan.limit_hint')} />
          </div>
          {#if range}<p class="range">{t('lan.range', { range })}</p>{/if}
          <Select label={t('lan.leasetime')} bind:value={leasetime} options={leaseOptions} />
        {/if}

        {#if addressChanged}
          <Banner kind="warning">{t('lan.address_change_warning')}</Banner>
        {/if}

        <div class="actions">
          <Button onclick={() => config && fill(config)} disabled={!dirty || busy}>{t('common.reset')}</Button>
          <Button variant="primary" type="submit" {busy} disabled={!dirty || !valid}>{t('common.apply')}</Button>
        </div>
      </form>
    {:else if !loadError}
      <p>{t('common.loading')}</p>
    {/if}
  </Card>

  <ModeCard onmoved={(ip) => (movedTo = ip)} />

  <Card title={t('lan.reservations')}>
    <p class="lead">{t('lan.reservations_hint')}</p>
    {#if config && config.reservations.length > 0}
      <ul class="reservations">
        {#each config.reservations as r (r.id)}
          <li>
            <span class="who">
              <strong>{r.name ?? nameFor(r.mac) ?? r.mac.toUpperCase()}</strong>
              <span class="muted">{r.mac.toUpperCase()}</span>
            </span>
            <span class="ip">{r.ip}</span>
            <span class="row-actions">
              <Button icon="edit" variant="ghost" label={t('common.edit_named', { name: r.ip })} onclick={() => ((editing = r), (reservationOpen = true))} />
              <Button icon="trash" variant="ghost" label={t('common.delete_named', { name: r.ip })} onclick={() => ((deleting = r), (confirmDelete = true))} />
            </span>
          </li>
        {/each}
      </ul>
    {:else if config}
      <p class="muted">{t('lan.no_reservations')}</p>
    {/if}
    <div class="actions">
      <Button icon="plus" onclick={() => ((editing = null), (reservationOpen = true))} disabled={!config}>{t('lan.add_reservation')}</Button>
    </div>
  </Card>
</div>

{#if config}
  <ReservationDialog
    bind:open={reservationOpen}
    {editing}
    clients={reservationClients}
    network={config ? intToIpv4(Math.floor(ipv4ToInt(config.ipaddr) / 2 ** (32 - config.prefix)) * 2 ** (32 - config.prefix)) : ''}
    prefix={config.prefix}
    {taken}
    onsaved={load}
  />
{/if}

<ConfirmDialog
  bind:open={confirmMove}
  title={t('lan.change_address')}
  message={t('lan.change_address_confirm', { ip: ipaddr })}
  consequence={onRouterAddress ? t('lan.change_address_disconnect', { ip: ipaddr }) : t('lan.change_address_clients')}
  confirmLabel={t('common.apply')}
  {busy}
  onconfirm={save}
/>

<ConfirmDialog
  bind:open={confirmDelete}
  title={t('lan.delete_reservation')}
  message={t('lan.delete_reservation_confirm', { ip: deleting?.ip ?? '' })}
  confirmLabel={t('common.delete')}
  danger
  {busy}
  onconfirm={removeReservation}
/>

<style>
  .grid {
    display: grid;
    gap: var(--space-4);
  }

  .form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .lead,
  .muted {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .pair {
    display: grid;
    gap: var(--space-3);
  }

  .range {
    font-size: var(--font-size-sm);
    font-variant-numeric: tabular-nums;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
    margin-top: var(--space-2);
  }

  .reservations {
    list-style: none;
    margin: var(--space-3) 0 0;
    padding: 0;
  }

  .reservations li {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    grid-template-areas: "who actions" "ip actions";
    align-items: center;
    gap: 0 var(--space-3);
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
  }

  .who {
    grid-area: who;
    display: flex;
    flex-direction: column;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .ip {
    grid-area: ip;
    font-variant-numeric: tabular-nums;
  }

  .row-actions {
    grid-area: actions;
    display: flex;
  }

  @media (min-width: 600px) {
    .pair {
      grid-template-columns: 1fr 1fr;
    }

    .reservations li {
      grid-template-columns: minmax(0, 1fr) 140px auto;
      grid-template-areas: "who ip actions";
    }
  }

  @media (min-width: 1200px) {
    .grid {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      align-items: start;
    }
  }
</style>
