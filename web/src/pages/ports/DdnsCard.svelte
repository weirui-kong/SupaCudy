<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import DataRow from '../../components/DataRow.svelte';
  import Select from '../../components/Select.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import { domainError, getDdns, setDdns, type DdnsState } from '../../lib/api';
  import { formatClock } from '../../lib/format';
  import { locale, t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

    let ddns = $state<DdnsState | null>(null);
  let enabled = $state(false);
  let service = $state('');
  let domain = $state('');
  let username = $state('');
  let password = $state('');
  let busy = $state(false);

  async function load() {
    try {
      const d = await getDdns();
      ddns = d;
      ({ enabled, service, domain, username } = d);
      service ||= d.services[0] ?? '';
      password = '';
    } catch {
      ddns = null;
    }
  }

  $effect(() => {
    load();
  });

  const errors = $derived({
    domain: enabled && domain && domainError(domain) ? t('ddns.domain_invalid') : null,
    password: enabled && !password && !ddns?.has_password ? t('ddns.password_required') : null,
  });
  const valid = $derived(!enabled || (!!domain && !errors.domain && !errors.password));
  const options = $derived((ddns?.services ?? []).map((s) => ({ value: s, label: s })));

  async function save() {
    busy = true;
    const ok = await apply(() => setDdns({ enabled, service, domain: domain.trim(), username: username.trim(), password }));
    busy = false;
    if (ok) {
      await load();
    }
  }
</script>

{#if ddns?.available}
  <Card title={t('ddns.title')}>
    <div class="stack">
      <p class="hint">{t('ddns.hint')}</p>
      <Switch label={t('ddns.enable')} bind:checked={enabled} />
      {#if enabled}
        <Select label={t('ddns.service')} bind:value={service} {options} />
        <TextField label={t('ddns.domain')} bind:value={domain} placeholder="myhome.duckdns.org" autocomplete="off" spellcheck={false} error={errors.domain} />
        <TextField label={t('vpn.username')} bind:value={username} hint={t('ddns.username_hint')} autocomplete="off" />
        <TextField
          label={t('ddns.password')}
          type="password"
          revealable
          bind:value={password}
          autocomplete="off"
          placeholder={ddns.has_password ? t('vpn.keep_key') : ''}
          error={errors.password}
        />
      {/if}
      {#if ddns.enabled}
        <dl>
          <DataRow label={t('ddns.ip')}>{ddns.ip ?? t('common.unavailable')}</DataRow>
          <DataRow label={t('ddns.updated')}>
            {ddns.last_update ? formatClock(ddns.last_update * 1000, Intl.DateTimeFormat().resolvedOptions().timeZone, locale()) : t('vpn.never')}
          </DataRow>
        </dl>
      {/if}
      <div class="actions">
        <Button variant="primary" onclick={save} {busy} disabled={!valid}>{t('common.apply')}</Button>
      </div>
    </div>
  </Card>
{/if}

<style>
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

  .actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
