<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Select from '../../components/Select.svelte';
  import TextField from '../../components/TextField.svelte';
  import { clientLabel, setReservation, type Client, type Reservation } from '../../lib/api';
  import { apply } from '../../lib/notify.svelte';
  import { inSubnet, isMac, normalizeMac } from '../../lib/validate';
  import { t } from '../../lib/i18n/index.svelte';

  let {
    open = $bindable(false),
    editing = null,
    clients,
    network,
    prefix,
    taken,
    onsaved,
  }: {
    open?: boolean;
    editing?: Reservation | null;
    clients: Client[];
    network: string;
    prefix: number;
    /** IP -> MAC of existing reservations, for duplicate checks. */
    taken: Map<string, string>;
    onsaved: () => void;
  } = $props();

  const MANUAL = 'manual';

  let device = $state(MANUAL);
  let mac = $state('');
  let ip = $state('');
  let name = $state('');
  let busy = $state(false);
  const uid = $props.id();
  const formId = `reservation-${uid}`;

  $effect(() => {
    if (!open) return;
    device = editing ? MANUAL : (clients[0]?.mac ?? MANUAL);
    mac = editing?.mac ?? clients[0]?.mac ?? '';
    ip = editing?.ip ?? clients[0]?.ip ?? '';
    name = editing?.name ?? '';
  });

  const deviceOptions = $derived([
    ...clients.map((c) => ({ value: c.mac, label: `${clientLabel(c)} (${c.mac.toUpperCase()})` })),
    { value: MANUAL, label: t('lan.manual_mac') },
  ]);

  function pick(value: string) {
    if (value === MANUAL) return;
    const client = clients.find((c) => c.mac === value);
    mac = value;
    if (client?.ip) ip = client.ip;
  }

  const errors = $derived({
    mac: !isMac(mac) ? t('validation.mac') : null,
    ip: !inSubnet(ip, network, prefix)
      ? t('lan.ip_outside', { network: `${network}/${prefix}` })
      : taken.has(ip) && taken.get(ip) !== normalizeMac(mac) ? t('lan.ip_taken') : null,
    name: name !== '' && !/^[A-Za-z0-9][A-Za-z0-9-]{0,62}$/.test(name) ? t('lan.hostname_invalid') : null,
  });
  const valid = $derived(Object.values(errors).every((e) => e === null));

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    busy = true;
    const ok = await apply(() => setReservation(normalizeMac(mac), ip.trim(), name.trim()));
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }
</script>

<Dialog bind:open title={editing ? t('lan.edit_reservation') : t('lan.add_reservation')}>
  <form id={formId} onsubmit={save}>
    {#if !editing && clients.length > 0}
      <Select label={t('lan.device')} bind:value={device} options={deviceOptions} onchange={pick} />
    {/if}
    {#if editing || device === MANUAL || clients.length === 0}
      <TextField label={t('clients.mac')} bind:value={mac} placeholder="AA:BB:CC:DD:EE:FF" error={mac ? errors.mac : null} disabled={!!editing} required />
    {/if}
    <TextField label={t('clients.fixed_ip_address')} bind:value={ip} inputmode="decimal" error={ip ? errors.ip : null} required />
    <TextField label={t('lan.hostname')} bind:value={name} hint={t('lan.hostname_hint')} error={errors.name} />
  </form>
  {#snippet footer()}
    <Button onclick={() => (open = false)} disabled={busy}>{t('common.cancel')}</Button>
    <Button variant="primary" type="submit" form={formId} {busy} disabled={!valid}>{t('common.save')}</Button>
  {/snippet}
</Dialog>

<style>
  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }
</style>
