<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from './Banner.svelte';
  import type { RescueState } from '../lib/api';
  import { t } from '../lib/i18n/index.svelte';

  let { rescue }: { rescue: RescueState | null } = $props();
</script>

{#if rescue?.active}
  <Banner kind="warning">
    <strong>{t('rescue.title')}</strong>
    {t('rescue.why')}
    {#if rescue.address}{t('rescue.address', { address: rescue.address })}{/if}
    {#if rescue.ssid}{t('rescue.ssid', { ssid: rescue.ssid })}{/if}
    {t('rescue.temporary')}
  </Banner>
{/if}
