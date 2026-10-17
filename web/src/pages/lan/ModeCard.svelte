<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import TextField from '../../components/TextField.svelte';
  import { getNetMode, setApMode, setRouterMode, type NetModeState } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';
  import { intToIpv4, ipv4ToInt, isIPv4, prefixToNetmask } from '../../lib/validate';

  let { onmoved }: { onmoved: (ip: string) => void } = $props();

  let mode = $state<NetModeState | null>(null);
  let apOpen = $state(false);
  let confirmAp = $state(false);
  let confirmRouter = $state(false);
  let ipaddr = $state('');
  let netmask = $state('255.255.255.0');
  let gateway = $state('');
  let dns = $state('');
  let busy = $state(false);
  const uid = $props.id();
  const formId = `ap-${uid}`;

  $effect(() => {
    getNetMode().then((s) => (mode = s)).catch(() => (mode = null));
  });

  function startAp() {
    const up = mode?.upstream;
    ipaddr = up?.ipaddr ?? '';
    netmask = up ? prefixToNetmask(up.prefix) : '255.255.255.0';
    gateway = up?.gateway ?? '';
    dns = up?.dns[0] ?? '';
    apOpen = true;
  }

  const maskOk = $derived(isIPv4(netmask) && /^1*0*$/.test((ipv4ToInt(netmask) >>> 0).toString(2).padStart(32, '0')));
  const errors = $derived({
    ipaddr: isIPv4(ipaddr) ? null : t('validation.ipv4'),
    netmask: maskOk ? null : t('internet.netmask_invalid'),
    gateway: !isIPv4(gateway)
      ? t('validation.ipv4')
      : isIPv4(ipaddr) && maskOk && ((ipv4ToInt(ipaddr) & ipv4ToInt(netmask)) >>> 0) !== ((ipv4ToInt(gateway) & ipv4ToInt(netmask)) >>> 0)
        ? t('internet.gateway_outside', { network: intToIpv4((ipv4ToInt(ipaddr) & ipv4ToInt(netmask)) >>> 0) })
        : null,
    dns: dns && !isIPv4(dns) ? t('validation.ipv4') : null,
  });
  const valid = $derived(Object.values(errors).every((e) => e === null));

  async function toAp() {
    busy = true;
    const ok = await apply(() => setApMode({ ipaddr, netmask, gateway, dns: dns ? [dns] : [] }));
    busy = false;
    confirmAp = false;
    if (ok) {
      apOpen = false;
      onmoved(ipaddr);
    }
  }

  async function toRouter() {
    busy = true;
    const ok = await apply(setRouterMode);
    busy = false;
    confirmRouter = false;
    if (ok) onmoved(mode?.lan.ipaddr ?? '');
  }
</script>

{#if mode}
  <Card title={t('netmode.title')}>
    <div class="stack">
      <p class="state">{mode.mode === 'ap' ? t('netmode.is_ap', { ip: mode.lan.ipaddr }) : t('netmode.is_router')}</p>
      <p class="hint">{mode.mode === 'ap' ? t('netmode.ap_hint') : t('netmode.router_hint')}</p>
      <div class="actions">
        {#if mode.mode === 'ap'}
          <Button onclick={() => (confirmRouter = true)}>{t('netmode.to_router')}</Button>
        {:else}
          <Button onclick={startAp}>{t('netmode.to_ap')}</Button>
        {/if}
      </div>
    </div>
  </Card>

  <Dialog bind:open={apOpen} title={t('netmode.to_ap')}>
    <form id={formId} class="stack" onsubmit={(e) => (e.preventDefault(), valid && (confirmAp = true))}>
      <p class="hint">{t('netmode.ap_form_hint')}</p>
      {#if !mode.upstream}<Banner kind="warning">{t('netmode.no_upstream')}</Banner>{/if}
      <TextField label={t('netmode.ap_address')} bind:value={ipaddr} inputmode="decimal" error={ipaddr ? errors.ipaddr : null} />
      <TextField label={t('lan.netmask')} bind:value={netmask} inputmode="decimal" error={errors.netmask} />
      <TextField label={t('netmode.main_router')} bind:value={gateway} inputmode="decimal" error={gateway ? errors.gateway : null} />
      <TextField label={t('internet.dns1')} bind:value={dns} inputmode="decimal" placeholder={gateway} error={errors.dns} />
    </form>
    {#snippet footer()}
      <Button onclick={() => (apOpen = false)}>{t('common.cancel')}</Button>
      <Button variant="primary" type="submit" form={formId} disabled={!valid}>{t('setup.next')}</Button>
    {/snippet}
  </Dialog>

  <ConfirmDialog
    bind:open={confirmAp}
    title={t('netmode.to_ap')}
    message={t('netmode.ap_confirm', { ip: ipaddr })}
    consequence={t('netmode.ap_consequence', { ip: ipaddr })}
    confirmLabel={t('common.apply')}
    danger
    {busy}
    onconfirm={toAp}
  />
  <ConfirmDialog
    bind:open={confirmRouter}
    title={t('netmode.to_router')}
    message={t('netmode.router_confirm')}
    consequence={t('netmode.router_consequence')}
    confirmLabel={t('common.apply')}
    {busy}
    onconfirm={toRouter}
  />
{/if}

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .state {
    font-weight: 600;
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
