<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import DataRow from '../../components/DataRow.svelte';
  import Select from '../../components/Select.svelte';
  import Switch from '../../components/Switch.svelte';
  import { getTimeSettings, setTimeSettings, type TimeSettings } from '../../lib/api';
  import { errorMessage } from '../../lib/errors';
  import { formatClock, ianaZone } from '../../lib/format';
  import { locale, t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  // A router clock further off than this is worth fixing by hand.
  const DRIFT_SECONDS = 120;

  let settings = $state<TimeSettings | null>(null);
  let error = $state<string | null>(null);
  let zonename = $state('UTC');
  let ntp = $state(true);
  // Router clock minus browser clock, so the display can tick locally.
  let offset = $state(0);
  let now = $state(Date.now());
  let busy = $state(false);

  async function load() {
    try {
      const s = await getTimeSettings();
      settings = s;
      zonename = s.zonename;
      ntp = s.ntp;
      offset = s.time * 1000 - Date.now();
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load();
    const timer = setInterval(() => (now = Date.now()), 1000);
    return () => clearInterval(timer);
  });

  const browserZone = $derived.by(() => {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    // The router's table spells zones with spaces ("America/New York").
    const name = zone?.replace(/_/g, ' ');
    return name && settings?.zones.includes(name) ? name : null;
  });
  const options = $derived((settings?.zones ?? []).map((z) => ({ value: z, label: z })));
  const changed = $derived(!!settings && (zonename !== settings.zonename || ntp !== settings.ntp));
  const drifting = $derived(Math.abs(offset) > DRIFT_SECONDS * 1000);
  const routerClock = $derived(settings ? formatClock(now + offset, ianaZone(settings.zonename), locale()) : null);

  async function save(copyBrowserClock = false) {
    busy = true;
    const ok = await apply(() =>
      setTimeSettings(zonename, ntp, copyBrowserClock ? Math.floor(Date.now() / 1000) : 0),
    );
    busy = false;
    if (ok) await load();
  }
</script>

<Card title={t('settings.time')}>
  {#if error}<Banner kind="error">{error}</Banner>{/if}
  {#if settings}
    <div class="stack">
      <dl>
        <DataRow label={t('settings.router_time')}>{routerClock ?? t('common.unavailable')}</DataRow>
      </dl>
      {#if drifting}
        <Banner kind="warning">{t('settings.clock_drift')}</Banner>
      {/if}
      <Select label={t('settings.timezone')} bind:value={zonename} {options} />
      {#if browserZone && browserZone !== zonename}
        <div>
          <Button variant="ghost" icon="pin" onclick={() => (zonename = browserZone)}>
            {t('settings.use_browser_zone', { zone: browserZone })}
          </Button>
        </div>
      {/if}
      <Switch label={t('settings.ntp')} description={t('settings.ntp_hint')} bind:checked={ntp} />
      <div class="actions">
        <Button icon="clock" onclick={() => save(true)} disabled={busy}>{t('settings.sync_clock')}</Button>
        <Button variant="primary" onclick={() => save()} {busy} disabled={!changed}>{t('common.apply')}</Button>
      </div>
    </div>
  {:else if !error}
    <p>{t('common.loading')}</p>
  {/if}
</Card>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  dl {
    margin: 0;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: var(--space-3);
  }
</style>
