<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import ParentalDialog from './schedules/ParentalDialog.svelte';
  import ScheduleCard from './schedules/ScheduleCard.svelte';
  import { deleteParentalRule, getSchedules, listClients, type Client, type ParentalRule, type ScheduleState } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';

  let sched = $state<ScheduleState | null>(null);
  let error = $state<string | null>(null);
  let clients = $state<Client[]>([]);
  let open = $state(false);
  let editing = $state<ParentalRule | null>(null);

  async function load() {
    try {
      sched = await getSchedules();
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load();
    listClients().then((l) => (clients = l.clients)).catch(() => {});
  });

  const dayList = (days: string[]) => (days.length === 7 ? t('schedules.every_day') : days.map((d) => t(`days.short_${d as 'mon'}`)).join(' '));

  async function remove(r: ParentalRule) {
    if (await apply(() => deleteParentalRule(r.id))) load();
  }
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

{#if sched}
  <div class="grid">
    <Card title={t('schedules.parental_title')}>
      <p class="hint">{t('schedules.parental_hint')}</p>
      {#if sched.parental.length === 0}
        <p class="hint">{t('ports.none')}</p>
      {:else}
        <ul>
          {#each sched.parental as r (r.id)}
            <li>
              <span class="label">
                <strong>{r.name}</strong>
                <span>
                  {t('schedules.rule_summary', { start: r.start, end: r.end, days: dayList(r.days), count: r.macs.length })}
                  {#if !r.enabled}· {t('ports.disabled')}{/if}
                </span>
              </span>
              <span class="buttons">
                <Button variant="ghost" icon="edit" label={t('common.edit_named', { name: r.name })} onclick={() => ((editing = r), (open = true))} />
                <Button variant="ghost" icon="trash" label={t('common.delete_named', { name: r.name })} onclick={() => remove(r)} />
              </span>
            </li>
          {/each}
        </ul>
      {/if}
      <div class="actions"><Button icon="plus" onclick={() => ((editing = null), (open = true))}>{t('schedules.add_parental')}</Button></div>
    </Card>
    <ScheduleCard kind="wifi_off" schedule={sched.wifi_off} onsaved={load} />
    <ScheduleCard kind="reboot" schedule={sched.reboot} onsaved={load} />
  </div>
{:else if !error}
  <p>{t('common.loading')}</p>
{/if}

<ParentalDialog bind:open rule={editing} {clients} onsaved={load} />

<style>
  .grid {
    display: grid;
    gap: var(--space-4);
    align-items: start;
  }

  .hint,
  .label span {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  ul {
    list-style: none;
    margin: var(--space-3) 0 0;
    padding: 0;
  }

  li {
    display: flex;
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

  .buttons {
    display: flex;
    flex: none;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    margin-top: var(--space-3);
  }

  @media (min-width: 1200px) {
    .grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .grid > :global(:first-child) {
      grid-column: 1 / -1;
    }
  }
</style>
