<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { label, hint, children }: { label: string; hint?: Snippet; children: Snippet } = $props();
</script>

<div class="row">
  <dt>{label}{#if hint}{@render hint()}{/if}</dt>
  <dd>{@render children()}</dd>
</div>

<style>
  .row {
    display: grid;
    grid-template-columns: minmax(0, 2fr) minmax(0, 3fr);
    gap: var(--space-3);
    align-items: center;
    min-height: var(--touch-target);
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
  }

  .row:first-child {
    border-top: 0;
  }

  dt {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
    display: flex;
    align-items: center;
    gap: var(--space-1);
  }

  dd {
    margin: 0;
    text-align: right;
    overflow-wrap: anywhere;
    font-variant-numeric: tabular-nums;
  }
</style>
