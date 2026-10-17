<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import { signalBars } from '../lib/api';
  import { t } from '../lib/i18n/index.svelte';

  let { dbm }: { dbm: number | null } = $props();
  const bars = $derived(signalBars(dbm));
</script>

<!-- The label carries the value, so strength is not shown by shape alone. -->
<span class="signal" role="img" aria-label={dbm === null ? t('common.unavailable') : t('internet.signal_label', { bars, dbm })}>
  <svg width="18" height="16" viewBox="0 0 18 16" aria-hidden="true">
    {#each [0, 1, 2, 3] as i (i)}
      <rect x={i * 4.5} y={12 - i * 4} width="3" height={4 + i * 4} rx="1" class:on={i < bars} />
    {/each}
  </svg>
</span>

<style>
  .signal {
    display: inline-flex;
    color: var(--color-text);
  }

  rect {
    fill: var(--color-border);
  }

  rect.on {
    fill: currentColor;
  }
</style>
