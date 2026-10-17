<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import AppearanceControls from '../components/AppearanceControls.svelte';
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Icon from '../components/Icon.svelte';
  import Select from '../components/Select.svelte';
  import TextField from '../components/TextField.svelte';
  import JoinDialog from './internet/JoinDialog.svelte';
  import WanDialog from './internet/WanDialog.svelte';
  import NetworkFields from './wireless/NetworkFields.svelte';
  import {
    ENCRYPTIONS, PASSWORD_MIN, completeSetup, getInternetStatus, getTimeSettings, getWifi, passwordError,
    setAdminPassword, setTimeSettings, setWifi, type Encryption, type InternetStatus, type Radio, type TimeSettings,
  } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';
  import { uplinkName } from '../lib/uplink';
  import { apply } from '../lib/notify.svelte';

  let { passwordSet, ondone }: { passwordSet: boolean; ondone: () => void } = $props();

  const STEPS = ['password', 'wifi', 'internet', 'done'] as const;
  type Step = (typeof STEPS)[number];
  let step = $state<Step>('password');
  const index = $derived(STEPS.indexOf(step));

  // Password
  let password = $state('');
  let confirm = $state('');
  let passwordChanged = $state(false);
  const passwordProblem = $derived(password ? passwordError(password) : null);
  const passwordMessage = $derived(
    passwordProblem === 'too_short' ? t('settings.password_too_short', { min: PASSWORD_MIN })
      : passwordProblem === 'too_long' ? t('settings.password_too_long', { max: 128 })
        : passwordProblem === 'invalid' ? t('settings.password_invalid')
          : passwordProblem === 'default' ? t('settings.password_default') : null,
  );
  const confirmMessage = $derived(confirm && confirm !== password ? t('settings.password_mismatch') : null);
  const passwordReady = $derived(!!password && !passwordProblem && confirm === password);

  // Wi-Fi
  let radios = $state<Radio[]>([]);
  let wifiError = $state<string | null>(null);
  let ssid = $state('');
  let encryption = $state<Encryption>('psk2');
  let key = $state('');
  let hidden = $state(false);
  let wifiErrors = $state<{ ssid: string | null; key: string | null }>({ ssid: null, key: null });
  let original = $state('');
  // Offer only what every radio supports, since one network spans them all.
  const encryptions = $derived(
    ENCRYPTIONS.filter((e) => radios.length > 0 && radios.every((r) => r.encryptions.includes(e))),
  );
  const wifiChanged = $derived(radios.length > 0 && JSON.stringify({ ssid, encryption, key, hidden }) !== original);

  // Internet
  let internet = $state<InternetStatus | null>(null);
  let wanOpen = $state(false);
  let joinOpen = $state(false);

  // Time zone: a fresh router runs on UTC, so suggest the browser's.
  let time = $state<TimeSettings | null>(null);
  let zonename = $state('UTC');
  const zoneOptions = $derived((time?.zones ?? []).map((z) => ({ value: z, label: z })));

  let busy = $state(false);
  let confirmOpen = $state(false);

  $effect(() => {
    getTimeSettings()
      .then((ts) => {
        time = ts;
        const browser = Intl.DateTimeFormat().resolvedOptions().timeZone?.replace(/_/g, ' ');
        zonename = ts.zonename === 'UTC' && browser && ts.zones.includes(browser) ? browser : ts.zonename;
      })
      .catch(() => (time = null));
  });

  $effect(() => {
    getWifi()
      .then((w) => {
        radios = w.radios;
        const first = w.radios[0]?.main;
        if (first) {
          ({ ssid, encryption, key, hidden } = first);
          original = JSON.stringify({ ssid, encryption, key, hidden });
        }
      })
      .catch((err) => (wifiError = errorMessage(err)));
  });

  $effect(() => {
    if (step !== 'internet') return;
    const load = () => getInternetStatus().then((s) => (internet = s)).catch(() => (internet = null));
    load();
    const timer = setInterval(load, 5000);
    return () => clearInterval(timer);
  });

  async function savePassword(event: SubmitEvent) {
    event.preventDefault();
    if (!passwordReady) return;
    busy = true;
    const ok = await apply(() => setAdminPassword(password), t('settings.password_changed'));
    busy = false;
    if (ok) {
      passwordChanged = true;
      password = confirm = '';
      step = 'wifi';
    }
  }

  async function finish() {
    busy = true;
    const ok = await apply(async () => {
      await completeSetup();
      if (time && zonename !== time.zonename) {
        // Without NTP yet, the browser clock is the best guess.
        const drift = Math.abs(time.time * 1000 - Date.now()) > 120_000;
        await setTimeSettings(zonename, time.ntp, drift ? Math.floor(Date.now() / 1000) : 0);
      }
      if (!wifiChanged) return true;
      for (const r of radios) {
        await setWifi({
          radio: r.name, enabled: true, channel: String(r.channel), width: r.width, txpower: r.txpower,
          ssid, encryption, key, hidden,
        });
      }
      return true;
    }, t('setup.finished'));
    busy = false;
    confirmOpen = false;
    if (ok) ondone();
  }

  const source = $derived.by(() => {
    const key = uplinkName(internet?.active);
    return key ? t(key) : null;
  });
