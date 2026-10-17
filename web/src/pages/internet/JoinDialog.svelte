<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Icon from '../../components/Icon.svelte';
  import SignalBars from '../../components/SignalBars.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import EapFields from './EapFields.svelte';
  import {
    connectRepeater, getJoinStatus, getSavedNetworks, groupNetworks, joinable, needsPassword, pickAccessPoint, scanNetworks,
    usesKey, type EapSettings, type JoinFailure, type NetworkGroup, type ScannedNetwork, type SavedNetworks,
  } from '../../lib/api';
  import { errorMessage } from '../../lib/errors';
  import { t } from '../../lib/i18n/index.svelte';

  let { open = $bindable(false), onjoined }: { open?: boolean; onjoined: () => void } = $props();

  // The router reports the result itself; joining takes up to its own 45 s
  // limit plus the wifi reload, so the dialog gives up a little later.
  const POLL_MS = 2000;
  const GIVE_UP_MS = 90_000;

  type Step = 'list' | 'form' | 'joining' | 'connected' | 'failed';

  let networks = $state<ScannedNetwork[]>([]);
  let saved = $state<SavedNetworks['networks']>([]);
  let scanning = $state(false);
  let scanError = $state<string | null>(null);
  let step = $state<Step>('list');
  let chosen = $state<NetworkGroup | null>(null);
  let key = $state('');
  let eap = $state<EapSettings>(blankEap());
  let eapValid = $state(false);
  let save = $state(true);
  let busy = $state(false);
  let joinError = $state<string | null>(null);
  let failure = $state<JoinFailure | null>(null);
  let address = $state<string | null>(null);
  // Bumped to stop the polling of an earlier attempt.
  let attempt = 0;
  const uid = $props.id();
  const formId = `join-${uid}`;

  function blankEap(): EapSettings {
    return { method: 'peap', identity: '', anonymous_identity: '', password: '', phase2: 'MSCHAPV2', validate: false, domain: '' };
  }

  async function scan() {
    scanning = true;
    scanError = null;
    try {
      const [found, known] = await Promise.all([scanNetworks(), getSavedNetworks()]);
      networks = found.networks;
      saved = known.networks;
    } catch (err) {
      scanError = errorMessage(err);
    }
    scanning = false;
  }

  $effect(() => {
    if (!open) {
      attempt++;
      return;
    }
    step = 'list';
    chosen = null;
    scan();
  });

  const grouped = $derived(groupNetworks(networks));
  const enterprise = $derived(chosen?.encryption === 'enterprise');

  const keyError = $derived(
    chosen && usesKey(chosen.encryption) && !(chosen.saved && key === '')
      ? key.length < 8 ? t('wifi.key_too_short') : key.length > 63 ? t('wifi.key_too_long') : null
      : null,
  );
  const canJoin = $derived(!!chosen && (enterprise ? eapValid : !keyError));

  const bandsText = (g: NetworkGroup) => g.bands.map((b) => t(`bands.${b}`)).join(' · ');

  function pick(g: NetworkGroup) {
    if (!joinable(g.encryption)) return;
    chosen = g;
    key = '';
    save = true;
    const known = saved.find((n) => n.ssid === g.ssid)?.eap;
    eap = known ? { ...known, password: '' } : blankEap();
    joinError = null;
    step = 'form';
  }

  async function join(event: SubmitEvent) {
    event.preventDefault();
    if (!chosen || !canJoin) return;
    const target = chosen;
    const ap = pickAccessPoint(target);
    busy = true;
    joinError = null;
    try {
      await connectRepeater({
        ssid: target.ssid, bssid: '', encryption: target.encryption, key: enterprise ? '' : key, band: ap.band, save,
        ...(enterprise ? { eap: { ...eap, identity: eap.identity.trim(), domain: eap.domain.trim() } } : {}),
      });
    } catch (err) {
      busy = false;
      joinError = errorMessage(err);
      return;
    }
    busy = false;
    step = 'joining';
    onjoined();
    follow(++attempt);
  }

  async function follow(id: number) {
    const started = Date.now();
    while (id === attempt) {
      await new Promise((r) => setTimeout(r, POLL_MS));
      if (id !== attempt) return;
      try {
        const status = await getJoinStatus();
        if (status.state === 'connected') {
          address = status.ipaddr;
          step = 'connected';
          onjoined();
          return;
        }
        if (status.state === 'failed') {
          failure = status.reason ?? 'timeout';
          step = 'failed';
          return;
        }
      } catch {
        // The wifi reload can cut this device off for a moment.
      }
      if (Date.now() - started > GIVE_UP_MS) {
        failure = 'timeout';
        step = 'failed';
        return;
      }
    }
  }

  const title = $derived(
    step === 'list' || !chosen ? t('internet.choose_network') : t('internet.join_named', { ssid: chosen.ssid }),
  );
</script>

