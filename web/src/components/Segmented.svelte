<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts" generics="T extends string">
  import Icon, { type IconName } from './Icon.svelte';

  interface Option {
    value: T;
    label: string;
    icon?: IconName;
  }

  let {
    label,
    options,
    value,
    onchange,
  }: { label: string; options: readonly Option[]; value: T; onchange: (value: T) => void } = $props();

  const uid = $props.id();
  const name = `segmented-${uid}`;
</script>

<fieldset class="segmented">
  <legend class="visually-hidden">{label}</legend>
  {#each options as option (option.value)}
    <label class:selected={option.value === value}>
      <input
        type="radio"
        {name}
        value={option.value}
        checked={option.value === value}
        onchange={() => onchange(option.value)}
      />
      {#if option.icon}<Icon name={option.icon} size={18} />{/if}
      <span>{option.label}</span>
    </label>
  {/each}
</fieldset>

<style>
  .segmented {
    display: inline-flex;
    flex-wrap: wrap;
    gap: var(--space-1);
    margin: 0;
    padding: var(--space-1);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface-muted);
    max-width: 100%;
  }

  label {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    min-height: var(--touch-target);
    padding: 0 var(--space-4);
    border-radius: var(--radius-sm);
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
    cursor: pointer;
  }

  label.selected {
    background: var(--color-surface);
    color: var(--color-text);
    font-weight: 600;
    box-shadow: 0 1px 2px var(--color-shadow);
  }

  input {
    position: absolute;
    opacity: 0;
    inset: 0;
    margin: 0;
    cursor: pointer;
  }

  label:has(input:focus-visible) {
    outline: 2px solid var(--color-focus);
    outline-offset: 2px;
  }
</style>
