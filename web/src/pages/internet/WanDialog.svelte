<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Segmented from '../../components/Segmented.svelte';
  import TextField from '../../components/TextField.svelte';
  import { WAN_PROTOS, getWan, setWan, type WanProto } from '../../lib/api';
  import { errorMessage } from '../../lib/errors';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';
  import { intToIpv4, ipv4ToInt, isIPv4 } from '../../lib/validate';

  let { open = $bindable(false), onsaved }: { open?: boolean; onsaved: () => void } = $props();

  let loaded = $state(false);
  let loadError = $state<string | null>(null);
  let proto = $state<WanProto>('dhcp');
  let ipaddr = $state('');
  let netmask = $state('255.255.255.0');
  let gateway = $state('');
  let dns1 = $state('');
  let dns2 = $state('');
  let username = $state('');
  let password = $state('');
  let hasPassword = $state(false);
  let busy = $state(false);
  const uid = $props.id();
  const formId = `wan-${uid}`;

  $effect(() => {
    if (!open) return;
    loaded = false;
    getWan()
      .then((w) => {
        proto = w.proto;
        ipaddr = w.ipaddr;
        netmask = w.netmask || '255.255.255.0';
        gateway = w.gateway;
        [dns1 = '', dns2 = ''] = w.dns;
        username = w.username;
        password = '';
        hasPassword = w.has_password;
        loaded = true;
        loadError = null;
      })
      .catch((err) => (loadError = errorMessage(err)));
  });

  function sameSubnet(a: string, b: string, mask: string) {
    const m = ipv4ToInt(mask);
    return (ipv4ToInt(a) & m) === (ipv4ToInt(b) & m);
  }

  const errors = $derived.by(() => {
    const e: Record<string, string | null> = {};
    if (proto === 'static') {
      e.ipaddr = isIPv4(ipaddr) ? null : t('validation.ipv4');
      const maskOk = isIPv4(netmask) && /^1*0*$/.test((ipv4ToInt(netmask) >>> 0).toString(2).padStart(32, '0'));
      e.netmask = maskOk ? null : t('internet.netmask_invalid');
      e.gateway = !isIPv4(gateway)
        ? t('validation.ipv4')
        : isIPv4(ipaddr) && maskOk && !sameSubnet(ipaddr, gateway, netmask)
          ? t('internet.gateway_outside', { network: intToIpv4((ipv4ToInt(ipaddr) & ipv4ToInt(netmask)) >>> 0) })
          : null;
    }
    if (proto === 'pppoe') e.username = username.trim() ? null : t('internet.username_required');
    e.dns1 = dns1 && !isIPv4(dns1) ? t('validation.ipv4') : null;
    e.dns2 = dns2 && !isIPv4(dns2) ? t('validation.ipv4') : null;
    return e;
  });
  const valid = $derived(Object.values(errors).every((v) => v === null));

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    busy = true;
    const ok = await apply(() =>
      setWan({ proto, ipaddr, netmask, gateway, dns: [dns1, dns2].filter(Boolean), username: username.trim(), password }),
    );
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }

  const protoOptions = $derived(WAN_PROTOS.map((value) => ({ value, label: t(`internet.proto_${value}`) })));
</script>

<Dialog bind:open title={t('internet.ethernet_settings')}>
  {#if loadError}<Banner kind="error">{loadError}</Banner>{/if}
  {#if loaded}
    <form id={formId} onsubmit={save}>
      <Segmented label={t('internet.proto')} options={protoOptions} value={proto} onchange={(v: WanProto) => (proto = v)} />
      <p class="hint">{t(`internet.proto_hint_${proto}`)}</p>

      {#if proto === 'static'}
        <TextField label={t('internet.ipaddr')} bind:value={ipaddr} inputmode="decimal" error={ipaddr ? errors.ipaddr : null} />
        <TextField label={t('lan.netmask')} bind:value={netmask} inputmode="decimal" error={errors.netmask} />
        <TextField label={t('internet.gateway')} bind:value={gateway} inputmode="decimal" error={gateway ? errors.gateway : null} />
      {:else if proto === 'pppoe'}
        <TextField label={t('internet.username')} bind:value={username} autocomplete="off" error={username ? null : errors.username} />
        <TextField
          label={t('internet.password')}
          type="password"
          revealable
          bind:value={password}
          autocomplete="off"
          placeholder={hasPassword ? t('vpn.keep_key') : ''}
        />
      {/if}

      <fieldset>
        <legend>{t('internet.dns')}</legend>
        <p class="hint">{t('internet.dns_hint')}</p>
        <TextField label={t('internet.dns1')} bind:value={dns1} inputmode="decimal" placeholder={t('internet.dns_auto')} error={errors.dns1} />
        <TextField label={t('internet.dns2')} bind:value={dns2} inputmode="decimal" placeholder={t('internet.dns_auto')} error={errors.dns2} />
      </fieldset>
      <Banner kind="warning">{t('internet.wan_apply_warning')}</Banner>
    </form>
  {:else if !loadError}
    <p>{t('common.loading')}</p>
  {/if}
  {#snippet footer()}
    <Button onclick={() => (open = false)} disabled={busy}>{t('common.cancel')}</Button>
    <Button variant="primary" type="submit" form={formId} {busy} disabled={!loaded || !valid}>{t('common.apply')}</Button>
  {/snippet}
</Dialog>

<style>
  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  fieldset {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    margin: 0;
    padding: var(--space-3) 0 0;
    border: 0;
    border-top: 1px solid var(--color-border);
  }

  legend {
    font-weight: 600;
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }
</style>
