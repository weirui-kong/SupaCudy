<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Icon from '../../components/Icon.svelte';
  import { getInternetStatus, listClients, type ClientList, type InternetStatus } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { uplinkName } from '../../lib/uplink';
  import { href } from '../../lib/router.svelte';

  let { refreshMs = 5000 }: { refreshMs?: number } = $props();

  let internet = $state<InternetStatus | null>(null);
  let clients = $state<ClientList | null>(null);

  async function refresh() {
    // Each half shows "—" on its own when it cannot be read.
    const [i, c] = await Promise.allSettled([getInternetStatus(), listClients()]);
    internet = i.status === 'fulfilled' ? i.value : null;
    clients = c.status === 'fulfilled' ? c.value : null;
  }

  $effect(() => {
    refresh();
    const timer = setInterval(refresh, refreshMs);
    return () => clearInterval(timer);
  });

  const source = $derived.by(() => {
    const key = uplinkName(internet?.active);
    return key ? t(key) : null;
  });
  const online = $derived(clients?.clients.filter((c) => c.online) ?? null);
</script>

<nav class="topology" aria-label={t('overview.topology')}>
  <a class="node" href={href('internet')} class:bad={internet && !internet.internet}>
    <span class="icon"><Icon name="globe" size={28} /></span>
    <strong>{t('nav.internet')}</strong>
    <span class="detail">
      {#if !internet}{t('common.unavailable')}
      {:else if internet.internet}<Icon name="check" size={14} /> {source ?? t('internet.online')}
      {:else}<Icon name="error" size={14} /> {t('overview.offline')}{/if}
    </span>
  </a>
  <span class="link" class:down={internet && !internet.internet} aria-hidden="true"></span>
  <span class="node router">
    <span class="icon"><Icon name="router" size={28} /></span>
    <strong>{t('overview.this_router')}</strong>
  </span>
  <span class="link" aria-hidden="true"></span>
  <a class="node" href={href('clients')}>
    <span class="icon"><Icon name="device" size={28} /></span>
    <strong>{t('nav.clients')}</strong>
    <span class="detail">{online ? t('overview.clients_online', { count: online.length }) : t('common.unavailable')}</span>
  </a>
</nav>

<style>
  .topology {
    display: flex;
    align-items: center;
    padding: var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    background: var(--color-surface);
  }

  .node {
    flex: 1 1 0;
    min-width: 0;
    min-height: 44px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-2);
    border-radius: var(--radius-md);
    color: var(--color-text);
    text-align: center;
    text-decoration: none;
    overflow-wrap: anywhere;
  }

  a.node:hover {
    background: var(--color-surface-muted);
  }

  .icon {
    display: grid;
    place-items: center;
    width: 52px;
    height: 52px;
    border-radius: 50%;
    background: var(--color-accent-soft);
    color: var(--color-accent);
  }

  .bad .icon {
    background: var(--color-danger-soft);
    color: var(--color-danger);
  }

  .detail {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
  }

  .link {
    flex: 0 1 48px;
    min-width: 12px;
    height: 2px;
    margin-bottom: var(--space-6);
    background: var(--color-accent);
  }

  .link.down {
    background: repeating-linear-gradient(90deg, var(--color-danger) 0 4px, transparent 4px 8px);
  }
</style>
