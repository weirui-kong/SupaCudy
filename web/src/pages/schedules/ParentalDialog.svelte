<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import DayPicker from '../../components/DayPicker.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import { WEEKDAYS, clientLabel, isTime, saveParentalRule, type Client, type ParentalRule, type Weekday } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let {
    open = $bindable(false),
    rule,
    clients,
    onsaved,
  }: { open?: boolean; rule: ParentalRule | null; clients: Client[]; onsaved: () => void } = $props();

  let name = $state('');
  let macs = $state<string[]>([]);
  let days = $state<Weekday[]>([]);
  let start = $state('22:00');
  let end = $state('07:00');
  let enabled = $state(true);
  let busy = $state(false);
  const uid = $props.id();
  const formId = `parental-${uid}`;

  $effect(() => {
    if (!open) return;
    name = rule?.name ?? t('schedules.bedtime');
    macs = [...(rule?.macs ?? [])];
    days = [...(rule?.days ?? WEEKDAYS)];
    start = rule?.start ?? '22:00';
    end = rule?.end ?? '07:00';
    enabled = rule?.enabled ?? true;
  });

  // Devices in the rule stay listed even while offline.
  const devices = $derived.by(() => {
    const list = new Map(clients.map((c) => [c.mac, clientLabel(c)]));
    for (const m of rule?.macs ?? []) if (!list.has(m)) list.set(m, m.toUpperCase());
    return [...list].map(([mac, label]) => ({ mac, label }));
  });

  const valid = $derived(
    !!name.trim() && name.length <= 64 && macs.length > 0 && days.length > 0 && isTime(start) && isTime(end) && start !== end,
  );

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    busy = true;
    const ok = await apply(() => saveParentalRule({ id: rule?.id ?? '', name: name.trim(), macs, days, start, end, enabled }));
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }
</script>

<Dialog bind:open title={rule ? t('common.edit_named', { name: rule.name }) : t('schedules.add_parental')}>
  <form id={formId} onsubmit={save}>
    <TextField label={t('vpn.name')} bind:value={name} autocomplete="off" />
    <fieldset>
      <legend>{t('schedules.devices')}</legend>
      {#if devices.length === 0}<p class="hint">{t('clients.none_online')}</p>{/if}
      {#each devices as d (d.mac)}
        <Switch
          label={d.label}
          checked={macs.includes(d.mac)}
          onchange={(on) => (macs = on ? [...macs, d.mac] : macs.filter((m) => m !== d.mac))}
        />
      {/each}
    </fieldset>
    <DayPicker label={t('schedules.days')} bind:days />
    <div class="times">
      <TextField label={t('schedules.offline_from')} type="time" bind:value={start} />
      <TextField label={t('schedules.offline_until')} type="time" bind:value={end} error={start === end ? t('schedules.end_invalid') : null} />
    </div>
    <p class="hint">{t('schedules.parental_note')}</p>
    <Switch label={t('ports.enabled')} bind:checked={enabled} />
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

  fieldset {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin: 0;
    padding: 0;
    border: 0;
  }

  legend {
    font-weight: 600;
    margin-bottom: var(--space-2);
  }

  .times {
    display: grid;
    gap: var(--space-3);
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }
</style>
