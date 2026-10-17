<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import Switch from '../../components/Switch.svelte';
  import NetworkFields from './NetworkFields.svelte';
  import ShareDialog from './ShareDialog.svelte';
  import { ENCRYPTIONS, setWifi, type Encryption, type Radio, type WifiNetwork } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  // While merged, the name, security and password are edited here only and
  // written to every radio; the radio cards keep the per-band settings.
  let { radios, merged, onsaved }: { radios: Radio[]; merged: boolean; onsaved: () => void } = $props();

  let merging = $state(false);
  let ssid = $state('');
  let encryption = $state<Encryption>('psk2');
  let key = $state('');
  let hidden = $state(false);
  let errors = $state<{ ssid: string | null; key: string | null }>({ ssid: null, key: null });
  let confirmApply = $state(false);
  let confirmSplit = $state(false);
  let busy = $state(false);
  let sharing = $state(false);

  const shared = $derived(radios[0]?.main);
  const encryptions = $derived(ENCRYPTIONS.filter((e) => radios.every((r) => r.encryptions.includes(e))));
  const showForm = $derived(merged || merging);
  const dirty = $derived(
    !!shared && (merging || ssid !== shared.ssid || encryption !== shared.encryption || key !== shared.key || hidden !== shared.hidden),
  );
  const reconnects = $derived(
    merging || (!!shared && (ssid !== shared.ssid || encryption !== shared.encryption || key !== shared.key)),
  );
  const valid = $derived(errors.ssid === null && errors.key === null);
  const anyOn = $derived(radios.some((r) => r.enabled && r.main.enabled));

  function fill(n: WifiNetwork) {
    ({ ssid, encryption, key, hidden } = n);
    if (!encryptions.includes(encryption)) encryption = encryptions[0] ?? 'psk2';
  }

  $effect(() => {
    if (shared) fill(shared);
  });

  function toggle(on: boolean) {
    if (on) {
      merging = true;
      if (shared) fill(shared);
    } else if (merged) {
      confirmSplit = true;
    } else {
      merging = false;
    }
  }

  async function applyAll(networkFor: (r: Radio) => Omit<WifiNetwork, 'enabled'>) {
    busy = true;
    const ok = await apply(async () => {
      for (const r of radios) {
        await setWifi({
          radio: r.name, enabled: r.enabled && r.main.enabled, channel: String(r.channel), width: r.width, txpower: r.txpower,
          ...networkFor(r),
        });
      }
      return true;
    });
    busy = false;
    confirmApply = false;
    confirmSplit = false;
    if (ok) merging = false;
    // Re-read after a failure too: some radios may have been written already.
    onsaved();
  }

  function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!valid || !dirty) return;
    if (reconnects) confirmApply = true;
    else applyAll(() => ({ ssid, encryption, key, hidden }));
  }

  const SUFFIX: Record<Radio['band'], string> = { '2g': '-2.4G', '5g': '-5G', '6g': '-6G' };

  // Splitting keeps the first band's name and suffixes the others with their band.
  const split = () =>
    applyAll((r) => ({
      ssid: r === radios[0] ? r.main.ssid : `${r.main.ssid.slice(0, 32 - SUFFIX[r.band].length)}${SUFFIX[r.band]}`,
      encryption: r.main.encryption, key: r.main.key, hidden: r.main.hidden,
    }));
</script>

{#if radios.length > 1}
  <Card title={t('wifi.bands_title')}>
    <form class="stack" onsubmit={submit}>
      <Switch
        label={t('wifi.bands_merge')}
        description={t('wifi.bands_merge_hint')}
        checked={showForm}
        disabled={busy}
        onchange={toggle}
      />
      {#if showForm}
        <NetworkFields bind:ssid bind:encryption bind:key bind:hidden {encryptions} bind:errors />
        <div class="actions">
          {#if merged && anyOn}
            <span class="share"><Button icon="qr" variant="ghost" onclick={() => (sharing = true)}>{t('wifi.share')}</Button></span>
          {/if}
          {#if merging}
            <Button onclick={() => (merging = false)} disabled={busy}>{t('common.cancel')}</Button>
          {:else}
            <Button onclick={() => shared && fill(shared)} disabled={!dirty || busy}>{t('common.reset')}</Button>
          {/if}
          <Button variant="primary" type="submit" {busy} disabled={!dirty || !valid}>{t('common.apply')}</Button>
        </div>
      {/if}
    </form>
  </Card>

  {#if shared}
    <ShareDialog bind:open={sharing} network={shared} />
  {/if}

  <ConfirmDialog
    bind:open={confirmApply}
    title={t('wifi.reconnect_title')}
    message={t('wifi.bands_reconnect', { ssid })}
    confirmLabel={t('common.apply')}
    {busy}
    onconfirm={() => applyAll(() => ({ ssid, encryption, key, hidden }))}
  />
  <ConfirmDialog
    bind:open={confirmSplit}
    title={t('wifi.reconnect_title')}
    message={t('wifi.bands_split_reconnect')}
    confirmLabel={t('wifi.bands_split')}
    {busy}
    onconfirm={split}
  />
{/if}

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
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
