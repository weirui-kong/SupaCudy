<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import DataRow from '../../components/DataRow.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import QrCode from '../../components/QrCode.svelte';
  import type { WifiNetwork } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { wifiQrPayload } from '../../lib/wifiqr';

  let { open = $bindable(false), network }: { open?: boolean; network: WifiNetwork } = $props();
  let reveal = $state(false);

  $effect(() => {
    if (!open) reveal = false;
  });
</script>

<Dialog bind:open title={t('wifi.share_title', { ssid: network.ssid })}>
  <div class="share">
    <QrCode data={wifiQrPayload(network)} label={t('wifi.share_qr', { ssid: network.ssid })} />
    <p class="hint">{t('wifi.share_hint')}</p>
    <dl>
      <DataRow label={t('wifi.ssid')}>{network.ssid}</DataRow>
      {#if network.encryption !== 'none'}
        <DataRow label={t('wifi.key')}>
          <span class="key">
            {reveal ? network.key : '••••••••'}
            <Button variant="ghost" icon={reveal ? 'eye-off' : 'eye'} label={reveal ? t('login.hide_password') : t('login.show_password')} onclick={() => (reveal = !reveal)} />
          </span>
        </DataRow>
      {/if}
    </dl>
  </div>
  {#snippet footer()}
    <Button onclick={() => (open = false)}>{t('common.close')}</Button>
  {/snippet}
</Dialog>

<style>
  .share {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
    text-align: center;
  }

  dl {
    align-self: stretch;
    margin: 0;
  }

  .key {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    overflow-wrap: anywhere;
  }
</style>
