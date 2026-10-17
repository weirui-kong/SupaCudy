<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Icon from '../components/Icon.svelte';
  import Segmented from '../components/Segmented.svelte';
  import TextField from '../components/TextField.svelte';
  import { LOG_LINES, getLogs, isProblem, logText, type LogEntry } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';

  type Filter = 'all' | 'problems' | 'kernel';

  let entries = $state<LogEntry[] | null>(null);
  let error = $state<string | null>(null);
  let busy = $state(false);
  let filter = $state<Filter>('all');
  let search = $state('');
  let confirmExport = $state(false);

  async function load() {
    busy = true;
    try {
      entries = (await getLogs()).entries;
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
    busy = false;
  }

  $effect(() => {
    load();
  });

  const shown = $derived.by(() => {
    const needle = search.trim().toLowerCase();
    return (entries ?? [])
      .filter((e) => filter === 'all' || (filter === 'problems' ? isProblem(e) : e.facility === 'kern'))
      .filter((e) => !needle || `${e.source ?? ''} ${e.message}`.toLowerCase().includes(needle))
      .reverse();
  });

  const filters = $derived([
    { value: 'all' as Filter, label: t('logs.filter_all') },
    { value: 'problems' as Filter, label: t('logs.filter_problems') },
    { value: 'kernel' as Filter, label: t('logs.filter_kernel') },
  ]);

  function download() {
    const blob = new Blob([logText(entries ?? [])], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `supacudy-log-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')}.txt`;
    a.click();
    URL.revokeObjectURL(url);
    confirmExport = false;
  }
</script>

<Card title={t('logs.system_log')}>
  <div class="toolbar">
    <Segmented label={t('logs.show')} options={filters} value={filter} onchange={(v: Filter) => (filter = v)} />
    <div class="search"><TextField label={t('logs.search')} type="text" bind:value={search} autocomplete="off" /></div>
    <div class="buttons">
      <Button icon="refresh" onclick={load} {busy}>{t('logs.refresh')}</Button>
      <Button icon="download" onclick={() => (confirmExport = true)} disabled={!entries?.length}>{t('logs.export')}</Button>
    </div>
  </div>

  {#if error}<Banner kind="error">{error}</Banner>{/if}
  {#if entries}
    <p class="count" aria-live="polite">{t('logs.count', { shown: shown.length, total: entries.length })}</p>
    {#if shown.length === 0}
      <p class="empty">{t('logs.none')}</p>
    {:else}
      <ol class="log" aria-label={t('logs.system_log')}>
        {#each shown as e, i (i)}
          <li class:problem={isProblem(e)}>
            <span class="meta">
              {#if isProblem(e)}<Icon name="warning" size={14} />{/if}
              <span class="level">{e.level ?? ''}</span>
              <time>{e.time ?? ''}</time>
              <span class="source">{e.source ?? ''}</span>
            </span>
            <span class="message">{e.message}</span>
          </li>
        {/each}
      </ol>
    {/if}
  {:else if !error}
    <p>{t('common.loading')}</p>
  {/if}
</Card>

<ConfirmDialog
  bind:open={confirmExport}
  title={t('logs.export')}
  message={t('logs.export_confirm', { lines: entries?.length ?? LOG_LINES })}
  consequence={t('logs.export_privacy')}
  confirmLabel={t('logs.export')}
  onconfirm={download}
/>

<style>
  .toolbar {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    margin-bottom: var(--space-3);
  }

  .buttons {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-3);
  }

  .count,
  .empty {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
    margin-bottom: var(--space-2);
  }

  .log {
    list-style: none;
    margin: 0;
    padding: 0;
    font-family: var(--font-mono);
    font-size: var(--font-size-xs);
  }

  .log li {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
    overflow-wrap: anywhere;
  }

  .meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-2);
    color: var(--color-text-muted);
  }

  .problem .meta {
    color: var(--color-warning);
  }

  .level {
    font-weight: 700;
    text-transform: uppercase;
  }

  @media (min-width: 1024px) {
    .toolbar {
      flex-direction: row;
      align-items: flex-end;
      flex-wrap: wrap;
    }

    .search {
      flex: 1;
      min-width: 220px;
    }

    .log li {
      flex-direction: row;
      gap: var(--space-3);
    }

    .meta {
      flex: none;
      width: 360px;
      flex-wrap: nowrap;
    }
  }
</style>
