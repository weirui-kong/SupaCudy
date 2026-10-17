<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import DataRow from '../components/DataRow.svelte';
  import Switch from '../components/Switch.svelte';
  import { getTailscale, logoutTailscale, safeLoginUrl, setTailscale, type TailscaleStatus } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';

  let ts = $state<TailscaleStatus | null>(null);
  let error = $state<string | null>(null);
  let busy = $state(false);
  let confirmLogout = $state(false);

  async function load() {
    try {
      ts = await getTailscale();
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  // Signing in happens in another tab, so the state is polled.
  $effect(() => {
    load();
    const timer = setInterval(load, 5000);
    return () => clearInterval(timer);
  });

  async function change(call: () => Promise<unknown>) {
    busy = true;
    const ok = (await apply(call)) !== null;
    busy = false;
    confirmLogout = false;
    // Settings are stored at once; the daemon's state follows a moment later.
    if (ok) {
      await load();
      setTimeout(load, 3000);
    }
  }

  const loginUrl = $derived(safeLoginUrl(ts?.login_url ?? null));
  const stateText = $derived.by(() => {
    if (!ts) return '';
    switch (ts.state) {
      case 'Running': return t('remote.state_running');
      case 'NeedsLogin': return t('remote.state_login');
      case 'NeedsMachineAuth': return t('remote.state_approval');
      case 'Starting': case 'NoState': return t('remote.state_starting');
      case 'Stopped': return t('remote.state_stopped');
      default: return t('remote.state_unknown');
    }
  });
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

{#if ts && !ts.installed}
  <Banner kind="warning">{t('remote.missing')}</Banner>
{:else if ts}
  <div class="grid">
    <Card title={t('remote.tailscale')}>
      <div class="stack">
        <p class="hint">{t('remote.hint')}</p>
        <Switch
          label={t('remote.enable')}
          checked={ts.enabled}
          disabled={busy}
          onchange={(v) => change(() => setTailscale(v, ts!.share_lan))}
        />
        {#if ts.enabled}
          <dl>
            <DataRow label={t('remote.status')}>
              <span class="state" class:ok={ts.state === 'Running'}>{stateText}</span>
            </DataRow>
            {#if ts.state === 'Running'}
              <DataRow label={t('remote.addresses')}>{ts.addresses.join(', ') || t('common.unavailable')}</DataRow>
              <DataRow label={t('remote.name')}>{ts.name ?? t('common.unavailable')}</DataRow>
              <DataRow label={t('remote.tailnet')}>{ts.tailnet ?? t('common.unavailable')}</DataRow>
            {/if}
          </dl>
          {#if loginUrl}
            <Banner kind="info">{t('remote.login_hint')}</Banner>
            <div class="actions">
              <a class="button-link" href={loginUrl} target="_blank" rel="noopener noreferrer">
                {t('remote.login')}<span class="visually-hidden"> {t('common.new_window')}</span>
              </a>
            </div>
          {:else if ts.state === 'NeedsMachineAuth'}
            <Banner kind="info">{t('remote.approval_hint')}</Banner>
          {/if}
        {/if}
      </div>
    </Card>

    {#if ts.enabled}
      <Card title={t('remote.share_title')}>
        <div class="stack">
          <Switch
            label={t('remote.share_lan')}
            description={t('remote.share_hint', { lan: ts.lan ?? t('common.unavailable') })}
            checked={ts.share_lan}
            disabled={busy}
            onchange={(v) => change(() => setTailscale(true, v))}
          />
          {#if ts.state === 'Running'}
            <div class="actions">
              <Button variant="ghost" disabled={busy} onclick={() => (confirmLogout = true)}>{t('remote.logout')}</Button>
            </div>
          {/if}
        </div>
      </Card>
    {/if}
  </div>
{:else if !error}
  <p>{t('common.loading')}</p>
{/if}

<ConfirmDialog
  bind:open={confirmLogout}
  title={t('remote.logout')}
  message={t('remote.logout_confirm')}
  consequence={t('remote.logout_consequence')}
  confirmLabel={t('remote.logout')}
  {busy}
  onconfirm={() => change(logoutTailscale)}
/>

<style>
  .grid {
    display: grid;
    gap: var(--space-4);
    align-items: start;
  }

  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  dl {
    margin: 0;
  }

  .state {
    font-weight: 600;
  }

  .state.ok {
    color: var(--color-success);
  }

  .actions {
    display: flex;
    justify-content: flex-end;
  }

  .button-link {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding: 0 var(--space-4);
    border-radius: var(--radius-md);
    background: var(--color-accent);
    color: var(--color-on-accent);
    font-weight: 600;
    text-decoration: none;
  }

  .button-link:hover {
    background: var(--color-accent-hover);
  }

  .button-link:focus-visible {
    outline: 2px solid var(--color-focus);
    outline-offset: 2px;
  }

  @media (min-width: 1200px) {
    .grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
</style>
