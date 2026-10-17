<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Icon from './Icon.svelte';
  import { dismiss, notices } from '../lib/notify.svelte';
  import { t } from '../lib/i18n/index.svelte';

  const ICONS = { applying: 'refresh', success: 'check', error: 'error' } as const;
</script>

<div class="notices" aria-live="polite">
  {#each notices() as notice (notice.id)}
    <div class="notice {notice.kind}" role={notice.kind === 'error' ? 'alert' : 'status'}>
      <span class="icon" class:spin={notice.kind === 'applying'}><Icon name={ICONS[notice.kind]} /></span>
      <span class="message">{notice.message}</span>
      {#if notice.kind !== 'applying'}
        <button type="button" class="close" aria-label={t('common.close')} onclick={() => dismiss(notice.id)}>
          <Icon name="close" size={16} />
        </button>
      {/if}
    </div>
  {/each}
</div>

<style>
  .notices {
    position: fixed;
    z-index: 50;
    left: var(--space-4);
    right: var(--space-4);
    bottom: calc(var(--bottom-nav-height) + var(--space-3) + env(safe-area-inset-bottom));
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    pointer-events: none;
  }

  .notice {
    pointer-events: auto;
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-2) var(--space-2) var(--space-4);
    min-height: var(--touch-target);
    border-radius: var(--radius-md);
    background: var(--color-text);
    color: var(--color-surface);
    box-shadow: 0 8px 24px var(--color-shadow);
    font-size: var(--font-size-sm);
  }

  .applying {
    padding-right: var(--space-4);
  }

  .icon {
    display: flex;
  }

  .spin {
    animation: spin 1s linear infinite;
  }

  .message {
    flex: 1;
    min-width: 0;
  }

  .close {
    width: var(--touch-target);
    height: var(--touch-target);
    border: 0;
    background: none;
    color: inherit;
    cursor: pointer;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (min-width: 768px) {
    .notices {
      left: auto;
      right: var(--space-5);
      bottom: var(--space-5);
      width: 380px;
    }
  }
</style>
