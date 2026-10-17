<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from './Banner.svelte';
  import Button from './Button.svelte';
  import Dialog from './Dialog.svelte';
  import { t } from '../lib/i18n/index.svelte';

  let {
    open = $bindable(false),
    title,
    message,
    consequence,
    confirmLabel,
    danger = false,
    busy = false,
    onconfirm,
  }: {
    open?: boolean;
    title: string;
    message: string;
    /** What the user loses or what will happen, shown as a warning. */
    consequence?: string;
    confirmLabel: string;
    danger?: boolean;
    busy?: boolean;
    onconfirm: () => void;
  } = $props();
</script>

<Dialog bind:open {title}>
  <p>{message}</p>
  {#if consequence}<Banner kind="warning">{consequence}</Banner>{/if}
  {#snippet footer()}
    <Button onclick={() => (open = false)} disabled={busy}>{t('common.cancel')}</Button>
    <Button variant={danger ? 'danger' : 'primary'} {busy} onclick={onconfirm}>{confirmLabel}</Button>
  {/snippet}
</Dialog>