</script>

<main class="page" id="main">
  <div class="panel">
    <span class="brand"><Icon name="router" size={28} />{t('app.name')}</span>
    <ol class="steps" aria-label={t('setup.progress', { step: index + 1, total: STEPS.length })}>
      {#each STEPS as s, i (s)}
        <li class:current={i === index} class:complete={i < index} aria-current={i === index ? 'step' : undefined}>
          <span class="dot" aria-hidden="true">{#if i < index}<Icon name="check" size={16} />{:else}{i + 1}{/if}</span>
          <span class="label">{t(`setup.step_${s}`)}</span>
        </li>
      {/each}
    </ol>

    {#if step === 'password'}
      <h1>{t('setup.welcome')}</h1>
      <p class="lead">{t('setup.welcome_hint')}</p>
      <AppearanceControls compact />
      <form onsubmit={savePassword}>
        <h2>{t('settings.password')}</h2>
        <p class="lead">{passwordSet ? t('setup.password_optional') : t('setup.password_required')}</p>
        <TextField
          label={t('settings.password_new')}
          type="password"
          revealable
          autocomplete="new-password"
          bind:value={password}
          hint={t('settings.password_rule', { min: PASSWORD_MIN })}
          error={passwordMessage}
        />
        <TextField
          label={t('settings.password_confirm')}
          type="password"
          revealable
          autocomplete="new-password"
          bind:value={confirm}
          error={confirmMessage}
        />
        <div class="actions">
          {#if passwordSet}
            <Button variant="ghost" onclick={() => (step = 'wifi')}>{t('setup.keep_password')}</Button>
          {/if}
          <Button variant="primary" type="submit" {busy} disabled={!passwordReady}>{t('setup.next')}</Button>
        </div>
      </form>
    {:else if step === 'wifi'}
      <h1>{t('setup.step_wifi')}</h1>
      <p class="lead">{t('setup.wifi_hint')}</p>
      {#if wifiError}<Banner kind="error">{wifiError}</Banner>{/if}
      {#if radios.length > 0}
        <div class="fields">
          <NetworkFields bind:ssid bind:encryption bind:key bind:hidden {encryptions} bind:errors={wifiErrors} />
        </div>
      {:else if !wifiError}
        <p>{t('common.loading')}</p>
      {/if}
      <div class="actions">
        <Button onclick={() => (step = 'password')}>{t('internet.back')}</Button>
        <Button variant="primary" disabled={!!(wifiErrors.ssid || wifiErrors.key)} onclick={() => (step = 'internet')}>
          {t('setup.next')}
        </Button>
      </div>
    {:else if step === 'internet'}
      <h1>{t('setup.step_internet')}</h1>
      <p class="lead">{t('setup.internet_hint')}</p>
      <div class="status" class:offline={internet && !internet.internet} role="status">
        {#if !internet}
          {t('common.loading')}
        {:else if internet.internet}
          <Icon name="check" /> {t('internet.online')} · {source ?? ''}
        {:else}
          <Icon name="error" /> {t('internet.offline')}
        {/if}
      </div>
      <div class="choices">
        <Button icon="ethernet" onclick={() => (wanOpen = true)}>{t('internet.ethernet_settings')}</Button>
        <Button icon="wifi" onclick={() => (joinOpen = true)}>{t('internet.choose_network')}</Button>
      </div>
      <div class="actions">
        <Button onclick={() => (step = 'wifi')}>{t('internet.back')}</Button>
        <Button variant="primary" onclick={() => (step = 'done')}>
          {internet?.internet ? t('setup.next') : t('setup.skip')}
        </Button>
      </div>
    {:else}
      <h1>{t('setup.step_done')}</h1>
      <p class="lead">{t('setup.done_hint')}</p>
      <ul class="summary">
        <li><Icon name="key" /> {passwordChanged ? t('setup.summary_password') : t('setup.summary_password_kept')}</li>
        <li><Icon name="wifi" /> {t('setup.summary_wifi', { ssid })}</li>
      </ul>
      {#if time}
        <Select label={t('settings.timezone')} bind:value={zonename} options={zoneOptions} />
      {/if}
      {#if wifiChanged}
        <Banner kind="warning">{t('setup.wifi_reconnect', { ssid })}</Banner>
      {/if}
      <div class="actions">
        <Button onclick={() => (step = 'internet')} disabled={busy}>{t('internet.back')}</Button>
        <Button variant="primary" {busy} onclick={() => (wifiChanged ? (confirmOpen = true) : finish())}>
          {t('setup.finish')}
        </Button>
      </div>
    {/if}
  </div>
</main>

<WanDialog bind:open={wanOpen} onsaved={() => {}} />
<JoinDialog bind:open={joinOpen} onjoined={() => {}} />
<ConfirmDialog
  bind:open={confirmOpen}
  title={t('setup.finish')}
  message={t('setup.finish_confirm')}
  consequence={t('setup.wifi_reconnect', { ssid })}
  confirmLabel={t('setup.finish')}
  {busy}
  onconfirm={finish}
/>

<style>
  .page {
    min-height: 100vh;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding: var(--space-4);
    background: var(--color-bg);
  }

  .panel {
    width: 100%;
    max-width: 560px;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    padding: var(--space-5) var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    background: var(--color-surface);
  }

  .brand {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-weight: 700;
  }

  .steps {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: var(--space-2);
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .steps li {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
    text-align: center;
  }

  .steps li.current {
    color: var(--color-text);
    font-weight: 600;
  }

  .dot {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    border: 2px solid var(--color-border);
  }

  .current .dot {
    border-color: var(--color-accent);
    color: var(--color-accent);
  }

  .complete .dot {
    border-color: var(--color-success);
    background: var(--color-success-soft);
    color: var(--color-success);
  }

  h1 {
    font-size: var(--font-size-xl);
  }

  h2 {
    font-size: var(--font-size-md);
  }

  .lead {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  form,
  .fields {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .status {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-3);
    border-radius: var(--radius-md);
    background: var(--color-success-soft);
  }

  .status :global(svg) {
    color: var(--color-success);
  }

  .status.offline {
    background: var(--color-danger-soft);
  }

  .status.offline :global(svg) {
    color: var(--color-danger);
  }

  .choices {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-3);
  }

  .summary {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin: 0;
    padding: 0;
    list-style: none;
    overflow-wrap: anywhere;
  }

  .summary li {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: var(--space-3);
  }

  @media (min-width: 768px) {
    .page {
      align-items: center;
      padding: var(--space-6);
    }

    .panel {
      padding: var(--space-6);
    }
  }
</style>
