<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Select from '../../components/Select.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import {
    FORWARD_PROTOS, PROTO_LABELS, portRangeError, rangeSize, saveOpenPort, savePortForward, type Client, type ForwardProto,
    type OpenPort, type PortForward,
  } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';
  import { inSubnet, isIPv4 } from '../../lib/validate';

  let {
    open = $bindable(false),
    kind,
    rule,
    lan,
    clients,
    onsaved,
  }: {
    open?: boolean;
    kind: 'forward' | 'open';
    rule: PortForward | OpenPort | null;
    lan: { ipaddr: string; prefix: number };
    clients: Client[];
    onsaved: () => void;
  } = $props();

  let name = $state('');
  let proto = $state<ForwardProto>('tcp');
  let externalPort = $state('');
  let internalIp = $state('');
  let internalPort = $state('');
  let enabled = $state(true);
  let busy = $state(false);
  const uid = $props.id();
  const formId = `rule-${uid}`;

  $effect(() => {
    if (!open) return;
    name = rule?.name ?? '';
    proto = rule?.proto ?? 'tcp';
    enabled = rule?.enabled ?? true;
    if (rule && 'internal_ip' in rule) {
      externalPort = rule.external_port;
      internalIp = rule.internal_ip;
      internalPort = rule.internal_port;
    } else {
      externalPort = rule && 'port' in rule ? rule.port : '';
      internalIp = '';
      internalPort = '';
    }
  });

  const protoOptions = $derived(FORWARD_PROTOS.map((value) => ({ value, label: t(PROTO_LABELS[value]) })));
  const deviceOptions = $derived([
    { value: '', label: t('ports.pick_device') },
    ...clients.filter((c) => c.ip).map((c) => ({ value: c.ip!, label: `${c.name || c.hostname || c.mac.toUpperCase()} · ${c.ip}` })),
  ]);

  const errors = $derived.by(() => {
    const e: Record<string, string | null> = {};
    e.name = name.trim() ? (name.length > 64 ? t('vpn.name_too_long') : null) : t('vpn.name_required');
    e.externalPort = portRangeError(externalPort) ? t('ports.port_invalid') : null;
    if (kind === 'forward') {
      e.internalIp = !isIPv4(internalIp)
        ? t('validation.ipv4')
        : !inSubnet(internalIp, lan.ipaddr, lan.prefix) || internalIp === lan.ipaddr ? t('ports.not_lan') : null;
      e.internalPort = !internalPort
        ? null
        : portRangeError(internalPort)
          ? t('ports.port_invalid')
          : !e.externalPort && rangeSize(internalPort) !== rangeSize(externalPort) ? t('ports.range_mismatch') : null;
    }
    return e;
  });
  const valid = $derived(Object.values(errors).every((v) => v === null));

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    busy = true;
    const id = rule?.id ?? '';
    const ok = await apply(() =>
      kind === 'forward'
        ? savePortForward({ id, name: name.trim(), proto, external_port: externalPort.trim(), internal_ip: internalIp, internal_port: internalPort.trim(), enabled })
        : saveOpenPort({ id, name: name.trim(), proto, port: externalPort.trim(), enabled }),
    );
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }

  const title = $derived(
    kind === 'forward'
      ? rule ? t('ports.edit_forward') : t('ports.add_forward')
      : rule ? t('ports.edit_open') : t('ports.add_open'),
  );
</script>

<Dialog bind:open {title}>
  <form id={formId} onsubmit={save}>
    <TextField label={t('vpn.name')} bind:value={name} placeholder={kind === 'forward' ? t('ports.name_example') : 'SSH'} error={name ? errors.name : null} autocomplete="off" />
    <Select label={t('ports.proto')} bind:value={proto} options={protoOptions} />
    <TextField
      label={kind === 'forward' ? t('ports.external_port') : t('ports.port')}
      bind:value={externalPort}
      inputmode="numeric"
      placeholder="8080"
      hint={t('ports.port_hint')}
      error={externalPort ? errors.externalPort : null}
    />
    {#if kind === 'forward'}
      <Select label={t('ports.device')} value={clients.some((c) => c.ip === internalIp) ? internalIp : ''} options={deviceOptions} onchange={(v) => v && (internalIp = v)} />
      <TextField label={t('ports.internal_ip')} bind:value={internalIp} inputmode="decimal" error={internalIp ? errors.internalIp : null} />
      <TextField
        label={t('ports.internal_port')}
        bind:value={internalPort}
        inputmode="numeric"
        placeholder={t('ports.same_port')}
        error={errors.internalPort}
      />
    {:else}
      <p class="hint">{t('ports.open_warning')}</p>
    {/if}
    <Switch label={t('ports.enabled')} bind:checked={enabled} />
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
</style>
