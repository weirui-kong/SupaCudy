<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import TextField from '../../components/TextField.svelte';
  import { verifyPassword } from '../../lib/api';
  import { errorMessage } from '../../lib/errors';
  import { t } from '../../lib/i18n/index.svelte';

  let {
    open = $bindable(false),
    busy,
    onsubmit,
  }: { open?: boolean; busy: boolean; onsubmit: (password: string) => void } = $props();

  let password = $state('');
  let error = $state<string | null>(null);
  let checking = $state(false);
  const uid = $props.id();
  const formId = `adguard-web-${uid}`;

  // Checked here first: the router cannot verify it without logging in.
  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!password) return;
    checking = true;
    error = null;
    try {
      if (await verifyPassword(password)) onsubmit(password);
      else error = t('login.wrong_password');
    } catch (err) {
      error = errorMessage(err);
    } finally {
      checking = false;
    }
  }
</script>

<Dialog bind:open title={t('adblock.web_title')} onclose={() => ((password = ''), (error = null))}>
  <form id={formId} onsubmit={submit}>
    <p class="hint">{t('adblock.web_dialog_hint')}</p>
    <TextField label={t('adblock.web_user')} value="root" readonly />
    <TextField label={t('adblock.web_password')} type="password" revealable autocomplete="current-password"
      bind:value={password} oninput={() => (error = null)} {error} />
  </form>
  {#snippet footer()}
    <Button variant="primary" type="submit" form={formId} busy={busy || checking} disabled={!password}>{t('common.continue')}</Button>
  {/snippet}
</Dialog>

<style>
  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }
</style>
