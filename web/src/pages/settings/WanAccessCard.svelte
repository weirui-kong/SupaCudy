<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Card from '../../components/Card.svelte';
  import Switch from '../../components/Switch.svelte';
  import { getWanAccess, setWanAccess, type WanAccess } from '../../lib/api';
  import { errorMessage } from '../../lib/errors';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let access = $state<WanAccess | null>(null);
  let error = $state<string | null>(null);
  let busy = $state(false);

  async function load() {
    try {
      access = await getWanAccess();
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load();
  });

  async function change(next: WanAccess) {
    busy = true;
    await apply(() => setWanAccess(next));
    busy = false;
    await load();
  }
</script>

<Card title={t('settings.wan_access')}>
  {#if error}<Banner kind="error">{error}</Banner>{/if}
  {#if access}
    <div class="stack">
      <p>{t('settings.wan_access_hint')}</p>
      <Switch
        label={t('settings.wan_webui')}
        description={t('settings.wan_webui_hint')}
        checked={access.webui}
        disabled={busy}
        onchange={(v) => change({ ...access!, webui: v })}
      />
      <Switch
        label={t('settings.wan_ssh')}
        description={t('settings.wan_ssh_hint')}
        checked={access.ssh}
        disabled={busy}
        onchange={(v) => change({ ...access!, ssh: v })}
      />
      {#if access.webui || access.ssh}
        <Banner kind="warning">{t('settings.wan_exposed')}</Banner>
      {/if}
    </div>
  {/if}
</Card>

<style>
  .stack {
    display: grid;
    gap: var(--space-3);
  }

  p {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }
</style>
