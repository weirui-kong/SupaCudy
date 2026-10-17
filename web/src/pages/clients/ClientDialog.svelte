<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import DataRow from '../../components/DataRow.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Select from '../../components/Select.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import {
    CLIENT_TYPES, clientLabel, deleteReservation, setClientBlocked, setClientInfo, setClientLimit,
    setReservation, type Client, type ClientType,
  } from '../../lib/api';
  import { apply } from '../../lib/notify.svelte';
  import { isIPv4 } from '../../lib/validate';
  import { t } from '../../lib/i18n/index.svelte';

  let {
    open = $bindable(false),
    client,
    onsaved,
  }: { open?: boolean; client: Client; onsaved: () => void } = $props();

  // Form state starts from the client each time the dialog opens.
  let name = $state('');
  let kind = $state<ClientType | ''>('');
  let blocked = $state(false);
  let up = $state('');
  let down = $state('');
  let fixed = $state(false);
  let fixedIp = $state('');
  let busy = $state(false);
  const uid = $props.id();
  const formId = `client-form-${uid}`;

  $effect(() => {
    if (!open) return;
    name = client.name ?? '';
    kind = client.type ?? '';
    blocked = client.blocked;
    up = client.up_limit ? String(client.up_limit) : '';
    down = client.down_limit ? String(client.down_limit) : '';
    fixed = client.reserved_ip !== null;
    fixedIp = client.reserved_ip ?? client.ip ?? '';
  });

  const parseLimit = (value: string) => (value.trim() === '' ? 0 : Number(value));
  const limitError = (value: string) => {
    const n = parseLimit(value);
    return Number.isInteger(n) && n >= 0 && n <= 1_000_000 ? null : t('clients.limit_invalid');
  };

  const errors = $derived({
    name: name.length > 64 ? t('clients.name_too_long') : null,
    up: limitError(up),
    down: limitError(down),
    fixedIp: fixed && !isIPv4(fixedIp) ? t('validation.ipv4') : null,
  });
  const valid = $derived(Object.values(errors).every((e) => e === null));

  const typeOptions = $derived([
    { value: '' as const, label: t('clients.type_auto') },
    ...CLIENT_TYPES.map((value) => ({ value, label: t(`clients.types.${value}`) })),
  ]);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    busy = true;
    const ok = await apply(async () => {
      if (name !== (client.name ?? '') || kind !== (client.type ?? '')) await setClientInfo(client.mac, name, kind);
      if (blocked !== client.blocked) await setClientBlocked(client.mac, blocked);
      if (parseLimit(up) !== client.up_limit || parseLimit(down) !== client.down_limit)
        await setClientLimit(client.mac, parseLimit(up), parseLimit(down));
      if (fixed && fixedIp !== client.reserved_ip) await setReservation(client.mac, fixedIp);
      if (!fixed && client.reserved_ip) await deleteReservation(client.mac);
      return true;
    });
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }
</script>

<Dialog bind:open title={clientLabel(client)}>
  <form id={formId} onsubmit={save}>
    <dl>
      <DataRow label={t('clients.mac')}>{client.mac.toUpperCase()}</DataRow>
      <DataRow label={t('clients.ip')}>{client.ip ?? t('common.unavailable')}</DataRow>
      <DataRow label={t('clients.connection')}>
        {client.connection === 'wifi'
          ? t('clients.via_wifi', { band: client.band ? t(`bands.${client.band}`) : '' })
          : client.connection === 'wired'
            ? t('clients.via_wired')
            : t('common.unavailable')}
      </DataRow>
      {#if client.signal !== null}
        <DataRow label={t('clients.signal')}>{t('clients.signal_value', { dbm: client.signal })}</DataRow>
      {/if}
    </dl>
    {#if client.random_mac}<Banner kind="info">{t('clients.random_mac_hint')}</Banner>{/if}

    <fieldset>
      <legend>{t('clients.identity')}</legend>
      <TextField label={t('clients.name')} bind:value={name} placeholder={client.hostname ?? ''} hint={t('clients.name_hint')} error={errors.name} maxlength={64} />
      <Select label={t('clients.type')} bind:value={kind} options={typeOptions} />
    </fieldset>

    <fieldset>
      <legend>{t('clients.access')}</legend>
      <Switch label={t('clients.block')} description={t('clients.block_hint')} bind:checked={blocked} />
      <div class="pair">
        <TextField label={t('clients.up_limit')} bind:value={up} inputmode="numeric" suffix="KB/s" placeholder={t('clients.unlimited')} error={errors.up} />
        <TextField label={t('clients.down_limit')} bind:value={down} inputmode="numeric" suffix="KB/s" placeholder={t('clients.unlimited')} error={errors.down} />
      </div>
    </fieldset>

    <fieldset>
      <legend>{t('clients.address')}</legend>
      <Switch label={t('clients.fixed_ip')} description={t('clients.fixed_ip_hint')} bind:checked={fixed} />
      {#if fixed}
        <TextField label={t('clients.fixed_ip_address')} bind:value={fixedIp} inputmode="decimal" error={errors.fixedIp} />
      {/if}
    </fieldset>
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

  dl {
    margin: 0;
  }

  fieldset {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    margin: 0;
    padding: var(--space-4) 0 0;
    border: 0;
    border-top: 1px solid var(--color-border);
  }

  legend {
    padding: 0 0 var(--space-2);
    font-weight: 600;
  }

  .pair {
    display: grid;
    gap: var(--space-3);
  }

  @media (min-width: 480px) {
    .pair {
      grid-template-columns: 1fr 1fr;
    }
  }
</style>
