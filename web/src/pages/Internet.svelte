<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import DataRow from '../components/DataRow.svelte';
  import Icon from '../components/Icon.svelte';
  import SignalBars from '../components/SignalBars.svelte';
  import Switch from '../components/Switch.svelte';
  import JoinDialog from './internet/JoinDialog.svelte';
  import MacDialog from './internet/MacDialog.svelte';
  import WanDialog from './internet/WanDialog.svelte';
  import PriorityCard from './internet/PriorityCard.svelte';
  import {
    disconnectRepeater, forgetNetwork, getInternetStatus, getMacSettings, getSavedNetworks, getWan, setRepeaterOptions,
    setTethering, setWanPortAsLan,
    type InternetStatus, type MacSettings, type MacTarget, type SavedNetworks,
  } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { formatDuration } from '../lib/format';
  import { t } from '../lib/i18n/index.svelte';
  import { uplinkName } from '../lib/uplink';
  import { apply } from '../lib/notify.svelte';

  let { refreshMs = 5000 }: { refreshMs?: number } = $props();

  let status = $state<InternetStatus | null>(null);
  let saved = $state<SavedNetworks | null>(null);
  let error = $state<string | null>(null);
  let wanOpen = $state(false);
  let joinOpen = $state(false);
  let confirmDisconnect = $state(false);
  let forgetting = $state<string | null>(null);
  let busy = $state(false);
  let mac = $state<MacSettings | null>(null);
  let macTarget = $state<MacTarget>('wan');
  let macOpen = $state(false);
  let wanAsLan = $state(false);
  let portConfirm = $state(false);

  async function refresh() {
    try {
      let wan;
      [status, saved, mac, wan] = await Promise.all([getInternetStatus(), getSavedNetworks(), getMacSettings(), getWan()]);
      wanAsLan = wan.as_lan;
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    refresh();
    const timer = setInterval(refresh, refreshMs);
    return () => clearInterval(timer);
  });

  // Settings are stored at once and shown right away; the connections they
  // change come up a moment later, so look again then.
  function later() {
    setTimeout(refresh, 4000);
    return refresh();
  }

  const activeName = $derived.by(() => {
    const key = uplinkName(status?.active);
    return key ? t(key) : null;
  });
  const show = (v: string | null) => v ?? t('common.unavailable');

  async function disconnect() {
    busy = true;
    await apply(disconnectRepeater);
    busy = false;
    confirmDisconnect = false;
    later();
  }

  async function forget(ssid: string) {
    forgetting = ssid;
    await apply(() => forgetNetwork(ssid));
    forgetting = null;
    refresh();
  }

  async function setPortMode(asLan: boolean) {
    busy = true;
    await apply(() => setWanPortAsLan(asLan));
    busy = false;
    portConfirm = false;
    await later();
  }

  function editMac(target: MacTarget) {
    macTarget = target;
    macOpen = true;
  }

  async function setOption(auto_switch: boolean, force_20mhz: boolean) {
    await apply(() => setRepeaterOptions(auto_switch, force_20mhz));
    await refresh();
  }
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

