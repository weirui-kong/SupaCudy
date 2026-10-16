<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  let { label, value, max }: { label: string; value: number; max: number } = $props();

  const ratio = $derived(max > 0 ? Math.min(1, Math.max(0, value / max)) : 0);
  // Above 90% the bar changes color, and the percentage text says it too.
  const high = $derived(ratio >= 0.9);
</script>

<div class="meter">
  <div
    class="track"
    role="meter"
    aria-label={label}
    aria-valuemin={0}
    aria-valuemax={max}
    aria-valuenow={value}
    aria-valuetext={`${Math.round(ratio * 100)}%`}
  >
    <div class="fill" class:high style:width={`${ratio * 100}%`}></div>
  </div>
  <span class="percent" class:high>{Math.round(ratio * 100)}%</span>
</div>

<style>
  .meter {
    display: flex;
    align-items: center;
    gap: var(--space-3);
  }

  .track {
    flex: 1;
    height: 8px;
    border-radius: var(--radius-full);
    background: var(--color-surface-muted);
    border: 1px solid var(--color-border);
    overflow: hidden;
  }

  .fill {
    height: 100%;
    background: var(--color-accent);
    transition: width 0.3s ease;
  }

  .fill.high {
    background: var(--color-warning);
  }

  .percent {
    min-width: 3.5em;
    text-align: right;
    font-size: var(--font-size-sm);
    font-variant-numeric: tabular-nums;
    color: var(--color-text-muted);
  }

  .percent.high {
    color: var(--color-warning);
    font-weight: 600;
  }
</style>
