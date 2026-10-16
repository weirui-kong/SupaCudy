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
  import { getDeviceInfo, getSystemStatus, type DeviceInfo, type SystemStatus } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { formatBytes, formatDuration, formatLoad } from '../lib/format';
  import { locale, t } from '../lib/i18n/index.svelte';

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
</script>

{#if error}
  <Banner kind="error">{error}</Banner>
{:else if refreshFailed}
  <Banner kind="warning">{t('overview.refresh_failed')}</Banner>
{/if}

<div class="grid">
  <Card title={t('overview.device')}>
    <dl>
      <DataRow label={t('overview.model')}>{show(info?.model)}</DataRow>
      <DataRow label={t('overview.board')}>{show(info?.board)}</DataRow>
      <DataRow label={t('overview.openwrt')}>
        {info?.openwrt ? `${info.openwrt}${info.revision ? ` (${info.revision})` : ''}` : t('common.unavailable')}
      </DataRow>
      <DataRow label={t('overview.supacudy')}>{show(info?.version)}</DataRow>
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
  </Card>
</div>

<style>
  .grid {
    display: grid;
    gap: var(--space-4);
    margin-top: var(--space-4);
  }

  dl {
    margin: 0 0 var(--space-3);
  }

  @media (min-width: 1024px) {
    .grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--space-5);
      align-items: start;
    }
  }
</style>
