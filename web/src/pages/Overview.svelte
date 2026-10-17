<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Card from '../components/Card.svelte';
  import DataRow from '../components/DataRow.svelte';
  import InfoTip from '../components/InfoTip.svelte';
  import Meter from '../components/Meter.svelte';
  import Topology from './overview/Topology.svelte';
  import { getDeviceInfo, getSystemStatus, type DeviceInfo, type SystemStatus } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { formatBytes, formatDuration, formatLoad } from '../lib/format';
  import { locale, t } from '../lib/i18n/index.svelte';

  const SOURCE_URL = 'https://github.com/weirui-kong/SupaCudy';

  let { refreshMs = 5000 }: { refreshMs?: number } = $props();

  let info = $state<DeviceInfo | null>(null);
  let status = $state<SystemStatus | null>(null);
  let error = $state<string | null>(null);
  let refreshFailed = $state(false);

  const memoryUsed = $derived(status ? status.memory.total - status.memory.available : 0);

  async function loadInfo() {
    try {
      info = await getDeviceInfo();
    } catch (err) {
      error = errorMessage(err);
    }
  }

  async function loadStatus() {
    try {
      status = await getSystemStatus();
      refreshFailed = false;
    } catch (err) {
      if (status) refreshFailed = true;
      else error = errorMessage(err);
    }
  }

  $effect(() => {
    loadInfo();
    loadStatus();
    const timer = setInterval(loadStatus, refreshMs);
    return () => clearInterval(timer);
  });

  const show = (value: string | null | undefined) => value || t('common.unavailable');

  const temperatureText = $derived.by(() => {
    const temp = status?.temperature;
    if (!temp || (temp.cpu === null && temp.wifi === null)) return t('common.unavailable');
    const degrees = (c: number | null) =>
      c === null ? t('common.unavailable') : t('overview.degrees', { value: new Intl.NumberFormat(locale(), { maximumFractionDigits: 0 }).format(c) });
    return t('overview.temperature_value', { cpu: degrees(temp.cpu), wifi: degrees(temp.wifi) });
  });
</script>

{#if error}
  <Banner kind="error">{error}</Banner>
{:else if refreshFailed}
  <Banner kind="warning">{t('overview.refresh_failed')}</Banner>
{/if}

<Topology {refreshMs} />

<div class="grid">
  <Card title={t('overview.device')}>
    <dl>
      <DataRow label={t('overview.model')}>{show(info?.model)}</DataRow>
      <DataRow label={t('overview.board')}>{show(info?.board)}</DataRow>
      <DataRow label={t('overview.openwrt')}>
        {info?.openwrt ? `${info.openwrt}${info.revision ? ` (${info.revision})` : ''}` : t('common.unavailable')}
      </DataRow>
      <DataRow label={t('overview.supacudy')}>
        <span class="version">
          {show(info?.version)}
          <a
            class="source"
            href={SOURCE_URL}
            target="_blank"
            rel="noopener noreferrer"
            title={t('overview.source')}
            aria-label={`${t('overview.source')} ${t('common.new_window')}`}
          >
            <!-- GitHub's mark, from its MIT-licensed Octicons. -->
            <svg viewBox="0 0 16 16" width="20" height="20" aria-hidden="true" fill="currentColor">
              <path
                d="M8 0c4.42 0 8 3.58 8 8a8 8 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82a7.6 7.6 0 0 0-4 0c-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A8 8 0 0 1 0 8c0-4.42 3.58-8 8-8Z"
              />
            </svg>
          </a>
        </span>
      </DataRow>
    </dl>
  </Card>

  <Card title={t('overview.system')}>
    <dl>
      <DataRow label={t('overview.uptime')}>
        {status ? formatDuration(status.uptime, t) : t('common.unavailable')}
      </DataRow>
      <DataRow label={t('overview.load')}>
        {#snippet hint()}<InfoTip text={t('overview.load_hint')} />{/snippet}
        {status
          ? t('overview.load_value', {
              one: formatLoad(status.load[0], locale()),
              five: formatLoad(status.load[1], locale()),
              fifteen: formatLoad(status.load[2], locale()),
            })
          : t('common.unavailable')}
      </DataRow>
      <DataRow label={t('overview.cpus')}>{status ? status.cpus : t('common.unavailable')}</DataRow>
      <DataRow label={t('overview.temperature')}>{temperatureText}</DataRow>
      <DataRow label={t('overview.memory')}>
        {#snippet hint()}<InfoTip text={t('overview.memory_hint')} />{/snippet}
        {status
          ? t('overview.memory_value', {
              used: formatBytes(memoryUsed, locale()),
              total: formatBytes(status.memory.total, locale()),
            })
          : t('common.unavailable')}
      </DataRow>
    </dl>
    {#if status}
      <Meter label={t('overview.memory')} value={memoryUsed} max={status.memory.total} />
    {/if}
    <dl class="storage">
      <DataRow label={t('overview.storage')}>
        {status?.storage
          ? t('overview.memory_value', {
              used: formatBytes(status.storage.total - status.storage.available, locale()),
              total: formatBytes(status.storage.total, locale()),
            })
          : t('common.unavailable')}
      </DataRow>
    </dl>
    {#if status?.storage}
      <Meter label={t('overview.storage')} value={status.storage.total - status.storage.available} max={status.storage.total} />
    {/if}
  </Card>
</div>

<style>
  .version {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
  }

  .source {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: var(--touch-target);
    min-height: var(--touch-target);
    border-radius: var(--radius-md);
    color: var(--color-text-muted);
  }

  .source:hover {
    color: var(--color-text);
  }

  .grid {
    display: grid;
    gap: var(--space-4);
    margin-top: var(--space-4);
  }

  dl {
    margin: 0 0 var(--space-3);
  }

  .storage {
    margin-top: var(--space-3);
  }

  @media (min-width: 1024px) {
    .grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--space-5);
      align-items: start;
    }
  }
</style>
