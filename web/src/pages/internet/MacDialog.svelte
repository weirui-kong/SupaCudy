<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Segmented from '../../components/Segmented.svelte';
  import Select from '../../components/Select.svelte';
  import TextField from '../../components/TextField.svelte';
  import {
    MAC_MODES, callerAddress, clientLabel, listClients, macError, setMac, type Client, type MacMode, type MacTarget,
  } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let {
    open = $bindable(false),
    target,
    custom,
    onsaved,
  }: { open?: boolean; target: MacTarget; custom: string | null; onsaved: () => void } = $props();

  let mode = $state<MacMode>('default');
  let macaddr = $state('');
  let clients = $state<Client[]>([]);
  let cloneFrom = $state('');
  let thisDevice = $state<string | null>(null);
  let busy = $state(false);
  const uid = $props.id();
  const formId = `mac-${uid}`;

  $effect(() => {
    if (!open) return;
    mode = custom ? 'custom' : 'default';
    macaddr = custom ?? '';
    Promise.all([listClients().catch(() => null), callerAddress()]).then(([list, ip]) => {
      clients = (list?.clients ?? []).filter((c) => c.online);
      thisDevice = clients.find((c) => ip && c.ip === ip)?.mac ?? null;
      cloneFrom = thisDevice ?? clients[0]?.mac ?? '';
    });
  });

  const cloneOptions = $derived(
    clients.map((c) => ({
      value: c.mac,
      label: `${clientLabel(c)} · ${c.mac.toUpperCase()}${c.mac === thisDevice ? ` (${t('mac.this_device')})` : ''}`,
    })),
  );
  const modeOptions = $derived(MAC_MODES.map((value) => ({ value, label: t(`mac.mode_${value}`) })));
  const problem = $derived(mode === 'custom' && macaddr ? macError(macaddr) : null);
  const valid = $derived(mode === 'custom' ? !!macaddr && !problem : mode === 'clone' ? !!cloneFrom : true);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    busy = true;
    const mac = mode === 'clone' ? cloneFrom : mode === 'custom' ? macaddr.trim() : '';
    const ok = await apply(() => setMac(target, mode, mac));
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }
</script>

<Dialog bind:open title={t(`mac.title_${target}`)}>
  <form id={formId} onsubmit={save}>
    <Segmented label={t('mac.mode')} options={modeOptions} value={mode} onchange={(v: MacMode) => (mode = v)} />
    <p class="hint">{t(`mac.mode_hint_${mode}`)}</p>
    {#if mode === 'clone'}
      {#if clients.length}
        <Select label={t('mac.clone_from')} bind:value={cloneFrom} options={cloneOptions} />
      {:else}
        <Banner kind="info">{t('mac.no_clients')}</Banner>
      {/if}
    {:else if mode === 'custom'}
      <TextField
        label={t('mac.address')}
        bind:value={macaddr}
        autocomplete="off"
        spellcheck={false}
        placeholder="02:00:00:00:00:01"
        error={problem === 'format' ? t('validation.mac') : problem === 'unusable' ? t('mac.unusable') : null}
      />
    {/if}
    <Banner kind="warning">{t(`mac.reconnect_${target}`)}</Banner>
  </form>
  {#snippet footer()}
    <Button onclick={() => (open = false)} disabled={busy}>{t('common.cancel')}</Button>
    <Button variant="primary" type="submit" form={formId} {busy} disabled={!valid}>{t('common.apply')}</Button>
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
