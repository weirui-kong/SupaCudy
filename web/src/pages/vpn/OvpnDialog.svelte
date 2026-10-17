<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import TextField from '../../components/TextField.svelte';
  import { ovpnProblem, saveOvpnProfile, type OvpnProfile } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let {
    open = $bindable(false),
    profile,
    onsaved,
  }: { open?: boolean; profile: OvpnProfile | null; onsaved: () => void } = $props();

  let name = $state('');
  let config = $state('');
  let username = $state('');
  let password = $state('');
  let busy = $state(false);
  let fileInput = $state<HTMLInputElement>();
  const uid = $props.id();
  const formId = `ovpn-${uid}`;
  const editing = $derived(profile !== null);

  $effect(() => {
    if (!open) return;
    name = profile?.name ?? '';
    config = '';
    username = profile?.username ?? '';
    password = '';
  });

  async function readFile(file: File) {
    config = await file.text();
    name ||= file.name.replace(/\.(ovpn|conf)$/i, '');
    if (fileInput) fileInput.value = '';
  }

  const problem = $derived(config ? ovpnProblem(config) : editing ? null : 'missing');
  const configError = $derived(
    problem === 'too_large' ? t('vpn.ovpn_too_large') : problem === 'no_remote' ? t('vpn.ovpn_no_remote') : null,
  );
  const nameError = $derived(name.trim() ? (name.length > 64 ? t('vpn.name_too_long') : null) : t('vpn.name_required'));
  const loginError = $derived(!username && password ? t('vpn.username_needed') : null);
  const valid = $derived(!problem && !nameError && !loginError);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    busy = true;
    const ok = await apply(() =>
      saveOvpnProfile({ id: profile?.id ?? '', name: name.trim(), config, username: username.trim(), password }),
    );
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }
</script>

<Dialog bind:open title={editing ? t('vpn.edit_profile', { name: profile?.name ?? '' }) : t('vpn.add_openvpn')}>
  <form id={formId} onsubmit={save}>
    <p class="hint">{editing ? t('vpn.ovpn_keep') : t('vpn.ovpn_hint')}</p>
    <label class="area">
      <span>{t('vpn.config_text')}</span>
      <textarea bind:value={config} rows="8" spellcheck="false" autocomplete="off"></textarea>
    </label>
    {#if configError}<Banner kind="error">{configError}</Banner>{/if}
    <div class="row">
      <input
        bind:this={fileInput}
        type="file"
        accept=".ovpn,.conf,text/plain"
        hidden
        onchange={(e) => {
          const f = e.currentTarget.files?.[0];
          if (f) readFile(f);
        }}
      />
      <Button icon="upload" onclick={() => fileInput?.click()}>{t('vpn.import_file')}</Button>
    </div>
    <TextField label={t('vpn.name')} bind:value={name} error={name ? nameError : null} autocomplete="off" />
    <TextField label={t('vpn.username')} bind:value={username} hint={t('vpn.username_hint')} autocomplete="off" />
    <TextField
      label={t('internet.password')}
      type="password"
      revealable
      bind:value={password}
      autocomplete="off"
      placeholder={editing && profile?.username ? t('vpn.keep_key') : ''}
      error={loginError}
    />
  </form>
  {#snippet footer()}
    <Button onclick={() => (open = false)} disabled={busy}>{t('common.cancel')}</Button>
    <Button variant="primary" type="submit" form={formId} {busy} disabled={!valid}>{t('common.save')}</Button>
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

  .area {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    font-weight: 600;
  }

  textarea {
    width: 100%;
    min-height: 150px;
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface);
    color: var(--color-text);
    font-family: var(--font-mono);
    font-size: var(--font-size-xs);
    font-weight: 400;
    resize: vertical;
  }

  textarea:focus-visible {
    outline: 2px solid var(--color-focus);
    outline-offset: 1px;
  }

  .row {
    display: flex;
    justify-content: flex-end;
  }
</style>
