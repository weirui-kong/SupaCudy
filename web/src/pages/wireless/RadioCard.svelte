<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import Select from '../../components/Select.svelte';
  import Switch from '../../components/Switch.svelte';
  import NetworkFields from './NetworkFields.svelte';
  import ShareDialog from './ShareDialog.svelte';
  import { TX_POWERS, setWifi, type Encryption, type Radio, type TxPower } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  // shared: the bands are merged and the name, security and password are set
  // on the bands card.
  let { radio, shared = false, onsaved }: { radio: Radio; shared?: boolean; onsaved: () => void } = $props();

  let enabled = $state(false);
  let ssid = $state('');
  let encryption = $state<Encryption>('psk2');
  let key = $state('');
  let hidden = $state(false);
  let channel = $state('auto');
  let width = $state('20');
  let txpower = $state<TxPower>('max');
  let errors = $state({ ssid: null as string | null, key: null as string | null });
  let advanced = $state(false);
  let busy = $state(false);
  let sharing = $state(false);
  let confirm = $state(false);

  function fill(r: Radio) {
    enabled = r.enabled && r.main.enabled;
    ssid = r.main.ssid;
    encryption = r.main.encryption;
    key = r.main.key;
    hidden = r.main.hidden;
    channel = String(r.channel);
    width = String(r.width);
    txpower = r.txpower;
  }

  $effect(() => fill(radio));

  const bandName = $derived(t(`bands.${radio.band}`));
  const valid = $derived(!enabled || shared || (errors.ssid === null && errors.key === null));
  const dirty = $derived(
    enabled !== (radio.enabled && radio.main.enabled) || ssid !== radio.main.ssid || encryption !== radio.main.encryption ||
      key !== radio.main.key || hidden !== radio.main.hidden || channel !== String(radio.channel) ||
      width !== String(radio.width) || txpower !== radio.txpower,
  );
  // Clients on this network have to reconnect when its identity changes.
  const reconnects = $derived(
    !enabled || ssid !== radio.main.ssid || encryption !== radio.main.encryption || key !== radio.main.key,
  );

  const channelOptions = $derived([
    { value: 'auto', label: t('wifi.channel_auto') },
    ...radio.channels.map((c) => ({ value: String(c), label: String(c) })),
  ]);
  const widthOptions = $derived(radio.widths.map((w) => ({ value: String(w), label: `${w} MHz` })));
  const powerOptions = $derived(TX_POWERS.map((value) => ({ value, label: t(`wifi.txpower_${value}`) })));

  function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!valid || !dirty) return;
    if (reconnects) confirm = true;
    else save();
  }

  async function save() {
    busy = true;
    const ok = await apply(() =>
      setWifi({ radio: radio.name, enabled, channel, width: Number(width), txpower, ssid, encryption, key, hidden }),
    );
    busy = false;
    confirm = false;
    if (ok) onsaved();
  }
</script>

<Card title={t('wifi.radio_title', { band: bandName })}>
  <form class="form" onsubmit={submit}>
    <Switch label={t('wifi.enable', { band: bandName })} bind:checked={enabled} />
    {#if enabled}
      {#if shared}
        <p class="muted">{t('wifi.shared_hint', { ssid: radio.main.ssid })}</p>
      {:else}
        <NetworkFields bind:ssid bind:encryption bind:key bind:hidden bind:errors encryptions={radio.encryptions} />
      {/if}

      <button type="button" class="disclosure" aria-expanded={advanced} onclick={() => (advanced = !advanced)}>
        {t('wifi.advanced')}
      </button>
      {#if advanced}
        <div class="advanced">
          {#if radio.locked === 'repeater'}
            <Banner kind="info">{t('wifi.locked_repeater')}</Banner>
          {/if}
          <Select label={t('wifi.channel')} bind:value={channel} options={channelOptions} disabled={radio.locked !== null} />
          <Select label={t('wifi.width')} bind:value={width} options={widthOptions} disabled={radio.locked !== null} hint={t('wifi.width_hint')} />
          <Select label={t('wifi.txpower')} bind:value={txpower} options={powerOptions} hint={t('wifi.txpower_hint')} />
        </div>
      {/if}
    {:else}
      <p class="muted">{t('wifi.disabled_hint', { band: bandName })}</p>
    {/if}

    <div class="actions">
      {#if radio.enabled && radio.main.enabled && !shared}
        <span class="share"><Button icon="qr" variant="ghost" onclick={() => (sharing = true)}>{t('wifi.share')}</Button></span>
      {/if}
      <Button onclick={() => fill(radio)} disabled={!dirty || busy}>{t('common.reset')}</Button>
      <Button variant="primary" type="submit" {busy} disabled={!dirty || !valid}>{t('common.apply')}</Button>
    </div>
  </form>
</Card>

{#if radio.main}
  <ShareDialog bind:open={sharing} network={radio.main} />
{/if}

<ConfirmDialog
  bind:open={confirm}
  title={t('wifi.reconnect_title')}
  message={t('wifi.reconnect_message', { band: bandName })}
  consequence={t('wifi.reconnect_consequence')}
  confirmLabel={t('common.apply')}
  {busy}
  onconfirm={save}
/>

<style>
  .form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .disclosure {
    align-self: flex-start;
    min-height: var(--touch-target);
    padding: 0;
    border: 0;
    background: none;
    color: var(--color-accent);
    font-weight: 600;
    cursor: pointer;
  }

  .disclosure::after {
    content: ' ▾';
  }

  .disclosure[aria-expanded="true"]::after {
    content: ' ▴';
  }

  .advanced {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    padding-left: var(--space-3);
    border-left: 2px solid var(--color-border);
  }

  .muted {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .share {
    margin-right: auto;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
  }
</style>
