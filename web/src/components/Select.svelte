<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts" generics="T extends string">
  let {
    label,
    value = $bindable(),
    options,
    hint,
    disabled = false,
    onchange,
  }: {
    label: string;
    value: T;
    options: readonly { value: T; label: string }[];
    hint?: string;
    disabled?: boolean;
    onchange?: (value: T) => void;
  } = $props();

  const uid = $props.id();
  const selectId = `select-${uid}`;
  const hintId = `select-hint-${uid}`;
</script>

<div class="field">
  <label for={selectId}>{label}</label>
  <select
    id={selectId}
    bind:value
    {disabled}
    aria-describedby={hint ? hintId : undefined}
    onchange={() => onchange?.(value)}
  >
    {#each options as option (option.value)}
      <option value={option.value}>{option.label}</option>
    {/each}
  </select>
  {#if hint}<p class="hint" id={hintId}>{hint}</p>{/if}
</div>

<style>
  .field {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    min-width: 0;
  }

  label {
    font-size: var(--font-size-sm);
    font-weight: 600;
  }

  select {
    min-height: var(--touch-target);
    padding: 0 var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface-muted);
    color: var(--color-text);
  }

  select:disabled {
    color: var(--color-text-muted);
    cursor: not-allowed;
  }

  .hint {
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
  }
</style>
