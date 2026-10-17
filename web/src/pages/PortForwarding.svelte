<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Select from '../components/Select.svelte';
  import Switch from '../components/Switch.svelte';
  import TextField from '../components/TextField.svelte';
  import DdnsCard from './ports/DdnsCard.svelte';
  import RuleDialog from './ports/RuleDialog.svelte';
  import {
    PROTO_LABELS, deleteOpenPort, deletePortForward, getFirewall, listClients, setDmz, type Client, type FirewallState,
    type OpenPort, type PortForward,
  } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';
  import { inSubnet, isIPv4 } from '../lib/validate';

  let fw = $state<FirewallState | null>(null);
  let error = $state<string | null>(null);
  let clients = $state<Client[]>([]);
  let dialogOpen = $state(false);
  let dialogKind = $state<'forward' | 'open'>('forward');
  let editing = $state<PortForward | OpenPort | null>(null);
  let deleting = $state<{ kind: 'forward' | 'open'; rule: PortForward | OpenPort } | null>(null);
  let deleteOpen = $state(false);
  let dmzEnabled = $state(false);
  let dmzIp = $state('');
  let busy = $state(false);

  async function load() {
    try {
      fw = await getFirewall();
      dmzEnabled = fw.dmz.enabled;
      dmzIp = fw.dmz.ip;
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load();
    listClients().then((l) => (clients = l.clients)).catch(() => {});
  });

  function openDialog(kind: 'forward' | 'open', rule: PortForward | OpenPort | null) {
    dialogKind = kind;
    editing = rule;
    dialogOpen = true;
  }

  async function remove() {
    if (!deleting) return;
    const { kind, rule } = deleting;
    busy = true;
    const ok = await apply(() => (kind === 'forward' ? deletePortForward(rule.id) : deleteOpenPort(rule.id)));
    busy = false;
    deleteOpen = false;
    if (ok) load();
  }

  const dmzError = $derived(
    dmzEnabled && fw && (!isIPv4(dmzIp) || !inSubnet(dmzIp, fw.lan.ipaddr, fw.lan.prefix)) ? t('ports.not_lan') : null,
  );
  const dmzChanged = $derived(!!fw && (dmzEnabled !== fw.dmz.enabled || (dmzEnabled && dmzIp !== fw.dmz.ip)));
  const deviceOptions = $derived([
    { value: '', label: t('ports.pick_device') },
    ...clients.filter((c) => c.ip).map((c) => ({ value: c.ip!, label: `${c.name || c.hostname || c.mac.toUpperCase()} · ${c.ip}` })),
  ]);

  async function saveDmz() {
    busy = true;
    const ok = await apply(() => setDmz(dmzEnabled, dmzEnabled ? dmzIp : ''));
    busy = false;
    if (ok) load();
  }
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

{#if fw}
  <div class="stack">
    <Card title={t('ports.forwards')}>
      <p class="hint">{t('ports.forwards_hint')}</p>
      {#if fw.forwards.length === 0}
        <p class="hint">{t('ports.none')}</p>
      {:else}
        <ul class="rules">
          {#each fw.forwards as f (f.id)}
            <li class:off={!f.enabled}>
              <span class="label">
                <strong>{f.name}</strong>
                <span>
                  {t(PROTO_LABELS[f.proto])} {f.external_port} → {f.internal_ip}:{f.internal_port || f.external_port}
                  {#if !f.enabled}· {t('ports.disabled')}{/if}
                </span>
              </span>
              <span class="buttons">
                <Button variant="ghost" icon="edit" label={t('common.edit_named', { name: f.name })} onclick={() => openDialog('forward', f)} />
                <Button variant="ghost" icon="trash" label={t('common.delete_named', { name: f.name })} onclick={() => ((deleting = { kind: 'forward', rule: f }), (deleteOpen = true))} />
              </span>
            </li>
          {/each}
        </ul>
      {/if}
      <div class="actions"><Button icon="plus" onclick={() => openDialog('forward', null)}>{t('ports.add_forward')}</Button></div>
    </Card>

    <Card title={t('ports.dmz')}>
      <div class="form">
        <p class="hint">{t('ports.dmz_hint')}</p>
        <Switch label={t('ports.dmz_enable')} bind:checked={dmzEnabled} />
        {#if dmzEnabled}
          <Select label={t('ports.device')} value={clients.some((c) => c.ip === dmzIp) ? dmzIp : ''} options={deviceOptions} onchange={(v) => v && (dmzIp = v)} />
          <TextField label={t('ports.internal_ip')} bind:value={dmzIp} inputmode="decimal" error={dmzIp ? dmzError : null} />
          <Banner kind="warning">{t('ports.dmz_warning')}</Banner>
        {/if}
        <div class="actions">
          <Button variant="primary" onclick={saveDmz} {busy} disabled={!dmzChanged || !!dmzError}>{t('common.apply')}</Button>
        </div>
      </div>
    </Card>

    <DdnsCard />

    <Card title={t('ports.open_ports')}>
      <p class="hint">{t('ports.open_hint')}</p>
      {#if fw.open_ports.length === 0}
        <p class="hint">{t('ports.none')}</p>
      {:else}
        <ul class="rules">
          {#each fw.open_ports as o (o.id)}
            <li class:off={!o.enabled}>
              <span class="label">
                <strong>{o.name}</strong>
                <span>{t(PROTO_LABELS[o.proto])} {o.port}{#if !o.enabled} · {t('ports.disabled')}{/if}</span>
              </span>
              <span class="buttons">
                <Button variant="ghost" icon="edit" label={t('common.edit_named', { name: o.name })} onclick={() => openDialog('open', o)} />
                <Button variant="ghost" icon="trash" label={t('common.delete_named', { name: o.name })} onclick={() => ((deleting = { kind: 'open', rule: o }), (deleteOpen = true))} />
              </span>
            </li>
          {/each}
        </ul>
      {/if}
      <div class="actions"><Button icon="plus" onclick={() => openDialog('open', null)}>{t('ports.add_open')}</Button></div>
    </Card>
  </div>

  <RuleDialog bind:open={dialogOpen} kind={dialogKind} rule={editing} lan={fw.lan} {clients} onsaved={load} />
{:else if !error}
  <p>{t('common.loading')}</p>
{/if}

<ConfirmDialog
  bind:open={deleteOpen}
  title={t('ports.delete_title')}
  message={t('ports.delete_confirm', { name: deleting?.rule.name ?? '' })}
  confirmLabel={t('common.delete')}
  danger
  {busy}
  onconfirm={remove}
/>

<style>
  .stack {
    display: grid;
    gap: var(--space-4);
    max-width: 860px;
  }

  .form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .hint,
  .label span {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .rules {
    list-style: none;
    margin: var(--space-3) 0 0;
    padding: 0;
  }

  .rules li {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-2);
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
  }

  .rules li.off strong {
    color: var(--color-text-muted);
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
</style>
