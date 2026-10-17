<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import BandsCard from './wireless/BandsCard.svelte';
  import GuestCard from './wireless/GuestCard.svelte';
  import RadioCard from './wireless/RadioCard.svelte';
  import { getWifi, type WifiConfig } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';

  let config = $state<WifiConfig | null>(null);
  let error = $state<string | null>(null);

  async function load() {
    try {
      config = await getWifi();
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load();
  });

  // Devices see one network and pick the band themselves when every radio
  // broadcasts the same name, security and password.
  const merged = $derived(
    !!config && config.radios.length > 1 &&
      config.radios.every((r) => {
        const first = config!.radios[0].main;
        return r.main.ssid === first.ssid && r.main.encryption === first.encryption && r.main.key === first.key;
      }),
  );

  // Settings show at once; the radios are read again once wifi reload is done.
  function reload() {
    load();
    setTimeout(load, 4000);
  }
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

{#if config}
  {#if config.radios.length === 0}
    <Banner kind="warning">{t('wifi.no_radios')}</Banner>
  {/if}
  <div class="radios">
    <BandsCard radios={config.radios} {merged} onsaved={reload} />
    {#each config.radios as radio (radio.name)}
      <div class="pair">
        <RadioCard {radio} shared={merged} onsaved={reload} />
        <GuestCard {radio} subnet={config.guest_subnet} onsaved={reload} />
      </div>
    {/each}
  </div>
{:else if !error}
  <p>{t('common.loading')}</p>
{/if}

<style>
  .radios {
    display: grid;
    gap: var(--space-5);
  }

  .pair {
    display: grid;
    gap: var(--space-4);
    align-items: start;
  }

  @media (min-width: 1200px) {
    .pair {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    }
  }
</style>
