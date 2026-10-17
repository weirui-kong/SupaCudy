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
  import LuciDialog from '../components/LuciDialog.svelte';
  import Meter from '../components/Meter.svelte';
  import Segmented from '../components/Segmented.svelte';
  import Switch from '../components/Switch.svelte';
  import {
    CPU_LIMITS, FIRMWARE_PATH, OFFLOAD_MODES, getCpuLimit, setCpuLimit, type CpuLimit, checkFirmware, getFirewall, setOffload, type OffloadMode, discardFirmware, factoryReset, getDeviceInfo, rebootRouter, upgradeFirmware,
    uploadFile, type DeviceInfo, type FirmwareCheck,
  } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { formatBytes } from '../lib/format';
  import { locale, t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';
  import { beginRestart } from '../lib/restart.svelte';

  let info = $state<DeviceInfo | null>(null);
  let luci = $state(false);
  let file = $state<File | null>(null);
  let progress = $state<number | null>(null);
  let firmware = $state<FirmwareCheck | null>(null);
  let uploadError = $state<string | null>(null);
  let keepSettings = $state(true);
  let confirm = $state<'upgrade' | 'reboot' | 'reset'>('reboot');
  let confirmOpen = $state(false);
  let busy = $state(false);
  let input = $state<HTMLInputElement>();

  let offload = $state<OffloadMode | null>(null);
  let cpuLimit = $state<CpuLimit | null>(null);

  $effect(() => {
    getDeviceInfo().then((i) => (info = i)).catch(() => {});
    getFirewall().then((f) => (offload = f.offload)).catch(() => {});
    getCpuLimit().then((c) => (cpuLimit = c.limit)).catch(() => {});
  });

  async function changeCpuLimit(limit: CpuLimit) {
    const previous = cpuLimit;
    cpuLimit = limit;
    if (!(await apply(() => setCpuLimit(limit)))) cpuLimit = previous;
  }

  const cpuOptions = CPU_LIMITS.map((value) => ({ value: String(value), label: `${value}%` }));

  async function changeOffload(mode: OffloadMode) {
    const previous = offload;
    offload = mode;
    if (!(await apply(() => setOffload(mode)))) offload = previous;
  }

  const offloadOptions = $derived(OFFLOAD_MODES.map((value) => ({ value, label: t(`maintenance.offload_${value}`) })));

  async function upload(chosen: File) {
    file = chosen;
    firmware = null;
    uploadError = null;
    progress = 0;
    try {
      await uploadFile(FIRMWARE_PATH, chosen, (f) => (progress = f));
      firmware = await checkFirmware();
      keepSettings = firmware.allow_backup;
    } catch (err) {
      uploadError = errorMessage(err);
    }
    progress = null;
  }

  async function discard() {
    await discardFirmware().catch(() => {});
    file = null;
    firmware = null;
    uploadError = null;
    if (input) input.value = '';
  }

  function ask(kind: typeof confirm) {
    confirm = kind;
    confirmOpen = true;
  }

  async function run(action: () => Promise<unknown>, kind: 'reboot' | 'reset' | 'upgrade') {
    busy = true;
    const ok = await apply(action, t(`restart.title_${kind}`));
    busy = false;
    confirmOpen = false;
    if (ok) beginRestart(kind);
  }

  const dialogs = $derived({
    upgrade: {
      title: t('maintenance.upgrade'),
      message: t('maintenance.upgrade_confirm', { name: file?.name ?? '' }),
      consequence: keepSettings ? t('maintenance.upgrade_keep') : t('maintenance.upgrade_erase'),
      confirmLabel: t('maintenance.upgrade'),
      danger: !keepSettings,
      action: () => run(() => upgradeFirmware(keepSettings), 'upgrade'),
    },
    reboot: {
      title: t('maintenance.reboot'),
      message: t('maintenance.reboot_confirm'),
      consequence: t('maintenance.reboot_consequence'),
      confirmLabel: t('maintenance.reboot'),
      danger: false,
      action: () => run(rebootRouter, 'reboot'),
    },
    reset: {
      title: t('maintenance.reset'),
      message: t('maintenance.reset_confirm'),
      consequence: t('maintenance.reset_consequence'),
      confirmLabel: t('maintenance.reset'),
      danger: true,
      action: () => run(factoryReset, 'reset'),
    },
  });
</script>

<div class="stack">
  <Card title={t('maintenance.firmware')}>
    <dl>
      <DataRow label={t('overview.supacudy')}>{info?.version ?? t('common.unavailable')}</DataRow>
      <DataRow label={t('overview.openwrt')}>{info?.openwrt ?? t('common.unavailable')}</DataRow>
    </dl>
    <p class="hint">{t('maintenance.firmware_hint')}</p>

    <input
      bind:this={input}
      hidden
      type="file"
      accept=".bin,.itb,.img,.gz"
      onchange={(e) => {
        const chosen = e.currentTarget.files?.[0];
        if (chosen) upload(chosen);
      }}
    />

    {#if progress !== null}
      <Meter progress label={t('maintenance.uploading', { name: file?.name ?? '' })} value={progress} max={1} />
    {:else if uploadError}
      <Banner kind="error">{uploadError}</Banner>
      <div class="actions">
        <Button onclick={discard}>{t('common.cancel')}</Button>
      </div>
    {:else if firmware && file}
      <dl>
        <DataRow label={t('maintenance.file')}>{file.name}</DataRow>
        <DataRow label={t('maintenance.size')}>{formatBytes(firmware.size, locale())}</DataRow>
      </dl>
      {#if firmware.valid}
        <Banner kind="success">{t('maintenance.firmware_valid')}</Banner>
        <Switch
          label={t('maintenance.keep_settings')}
          description={firmware.allow_backup ? t('maintenance.keep_settings_hint') : t('maintenance.keep_settings_unsupported')}
          disabled={!firmware.allow_backup}
          bind:checked={keepSettings}
        />
        <div class="actions">
          <Button onclick={discard}>{t('common.cancel')}</Button>
          <Button variant="primary" icon="upload" onclick={() => ask('upgrade')}>{t('maintenance.upgrade')}</Button>
        </div>
      {:else}
        <Banner kind="error">{t('maintenance.firmware_invalid')}</Banner>
        <div class="actions">
          <Button onclick={discard}>{t('maintenance.choose_other')}</Button>
        </div>
      {/if}
    {:else}
      <div class="actions">
        <Button variant="primary" icon="upload" onclick={() => input?.click()}>{t('maintenance.choose_file')}</Button>
      </div>
    {/if}
  </Card>

  {#if offload}
    <Card title={t('maintenance.acceleration')}>
      <p class="hint">{t('maintenance.acceleration_hint')}</p>
      <Segmented label={t('maintenance.offload_mode')} options={offloadOptions} value={offload} onchange={(v: OffloadMode) => changeOffload(v)} />
      {#if offload !== 'off'}<p class="hint note">{t('maintenance.offload_note')}</p>{/if}
    </Card>
  {/if}

  {#if cpuLimit}
    <Card title={t('maintenance.cpu_limit')}>
      <p class="hint">{t('maintenance.cpu_limit_hint')}</p>
      <Segmented label={t('maintenance.cpu_limit')} options={cpuOptions} value={String(cpuLimit)} onchange={(v) => changeCpuLimit(Number(v) as CpuLimit)} />
      <p class="hint note">{t('maintenance.cpu_limit_note')}</p>
    </Card>
  {/if}

  <Card title={t('maintenance.advanced')}>
    <div class="row">
      <p class="hint">{t('maintenance.advanced_hint')}</p>
      <button type="button" class="luci" onclick={() => (luci = true)}>{t('maintenance.open_luci')}</button>
    </div>
  </Card>

  <Card title={t('maintenance.reboot')}>
    <div class="row">
      <p class="hint">{t('maintenance.reboot_hint')}</p>
      <Button icon="refresh" onclick={() => ask('reboot')}>{t('maintenance.reboot')}</Button>
    </div>
  </Card>

  <Card title={t('maintenance.reset')}>
    <div class="row">
      <p class="hint">{t('maintenance.reset_hint')}</p>
      <Button variant="danger" icon="trash" onclick={() => ask('reset')}>{t('maintenance.reset')}</Button>
    </div>
  </Card>
</div>

<ConfirmDialog
  bind:open={confirmOpen}
  title={dialogs[confirm].title}
  message={dialogs[confirm].message}
  consequence={dialogs[confirm].consequence}
  confirmLabel={dialogs[confirm].confirmLabel}
  danger={dialogs[confirm].danger}
  {busy}
  onconfirm={dialogs[confirm].action}
/>

<LuciDialog bind:open={luci} />

<style>
  .stack {
    display: grid;
    gap: var(--space-4);
    max-width: 760px;
  }

  dl {
    margin: 0 0 var(--space-3);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
    margin-bottom: var(--space-3);
  }

  .note {
    margin: var(--space-3) 0 0;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: var(--space-3);
    margin-top: var(--space-3);
  }

  .row {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    align-items: flex-start;
  }

  .row .hint {
    margin: 0;
  }


  .luci {
    display: inline-flex;
    background: none;
    cursor: pointer;
    font: inherit;
    align-items: center;
    min-height: var(--touch-target);
    padding: 0 var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    color: var(--color-text);
    font-weight: 600;
    text-decoration: none;
    white-space: nowrap;
  }

  .luci:hover {
    background: var(--color-surface-muted);
  }

  @media (min-width: 768px) {
    .row {
      flex-direction: row;
      align-items: center;
      justify-content: space-between;
    }
  }
</style>
