<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import TextField from '../../components/TextField.svelte';
  import { deleteLocalHost, hostnameError, saveLocalHost, type LocalHost } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';
  import { isIPv4 } from '../../lib/validate';

  let { hosts, onsaved }: { hosts: LocalHost[]; onsaved: () => void } = $props();

  let open = $state(false);
  let editing = $state<LocalHost | null>(null);
  let name = $state('');
  let ip = $state('');
  let busy = $state(false);
  const uid = $props.id();
  const formId = `host-${uid}`;

  function edit(h: LocalHost | null) {
    editing = h;
    name = h?.name ?? '';
    ip = h?.ip ?? '';
    open = true;
  }

  const nameError = $derived(name && hostnameError(name) ? t('dns.hostname_invalid') : null);
  const ipError = $derived(ip && !isIPv4(ip) ? t('validation.ipv4') : null);
  const valid = $derived(!!name && !!ip && !nameError && !ipError);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    busy = true;
    const ok = await apply(() => saveLocalHost({ id: editing?.id ?? '', name: name.trim(), ip }));
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }

  async function remove(h: LocalHost) {
    if (await apply(() => deleteLocalHost(h.id))) onsaved();
  }
</script>

<Card title={t('dns.hosts')}>
  <p class="hint">{t('dns.hosts_hint')}</p>
  {#if hosts.length === 0}
    <p class="hint">{t('ports.none')}</p>
  {:else}
    <ul>
      {#each hosts as h (h.id)}
        <li>
          <span class="label"><strong>{h.name}</strong><span>{h.ip}</span></span>
          <span class="buttons">
            <Button variant="ghost" icon="edit" label={t('common.edit_named', { name: h.name })} onclick={() => edit(h)} />
            <Button variant="ghost" icon="trash" label={t('common.delete_named', { name: h.name })} onclick={() => remove(h)} />
          </span>
        </li>
      {/each}
    </ul>
  {/if}
  <div class="actions"><Button icon="plus" onclick={() => edit(null)}>{t('dns.add_host')}</Button></div>
</Card>

<Dialog bind:open title={editing ? t('common.edit_named', { name: editing.name }) : t('dns.add_host')}>
  <form id={formId} onsubmit={save}>
    <TextField label={t('dns.hostname')} bind:value={name} placeholder="nas.home" autocomplete="off" spellcheck={false} error={nameError} />
    <TextField label={t('internet.ipaddr')} bind:value={ip} inputmode="decimal" placeholder="192.168.1.50" error={ipError} />
  </form>
  {#snippet footer()}
    <Button onclick={() => (open = false)} disabled={busy}>{t('common.cancel')}</Button>
    <Button variant="primary" type="submit" form={formId} {busy} disabled={!valid}>{t('common.save')}</Button>
  {/snippet}
</Dialog>

<style>
  .hint,
  .label span {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  ul {
    list-style: none;
    margin: var(--space-3) 0 0;
    padding: 0;
  }

  li {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
  }

  .label {
    display: flex;
    flex-direction: column;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .buttons {
    display: flex;
    flex: none;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    margin-top: var(--space-3);
  }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }
</style>
