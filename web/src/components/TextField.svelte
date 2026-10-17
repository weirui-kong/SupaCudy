<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements';
  import Icon from './Icon.svelte';
  import { t } from '../lib/i18n/index.svelte';

  let {
    label,
    value = $bindable(''),
    type = 'text',
    hint,
    error,
    suffix,
    revealable = false,
    disabled = false,
    required = false,
    ...rest
  }: {
    label: string;
    value?: string;
    type?: 'text' | 'password' | 'number' | 'email' | 'url' | 'time';
    hint?: string;
    error?: string | null;
    suffix?: string;
    revealable?: boolean;
    disabled?: boolean;
    required?: boolean;
  } & Omit<HTMLInputAttributes, 'value' | 'type'> = $props();

  const uid = $props.id();
  const inputId = `field-${uid}`;
  const hintId = `field-hint-${uid}`;
  const errorId = `field-error-${uid}`;
  let visible = $state(false);

  const describedBy = $derived([hint ? hintId : null, error ? errorId : null].filter(Boolean).join(' ') || undefined);
</script>

<div class="field" class:invalid={!!error}>
  <label for={inputId}>{label}</label>
  <div class="control">
    <input
      id={inputId}
      type={revealable && visible ? 'text' : type}
      bind:value
      {disabled}
      {required}
      aria-invalid={error ? 'true' : undefined}
      aria-describedby={describedBy}
      {...rest}
    />
    {#if suffix}<span class="suffix">{suffix}</span>{/if}
    {#if revealable}
      <button
        type="button"
        class="reveal"
        aria-label={visible ? t('login.hide_password') : t('login.show_password')}
        aria-pressed={visible}
        onclick={() => (visible = !visible)}
      >
        <Icon name={visible ? 'eye-off' : 'eye'} />
      </button>
    {/if}
  </div>
  {#if error}
    <p class="error" id={errorId}><Icon name="error" size={16} />{error}</p>
  {:else if hint}
    <p class="hint" id={hintId}>{hint}</p>
  {/if}
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
    display: flex;
    align-items: center;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface-muted);
  }

  .control:focus-within {
    border-color: var(--color-accent);
    outline: 2px solid var(--color-focus);
    outline-offset: 1px;
  }

  .invalid .control {
    border-color: var(--color-danger);
  }

  input {
    flex: 1;
    min-width: 0;
    min-height: var(--touch-target);
    padding: 0 var(--space-3);
    border: 0;
    background: transparent;
    outline: none;
  }

  input:disabled {
    color: var(--color-text-muted);
    cursor: not-allowed;
  }

  .suffix {
    padding-right: var(--space-3);
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .reveal {
    width: var(--touch-target);
    min-height: var(--touch-target);
    border: 0;
    background: none;
    color: var(--color-text-muted);
    cursor: pointer;
  }

  .hint,
  .error {
    font-size: var(--font-size-xs);
    display: flex;
    gap: var(--space-1);
    align-items: flex-start;
  }

  .hint {
    color: var(--color-text-muted);
  }

  .error {
    color: var(--color-danger);
  }
</style>
