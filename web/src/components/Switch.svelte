<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  let {
    label,
    checked = $bindable(false),
    description,
    disabled = false,
    hideLabel = false,
    onchange,
  }: {
    label: string;
    checked?: boolean;
    description?: string;
    disabled?: boolean;
    /** Keeps the label for screen readers only, e.g. inside a table row. */
    hideLabel?: boolean;
    onchange?: (checked: boolean) => unknown;
  } = $props();

  // With onchange the parent owns the value: once its handler is done the
  // switch shows what the parent has, so a refused or cancelled change
  // moves it back even when the value itself did not change.
  async function changed(event: Event & { currentTarget: HTMLInputElement }) {
    const input = event.currentTarget;
    if (!onchange) {
      checked = input.checked;
      return;
    }
    await onchange(input.checked);
    input.checked = checked;
  }

  const uid = $props.id();
  const descId = `switch-desc-${uid}`;
</script>

<label class="switch" class:disabled>
  <span class="text" class:visually-hidden={hideLabel}>
    <span class="label">{label}</span>
    {#if description}<span class="description" id={descId}>{description}</span>{/if}
  </span>
  <input
    type="checkbox"
    role="switch"
    {checked}
    {disabled}
    aria-describedby={description ? descId : undefined}
    onchange={changed}
  />
  <span class="track" aria-hidden="true"><span class="thumb"></span></span>
</label>

<style>
  .switch {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    min-height: var(--touch-target);
    min-width: var(--touch-target);
    cursor: pointer;
  }

  .disabled {
    cursor: not-allowed;
    opacity: 0.6;
  }

  .text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .label {
    font-size: var(--font-size-sm);
  }

  .description {
    font-size: var(--font-size-xs);
    color: var(--color-text-muted);
  }

  input {
    position: absolute;
    inset: 0;
    opacity: 0;
    margin: 0;
    cursor: inherit;
  }

  .track {
    flex: none;
    position: relative;
    pointer-events: none;
    width: 44px;
    height: 26px;
    border-radius: var(--radius-full);
    background: var(--color-switch-off);
    transition: background 0.15s;
  }

  .thumb {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: var(--color-surface);
    box-shadow: 0 1px 2px var(--color-shadow);
    transition: transform 0.15s;
  }

  input:checked + .track {
    background: var(--color-accent);
  }

  input:checked + .track .thumb {
    transform: translateX(18px);
  }

  input:focus-visible + .track {
    outline: 2px solid var(--color-focus);
    outline-offset: 2px;
  }
</style>
