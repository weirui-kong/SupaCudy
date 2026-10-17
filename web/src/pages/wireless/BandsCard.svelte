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
  import { ENCRYPTIONS, setWifi, type Encryption, type Radio } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let { radios, onsaved }: { radios: Radio[]; onsaved: () => void } = $props();

  // Devices see one network and pick the band themselves when every radio
  // broadcasts the same name, security and password.
  const merged = $derived(
    radios.length > 1 &&
      radios.every((r) => r.main.ssid === radios[0].main.ssid && r.main.encryption === radios[0].main.encryption && r.main.key === radios[0].main.key),
  );

  let editing = $state(false);
  let ssid = $state('');
  let encryption = $state<Encryption>('psk2');
  let key = $state('');
  let hidden = $state(false);
  let errors = $state<{ ssid: string | null; key: string | null }>({ ssid: null, key: null });
  let confirm = $state(false);
  let busy = $state(false);

  const encryptions = $derived(ENCRYPTIONS.filter((e) => radios.every((r) => r.encryptions.includes(e))));

  function startMerge() {
    ({ ssid, encryption, key, hidden } = radios[0].main);
    editing = true;
  }

  async function applyAll(networkFor: (r: Radio) => { ssid: string; encryption: Encryption; key: string; hidden: boolean }) {
    busy = true;
    const ok = await apply(async () => {
      for (const r of radios) {
        await setWifi({
          radio: r.name, enabled: r.enabled, channel: String(r.channel), width: r.width, txpower: r.txpower,
          ...networkFor(r),
        });
      }
      return true;
    });
    busy = false;
    confirm = false;
    if (ok) {
      editing = false;
      onsaved();
    }
  }

  const SUFFIX: Record<Radio['band'], string> = { '2g': '-2.4G', '5g': '-5G', '6g': '-6G' };

  // Splitting keeps the first band's name and suffixes the others with their band.
  const split = () =>
    applyAll((r) => ({ ...r.main, ssid: r === radios[0] ? r.main.ssid : `${r.main.ssid.slice(0, 32 - SUFFIX[r.band].length)}${SUFFIX[r.band]}` }));
</script>

{#if radios.length > 1}
  <Card title={t('wifi.bands_title')}>
    <div class="stack">
      <Switch
        label={t('wifi.bands_merge')}
        description={t('wifi.bands_merge_hint')}
        checked={merged || editing}
        disabled={busy}
        onchange={(on) => (on ? startMerge() : merged ? split() : (editing = false))}
      />
      {#if editing && !merged}
        <NetworkFields bind:ssid bind:encryption bind:key bind:hidden {encryptions} bind:errors />
        <div class="actions">
          <Button onclick={() => (editing = false)} disabled={busy}>{t('common.cancel')}</Button>
          <Button variant="primary" {busy} disabled={!!(errors.ssid || errors.key)} onclick={() => (confirm = true)}>
            {t('common.apply')}
          </Button>
        </div>
      {/if}
    </div>
  </Card>

  <ConfirmDialog
    bind:open={confirm}
    title={t('wifi.reconnect_title')}
    message={t('wifi.bands_reconnect', { ssid })}
    confirmLabel={t('common.apply')}
    {busy}
    onconfirm={() => applyAll(() => ({ ssid, encryption, key, hidden }))}
  />
{/if}

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
  }
</style>
