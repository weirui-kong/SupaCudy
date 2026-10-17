<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import DayPicker from '../../components/DayPicker.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import { isTime, setSchedule, type Schedule, type Weekday } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let { kind, schedule, onsaved }: { kind: 'reboot' | 'wifi_off'; schedule: Schedule; onsaved: () => void } = $props();

  let enabled = $state(false);
  let days = $state<Weekday[]>([]);
  let start = $state('');
  let end = $state('');
  let busy = $state(false);

  $effect(() => {
    ({ enabled, start, end } = schedule);
    days = [...schedule.days];
  });

  const errors = $derived({
    days: enabled && days.length === 0 ? t('schedules.days_required') : null,
    start: isTime(start) ? null : t('schedules.time_invalid'),
    end: kind === 'reboot' || (isTime(end) && end !== start) ? null : t('schedules.end_invalid'),
  });
  const valid = $derived(!enabled || Object.values(errors).every((e) => e === null));
  const changed = $derived(
    enabled !== schedule.enabled || start !== schedule.start || (kind === 'wifi_off' && end !== schedule.end) ||
      days.join() !== schedule.days.join(),
  );

  async function save() {
    busy = true;
    const ok = await apply(() => setSchedule(kind, { enabled, days: days.length ? days : schedule.days, start, end }));
    busy = false;
    if (ok) onsaved();
  }
</script>

<Card title={t(`schedules.${kind}_title`)}>
  <div class="stack">
    <Switch label={t(`schedules.${kind}_enable`)} description={t(`schedules.${kind}_hint`)} bind:checked={enabled} />
    {#if enabled}
      <DayPicker label={t('schedules.days')} bind:days />
      {#if errors.days}<p class="error" role="alert">{errors.days}</p>{/if}
      <div class="times">
        <TextField label={kind === 'reboot' ? t('schedules.at') : t('schedules.off_at')} type="time" bind:value={start} error={errors.start} />
        {#if kind === 'wifi_off'}
          <TextField label={t('schedules.on_at')} type="time" bind:value={end} error={errors.end} />
        {/if}
      </div>
      {#if kind === 'wifi_off'}<p class="hint">{t('schedules.wifi_off_note')}</p>{/if}
    {/if}
    <div class="actions">
      <Button variant="primary" onclick={save} {busy} disabled={!changed || !valid}>{t('common.apply')}</Button>
    </div>
  </div>
</Card>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
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

  .error {
    color: var(--color-danger);
    font-size: var(--font-size-sm);
  }

  .actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
