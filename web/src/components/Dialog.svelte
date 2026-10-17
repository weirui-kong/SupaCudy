<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon from './Icon.svelte';
  import { t } from '../lib/i18n/index.svelte';

  // Built on <dialog>: the browser provides the focus trap, Esc handling,
  // inert background and the top layer.
  let {
    open = $bindable(false),
    title,
    children,
    footer,
    onclose,
  }: {
    open?: boolean;
    title: string;
    children: Snippet;
    footer?: Snippet;
    onclose?: () => void;
  } = $props();

  let dialog: HTMLDialogElement;
  const uid = $props.id();
  const titleId = `dialog-title-${uid}`;

  $effect(() => {
    if (open && !dialog.open) dialog.showModal();
    else if (!open && dialog.open) dialog.close();
  });

  function closed() {
    open = false;
    onclose?.();
  }

  function onclick(event: MouseEvent) {
    if (event.target === dialog) dialog.close();
  }
</script>

<dialog bind:this={dialog} aria-labelledby={titleId} onclose={closed} {onclick}>
  <div class="panel">
    <header>
      <h2 id={titleId}>{title}</h2>
      <button type="button" class="close" aria-label={t('common.close')} onclick={() => dialog.close()}>
        <Icon name="close" />
      </button>
    </header>
    <div class="body">{@render children()}</div>
    {#if footer}<footer>{@render footer()}</footer>{/if}
  </div>
</dialog>

<style>
  dialog {
    width: min(520px, calc(100vw - 2 * var(--space-4)));
    max-height: calc(100dvh - 2 * var(--space-4));
    padding: 0;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    background: var(--color-surface);
    color: var(--color-text);
    box-shadow: 0 12px 32px var(--color-shadow);
  }

  dialog::backdrop {
    background: var(--color-backdrop);
  }

  .panel {
    display: flex;
    flex-direction: column;
    max-height: inherit;
  }

  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-2) var(--space-3) var(--space-5);
    border-bottom: 1px solid var(--color-border);
  }

  h2 {
    font-size: var(--font-size-lg);
  }

  .close {
    width: var(--touch-target);
    height: var(--touch-target);
    border: 0;
    border-radius: var(--radius-md);
    background: none;
    color: var(--color-text-muted);
    cursor: pointer;
  }

  .body {
    padding: var(--space-5);
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  footer {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-5);
    border-top: 1px solid var(--color-border);
  }

  /* Phones: a bottom sheet, closer to the thumb. */
  @media (max-width: 767px) {
    dialog {
      width: 100vw;
      max-width: 100vw;
      margin: auto 0 0;
      border-radius: var(--radius-lg) var(--radius-lg) 0 0;
      padding-bottom: env(safe-area-inset-bottom);
    }

    footer {
      flex-direction: column-reverse;
    }

    footer :global(.button) {
      width: 100%;
    }
  }
</style>