<Dialog bind:open {title}>
  {#if step === 'list'}
    <div class="scan-bar">
      <p class="hint" aria-live="polite">{scanning ? t('internet.scanning') : t('internet.found', { count: grouped.length })}</p>
      <Button icon="refresh" variant="ghost" onclick={scan} busy={scanning}>{t('internet.rescan')}</Button>
    </div>
    {#if scanError}<Banner kind="error">{scanError}</Banner>{/if}
    <ul class="networks">
      {#each grouped as g (g.ssid)}
        <li>
          <button type="button" onclick={() => pick(g)} disabled={!joinable(g.encryption)} aria-current={g.current || undefined}>
            <SignalBars dbm={g.signal} />
            <span class="ssid">
              <strong>{g.ssid}</strong>
              <span class="meta">
                {bandsText(g)} · {t(`internet.security.${g.encryption}`)}
                {#if g.current}· {t('internet.current')}{:else if g.saved}· {t('internet.saved')}{/if}
                {#if !joinable(g.encryption)}· {t('internet.unsupported')}{/if}
              </span>
            </span>
            {#if needsPassword(g.encryption)}
              <span class="lock"><Icon name="lock" size={16} /><span class="visually-hidden">{t('internet.secured')}</span></span>
            {:else}
              <span class="open">{t('internet.open')}</span>
            {/if}
          </button>
        </li>
      {/each}
    </ul>
  {:else if step === 'form' && chosen}
    <form id={formId} onsubmit={join}>
      <dl class="facts">
        <div><dt>{t('internet.security_label')}</dt><dd>{t(`internet.security.${chosen.encryption}`)}</dd></div>
        <div><dt>{t('internet.band')}</dt><dd>{bandsText(chosen)}</dd></div>
      </dl>
      {#if enterprise}
        <EapFields bind:eap bind:valid={eapValid} savedPassword={chosen.saved} />
      {:else if usesKey(chosen.encryption)}
        <TextField
          label={t('wifi.key')}
          type="password"
          revealable
          bind:value={key}
          autocomplete="off"
          placeholder={chosen.saved ? t('internet.saved_password') : ''}
          error={key || !chosen.saved ? keyError : null}
        />
      {:else}
        <Banner kind="warning">{t('internet.open_upstream')}</Banner>
      {/if}
      <Switch label={t('internet.remember')} description={t('internet.remember_hint')} bind:checked={save} />
      <Banner kind="info">{t('internet.join_hint')}</Banner>
      {#if joinError}<Banner kind="error">{joinError}</Banner>{/if}
    </form>
  {:else if step === 'joining' && chosen}
    <div class="progress" role="status" aria-live="polite">
      <span class="spinner" aria-hidden="true"></span>
      <p><strong>{t('internet.connecting_to', { ssid: chosen.ssid })}</strong></p>
      <p class="hint">{t('internet.joining_hint')}</p>
    </div>
  {:else if step === 'connected' && chosen}
    <Banner kind="success">
      {t('internet.joined', { ssid: chosen.ssid })}
      {#if address}{t('internet.joined_address', { ip: address })}{/if}
    </Banner>
  {:else if step === 'failed' && chosen}
    <Banner kind="error">
      {t('internet.join_failed', { ssid: chosen.ssid })}
      {t(`internet.join_reason.${failure ?? 'timeout'}`)}
    </Banner>
  {/if}
  {#snippet footer()}
    {#if step === 'form'}
      <Button onclick={() => (step = 'list')} disabled={busy}>{t('internet.back')}</Button>
      <Button variant="primary" type="submit" form={formId} {busy} disabled={!canJoin}>{t('internet.join')}</Button>
    {:else if step === 'joining'}
      <Button onclick={() => (open = false)}>{t('internet.close')}</Button>
    {:else if step === 'connected'}
      <Button variant="primary" onclick={() => (open = false)}>{t('internet.done')}</Button>
    {:else if step === 'failed'}
      <Button onclick={() => (open = false)}>{t('internet.close')}</Button>
      <Button variant="primary" onclick={() => (step = 'form')}>{t('internet.retry')}</Button>
    {:else}
      <Button onclick={() => (open = false)}>{t('common.cancel')}</Button>
    {/if}
  {/snippet}
</Dialog>

<style>
  .scan-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .networks {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .networks button {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    width: 100%;
    min-height: 56px;
    padding: var(--space-2);
    border: 0;
    border-top: 1px solid var(--color-border);
    border-radius: 0;
    background: none;
    text-align: left;
    cursor: pointer;
  }

  .networks li:first-child button {
    border-top: 0;
  }

  .networks button:hover:not(:disabled) {
    background: var(--color-surface-muted);
  }

  .networks button:disabled {
    cursor: not-allowed;
    color: var(--color-text-muted);
  }

  .ssid {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .meta {
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
  }

  .lock,
  .open {
    color: var(--color-text-muted);
    font-size: var(--font-size-xs);
    display: inline-flex;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .facts {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2) var(--space-5);
    margin: 0;
    font-size: var(--font-size-sm);
  }

  .facts div {
    display: flex;
    gap: var(--space-2);
  }

  .facts dt {
    color: var(--color-text-muted);
  }

  .facts dd {
    margin: 0;
    font-weight: 600;
  }

  .progress {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-5) 0;
    text-align: center;
  }

  .spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--color-border);
    border-top-color: var(--color-accent);
    border-radius: 50%;
    animation: spin 0.9s linear infinite;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .spinner {
      animation-duration: 3s;
    }
  }
</style>
