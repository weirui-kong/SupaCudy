<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import Segmented from '../components/Segmented.svelte';
  import Select from '../components/Select.svelte';
  import Switch from '../components/Switch.svelte';
  import TextField from '../components/TextField.svelte';
  import HostsCard from './dns/HostsCard.svelte';
  import {
    DNS_MODES, dohUrlError, getDns, isKnownProvider, setDns, setRebindProtection, type DnsMode, type DnsSettings,
  } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';
  import { isIPv4 } from '../lib/validate';

  let settings = $state<DnsSettings | null>(null);
  let error = $state<string | null>(null);
  let mode = $state<DnsMode>('auto');
  let dns1 = $state('');
  let dns2 = $state('');
  let provider = $state('alidns');
  let url = $state('');
  let busy = $state(false);

  async function load() {
    try {
      const s = await getDns();
      settings = s;
      mode = s.mode;
      [dns1 = '', dns2 = ''] = s.servers;
      provider = s.provider;
      url = s.url;
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load();
  });

  const modeOptions = $derived(
    DNS_MODES.filter((m) => m !== 'encrypted' || settings?.encrypted_available).map((value) => ({
      value,
      label: t(`dns.mode_${value}`),
    })),
  );
  const providerOptions = $derived([
    ...(settings?.providers ?? []).map((value) => ({
      value,
      label: isKnownProvider(value) ? t(`dns.providers.${value}`) : value,
    })),
    { value: 'custom', label: t('dns.provider_custom') },
  ]);

  const errors = $derived({
    dns1: mode === 'manual' && !isIPv4(dns1) ? (dns1 ? t('validation.ipv4') : t('dns.server_required')) : null,
    dns2: mode === 'manual' && dns2 && !isIPv4(dns2) ? t('validation.ipv4') : null,
    url: mode === 'encrypted' && provider === 'custom' && dohUrlError(url) ? t('dns.url_invalid') : null,
  });
  const valid = $derived(Object.values(errors).every((e) => e === null));
  const servers = $derived([dns1, dns2].filter(Boolean));
  const changed = $derived(
    !!settings &&
      (mode !== settings.mode ||
        (mode === 'manual' && servers.join() !== settings.servers.join()) ||
        (mode === 'encrypted' && (provider !== settings.provider || (provider === 'custom' && url !== settings.url)))),
  );

  async function save() {
    if (!valid) return;
    busy = true;
    const ok = await apply(() =>
      setDns({ mode, servers: mode === 'manual' ? servers : [], provider, url: provider === 'custom' ? url : '' }),
    );
    busy = false;
    if (ok) await load();
  }
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

{#if settings}
  <Card title={t('dns.title')}>
    <div class="stack">
      <Segmented label={t('dns.mode')} options={modeOptions} value={mode} onchange={(v: DnsMode) => (mode = v)} />
      <p class="hint">{t(`dns.mode_hint_${mode}`)}</p>

      {#if mode === 'manual'}
        <TextField label={t('internet.dns1')} bind:value={dns1} inputmode="decimal" placeholder="9.9.9.9" error={dns1 || changed ? errors.dns1 : null} />
        <TextField label={t('internet.dns2')} bind:value={dns2} inputmode="decimal" placeholder="1.1.1.1" error={errors.dns2} />
      {:else if mode === 'encrypted'}
        <Select label={t('dns.provider')} bind:value={provider} options={providerOptions} />
        {#if provider === 'custom'}
          <TextField
            label={t('dns.url')}
            type="url"
            bind:value={url}
            placeholder="https://dns.example/dns-query"
            autocomplete="off"
            spellcheck={false}
            error={url ? errors.url : null}
          />
        {/if}
        <Banner kind="info">{t('dns.encrypted_warning')}</Banner>
      {/if}
      {#if !settings.encrypted_available}
        <p class="hint">{t('dns.encrypted_missing')}</p>
      {/if}

      <div class="actions">
        <Button variant="primary" onclick={save} {busy} disabled={!changed || !valid}>{t('common.apply')}</Button>
      </div>
    </div>
  </Card>
  <div class="more">
    <Card title={t('dns.rebind')}>
      <Switch
        label={t('dns.rebind_enable')}
        description={t('dns.rebind_hint')}
        checked={settings.rebind_protection}
        onchange={async (v) => {
          await apply(() => setRebindProtection(v));
          await load();
        }}
      />
    </Card>
    <HostsCard hosts={settings.hosts} onsaved={load} />
  </div>
{:else if !error}
  <p>{t('common.loading')}</p>
{/if}

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    max-width: 640px;
  }

  .more {
    display: grid;
    gap: var(--space-4);
    margin-top: var(--space-4);
    max-width: 640px;
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
