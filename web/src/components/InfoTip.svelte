<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import { tick } from 'svelte';
  import Icon from './Icon.svelte';
  import { t } from '../lib/i18n/index.svelte';

  // Tap to toggle rather than hover only, so it works on touch screens.
  let { text }: { text: string } = $props();
  let open = $state(false);
  let trigger: HTMLButtonElement;
  let tip: HTMLSpanElement;
  let position = $state({ top: 0, left: 0 });
  const uid = $props.id();
  const tipId = `tip-${uid}`;

  const EDGE = 8;

  // Fixed positioning, clamped to the viewport: on phones the trigger often
  // sits near a screen edge, where a centered bubble would be cut off.
  async function place() {
    await tick();
    const anchor = trigger.getBoundingClientRect();
    const width = tip.offsetWidth;
    const centered = anchor.left + anchor.width / 2 - width / 2;
    position = {
      top: anchor.bottom + EDGE,
      left: Math.min(Math.max(EDGE, centered), window.innerWidth - width - EDGE),
    };
  }

  function toggle() {
    open = !open;
    if (open) place();
  }

  function onkeydown(event: KeyboardEvent) {
    if (event.key === 'Escape') open = false;
  }
</script>

<svelte:window onscroll={() => (open = false)} onresize={() => (open = false)} />

<span class="wrap">
  <button
    bind:this={trigger}
    type="button"
    class="trigger"
    aria-label={t('common.more_info')}
    aria-expanded={open}
    aria-controls={tipId}
    onclick={toggle}
    onblur={() => (open = false)}
    {onkeydown}
  >
    <Icon name="info" size={16} />
  </button>
  <span
    bind:this={tip}
    id={tipId}
    role="tooltip"
    class="tip"
    hidden={!open}
    style:top={`${position.top}px`}
    style:left={`${position.left}px`}>{text}</span
  >
</span>

<style>
  .wrap {
    display: inline-flex;
    vertical-align: middle;
  }

  .trigger {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: var(--touch-target);
    min-height: var(--touch-target);
    margin: calc((var(--touch-target) - 16px) / -2) 0;
    padding: 0;
    border: 0;
    background: none;
    color: var(--color-text-muted);
    cursor: pointer;
  }

  .trigger:hover {
    color: var(--color-accent);
  }

  .tip {
    position: fixed;
    z-index: 10;
    width: max-content;
    max-width: min(280px, calc(100vw - 16px));
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-sm);
    background: var(--color-text);
    color: var(--color-surface);
    font-size: var(--font-size-xs);
    line-height: 1.45;
    font-weight: 400;
    box-shadow: 0 4px 12px var(--color-shadow);
  }
</style>