{#if status}
  <div class="summary" class:offline={!status.internet}>
    <Icon name={status.internet ? 'check' : 'error'} size={24} />
    <div>
      <strong>{status.internet ? t('internet.online') : t('internet.offline')}</strong>
      <span>{status.internet && activeName ? t('internet.via', { source: activeName }) : t('internet.offline_hint')}</span>
    </div>
  </div>

  <div class="grid">
    <Card title={t('internet.ethernet')}>
      <p class="state">
        <span class="dot" class:on={status.ethernet.up}></span>
        {status.ethernet.up
          ? t('internet.connected')
          : status.ethernet.carrier ? t('internet.connecting') : t('internet.no_cable')}
      </p>
      {#if !status.ethernet.carrier && !status.ethernet.up}
        <Banner kind="info">{t('internet.no_cable_hint')}</Banner>
      {/if}
      <dl>
        <DataRow label={t('internet.proto')}>{t(`internet.proto_${status.ethernet.proto}`)}</DataRow>
        <DataRow label={t('internet.ipaddr')}>{show(status.ethernet.ipaddr)}</DataRow>
        <DataRow label={t('internet.gateway')}>{show(status.ethernet.gateway)}</DataRow>
        <DataRow label={t('internet.dns')}>{status.ethernet.dns.join(', ') || t('common.unavailable')}</DataRow>
        {#if status.ethernet.up}
          <DataRow label={t('internet.uptime')}>{formatDuration(status.ethernet.uptime, t)}</DataRow>
        {/if}
      </dl>
      {#if wanAsLan}
        <Banner kind="info">{t('internet.wan_as_lan_active')}</Banner>
      {/if}
      <Switch
        label={t('internet.wan_as_lan')}
        description={t('internet.wan_as_lan_hint')}
        checked={wanAsLan}
        disabled={busy}
        onchange={(v) => (v ? (portConfirm = true) : setPortMode(false))}
      />
      <div class="actions">
        <Button icon="settings" onclick={() => (wanOpen = true)} disabled={wanAsLan}>{t('internet.ethernet_settings')}</Button>
      </div>
    </Card>

    <Card title={t('internet.repeater')}>
      {#if !status.repeater.enabled}
        <p class="lead">{t('internet.repeater_hint')}</p>
        <div class="actions">
          <Button variant="primary" icon="wifi" onclick={() => (joinOpen = true)}>{t('internet.choose_network')}</Button>
        </div>
      {:else}
        <p class="state">
          <span class="dot" class:on={status.repeater.up}></span>
          {status.repeater.up
            ? t('internet.connected_to', { ssid: status.repeater.ssid ?? '' })
            : t('internet.connecting_to', { ssid: status.repeater.ssid ?? '' })}
        </p>
        {#if !status.repeater.connected}
          <Banner kind="warning">{t('internet.not_connected_hint')}</Banner>
        {/if}
        <dl>
          <DataRow label={t('internet.signal')}>
            {#if status.repeater.connected}
              <span class="signal"><SignalBars dbm={status.repeater.signal} /> {status.repeater.signal} dBm</span>
            {:else}{t('common.unavailable')}{/if}
          </DataRow>
          <DataRow label={t('internet.band')}>{status.repeater.band ? t(`bands.${status.repeater.band}`) : t('common.unavailable')}</DataRow>
          <DataRow label={t('internet.ipaddr')}>{show(status.repeater.ipaddr)}</DataRow>
          <DataRow label={t('internet.gateway')}>{show(status.repeater.gateway)}</DataRow>
        </dl>
        <div class="actions">
          <Button icon="power" onclick={() => (confirmDisconnect = true)}>{t('internet.disconnect')}</Button>
          <Button variant="primary" icon="wifi" onclick={() => (joinOpen = true)}>{t('internet.change_network')}</Button>
        </div>
      {/if}

      {#if saved}
        <section class="saved" aria-labelledby="saved-title">
          <h3 id="saved-title">{t('internet.saved_networks')}</h3>
          {#if saved.networks.length === 0}
            <p class="lead">{t('internet.no_saved')}</p>
          {:else}
            <ul>
              {#each saved.networks as n (n.ssid)}
                <li>
                  <span>{n.ssid}</span>
                  <Button icon="trash" variant="ghost" label={t('internet.forget_named', { ssid: n.ssid })} busy={forgetting === n.ssid} onclick={() => forget(n.ssid)} />
                </li>
              {/each}
            </ul>
          {/if}
          <Switch
            label={t('internet.auto_switch')}
            description={t('internet.auto_switch_hint')}
            checked={saved.auto_switch}
            onchange={(v) => setOption(v, saved!.force_20mhz)}
          />
          <Switch
            label={t('internet.force_20mhz')}
            description={t('internet.force_20mhz_hint')}
            checked={saved.force_20mhz}
            onchange={(v) => setOption(saved!.auto_switch, v)}
          />
        </section>
      {/if}
    </Card>

    <Card title={t('tethering.title')}>
      <p class="state">
        <span class="dot" class:on={status.tethering.up}></span>
        {!status.tethering.enabled ? t('tethering.off')
          : status.tethering.up ? t('internet.connected')
            : status.tethering.available ? t('internet.connecting') : t('tethering.no_phone')}
      </p>
      <p class="lead spaced">{t('tethering.hint')}</p>
      {#if status.tethering.up}
        <dl>
          <DataRow label={t('internet.ipaddr')}>{show(status.tethering.ipaddr)}</DataRow>
          <DataRow label={t('internet.gateway')}>{show(status.tethering.gateway)}</DataRow>
        </dl>
      {/if}
      <Switch
        label={t('tethering.enable')}
        description={t('tethering.enable_hint')}
        checked={status.tethering.enabled}
        onchange={async (v) => {
          await apply(() => setTethering(v));
          await later();
        }}
      />
    </Card>

    {#if mac}
      <Card title={t('mac.title')}>
        <p class="lead">{t('mac.hint')}</p>
        <ul class="macs">
          <li>
            <span class="mac-label">
              <strong>{t('internet.ethernet')}</strong>
              <span>
                {mac.wan.current?.toUpperCase() ?? t('common.unavailable')}
                · {mac.wan.custom ? t('mac.custom_label') : t('mac.factory_label')}
              </span>
            </span>
            <Button icon="edit" variant="ghost" label={t('mac.edit_named', { name: t('internet.ethernet') })} onclick={() => editMac('wan')} />
          </li>
          <li>
            <span class="mac-label">
              <strong>{t('internet.repeater')}</strong>
              <span>
                {#if !mac.repeater.configured}{t('mac.repeater_unused')}
                {:else if mac.repeater.custom}{mac.repeater.custom.toUpperCase()} · {t('mac.custom_label')}
                {:else}{t('mac.factory_label')}{/if}
              </span>
            </span>
            <Button
              icon="edit"
              variant="ghost"
              label={t('mac.edit_named', { name: t('internet.repeater') })}
              disabled={!mac.repeater.configured}
              onclick={() => editMac('repeater')}
            />
          </li>
        </ul>
      </Card>
    {/if}
    <div class="wide"><PriorityCard /></div>
  </div>
{:else if !error}
  <p>{t('common.loading')}</p>
{/if}

<WanDialog bind:open={wanOpen} onsaved={later} />
<MacDialog
  bind:open={macOpen}
  target={macTarget}
  custom={macTarget === 'wan' ? (mac?.wan.custom ?? null) : (mac?.repeater.custom ?? null)}
  onsaved={later}
/>
<JoinDialog bind:open={joinOpen} onjoined={later} />

<ConfirmDialog
  bind:open={portConfirm}
  title={t('internet.wan_as_lan')}
  message={t('internet.wan_as_lan_confirm')}
  consequence={status?.active === 'wan' ? t('internet.wan_as_lan_offline') : undefined}
  confirmLabel={t('common.apply')}
  {busy}
  onconfirm={() => setPortMode(true)}
/>

<ConfirmDialog
  bind:open={confirmDisconnect}
  title={t('internet.disconnect')}
  message={t('internet.disconnect_confirm', { ssid: status?.repeater.ssid ?? '' })}
  confirmLabel={t('internet.disconnect')}
  {busy}
  onconfirm={disconnect}
/>

<style>
  .summary {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-4);
    margin-bottom: var(--space-4);
    border-radius: var(--radius-lg);
    background: var(--color-success-soft);
    color: var(--color-text);
  }

  .summary :global(svg) {
    color: var(--color-success);
    flex: none;
  }

  .summary.offline {
    background: var(--color-danger-soft);
  }

  .summary.offline :global(svg) {
    color: var(--color-danger);
  }

  .summary div {
    display: flex;
    flex-direction: column;
  }

  .summary span {
    font-size: var(--font-size-sm);
    color: var(--color-text-muted);
  }

  .grid {
    display: grid;
    gap: var(--space-4);
    align-items: start;
  }

  .state {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-weight: 600;
    margin-bottom: var(--space-3);
  }

  .dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--color-switch-off);
  }

  .dot.on {
    background: var(--color-success);
  }

  .lead {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  dl {
    margin: 0 0 var(--space-3);
  }

  .spaced {
    margin-bottom: var(--space-3);
  }

  .signal {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: var(--space-3);
  }

  .saved {
    margin-top: var(--space-5);
    padding-top: var(--space-4);
    border-top: 1px solid var(--color-border);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  h3 {
    font-size: var(--font-size-md);
  }

  .saved ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .saved li {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    border-bottom: 1px solid var(--color-border);
    overflow-wrap: anywhere;
  }

  .macs {
    list-style: none;
    margin: var(--space-3) 0 0;
    padding: 0;
  }

  .macs li {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
  }

  .mac-label {
    display: flex;
    flex-direction: column;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .mac-label span {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  @media (min-width: 1200px) {
    .grid {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    }
  }

  .wide {
    grid-column: 1 / -1;
  }
</style>
