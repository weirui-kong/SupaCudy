<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import { WEEKDAYS, type Weekday } from '../lib/api';
  import { t } from '../lib/i18n/index.svelte';

  let { label, days = $bindable([]) }: { label: string; days?: Weekday[] } = $props();

  function toggle(d: Weekday) {
    days = days.includes(d) ? days.filter((x) => x !== d) : WEEKDAYS.filter((x) => x === d || days.includes(x));
  }
</script>

<fieldset>
  <legend>{label}</legend>
  <div class="days">
    {#each WEEKDAYS as d (d)}
      <button type="button" aria-pressed={days.includes(d)} aria-label={t(`days.long_${d}`)} onclick={() => toggle(d)}>
        {t(`days.short_${d}`)}
      </button>
    {/each}
  </div>
</fieldset>

<style>
  fieldset {
    margin: 0;
    padding: 0;
    border: 0;
  }

  legend {
    font-weight: 600;
    margin-bottom: var(--space-2);
  }

  .days {
    display: grid;
    grid-template-columns: repeat(7, minmax(0, 1fr));
    gap: var(--space-1);
  }

  button {
    min-height: var(--touch-target);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface);
    color: var(--color-text);
    font-size: var(--font-size-sm);
    cursor: pointer;
  }

  button[aria-pressed='true'] {
    border-color: var(--color-accent);
    background: var(--color-accent);
    color: var(--color-on-accent);
    font-weight: 600;
  }

  button:focus-visible {
    outline: 2px solid var(--color-focus);
    outline-offset: 2px;
  }
</style>
