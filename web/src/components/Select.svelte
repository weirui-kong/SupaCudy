<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts" generics="T extends string">
  import Icon from './Icon.svelte';

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
  <div class="control">
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
    <span class="chevron" aria-hidden="true"><Icon name="chevron-down" size={18} /></span>
  </div>
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

  .control {
    position: relative;
    display: flex;
  }

  /* The native look (on macOS) ignores height and padding, so it is drawn
     like TextField's control instead, with our own arrow. */
  select {
    flex: 1;
    min-width: 0;
    min-height: calc(var(--touch-target) + 2px);
    padding: 0 calc(var(--space-3) + 18px + var(--space-2)) 0 var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface-muted);
    color: var(--color-text);
    text-overflow: ellipsis;
    appearance: none;
    cursor: pointer;
  }

  select:focus-visible {
    border-color: var(--color-accent);
    outline: 2px solid var(--color-focus);
    outline-offset: 1px;
  }

  select:disabled {
    color: var(--color-text-muted);
    cursor: not-allowed;
  }

  .chevron {
    position: absolute;
    top: 50%;
    right: var(--space-3);
    display: flex;
    color: var(--color-text-muted);
    transform: translateY(-50%);
    pointer-events: none;
  }

  .hint {
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
  }
</style>
