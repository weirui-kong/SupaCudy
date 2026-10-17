<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Dialog from '../../components/Dialog.svelte';
  import Segmented from '../../components/Segmented.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import {
    formatEndpoint, isCidr, isEndpointHost, isIP, isWgKey, parseEndpoint, parseWgConf, saveVpnProfile, splitList,
    type WgProfile,
  } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let {
    open = $bindable(false),
    profile,
    onsaved,
  }: { open?: boolean; profile: WgProfile | null; onsaved: () => void } = $props();

  type Source = 'paste' | 'manual';
  let source = $state<Source>('paste');
  let text = $state('');
  let parseProblem = $state<string | null>(null);
  let extraPeers = $state(0);

  let name = $state('');
  let privateKey = $state('');
  let publicKey = $state('');
  let presharedKey = $state('');
  let removePsk = $state(false);
  let addresses = $state('');
  let dns = $state('');
  let endpoint = $state('');
  let allowedIps = $state('');
  let keepalive = $state('25');
  let mtu = $state('');
  let advanced = $state(false);
  let busy = $state(false);
  let fileInput = $state<HTMLInputElement>();
  const uid = $props.id();
  const formId = `vpn-profile-${uid}`;

  const editing = $derived(profile !== null);

  $effect(() => {
    if (!open) return;
    source = profile ? 'manual' : 'paste';
    text = '';
    parseProblem = null;
    extraPeers = 0;
    name = profile?.name ?? '';
    privateKey = '';
    publicKey = profile?.public_key ?? '';
    presharedKey = '';
    removePsk = false;
    addresses = profile?.addresses.join(', ') ?? '';
    dns = profile?.dns.join(', ') ?? '';
    endpoint = profile ? formatEndpoint(profile.endpoint_host, profile.endpoint_port) : '';
    allowedIps = profile?.allowed_ips.join(', ') ?? '0.0.0.0/0';
    keepalive = String(profile?.keepalive ?? 25);
    mtu = profile?.mtu ? String(profile.mtu) : '';
    advanced = false;
  });

  function read(conf: string, fileName = '') {
    const parsed = parseWgConf(conf);
    if (typeof parsed === 'string') {
      parseProblem = t(`vpn.parse_${parsed}`);
      return;
    }
    const p = parsed.profile;
    parseProblem = null;
    extraPeers = parsed.extraPeers;
    privateKey = p.private_key;
    publicKey = p.public_key;
    presharedKey = p.preshared_key;
    addresses = p.addresses.join(', ');
    dns = p.dns.join(', ');
    endpoint = formatEndpoint(p.endpoint_host, p.endpoint_port);
    allowedIps = p.allowed_ips.join(', ');
    keepalive = String(p.keepalive);
    mtu = p.mtu ? String(p.mtu) : '';
    name ||= fileName.replace(/\.conf$/i, '') || p.endpoint_host;
    source = 'manual';
  }

  async function readFile(file: File) {
    read(await file.text(), file.name);
    if (fileInput) fileInput.value = '';
  }

  const errors = $derived.by(() => {
    const e: Record<string, string | null> = {};
    e.name = name.trim() ? (name.length > 64 ? t('vpn.name_too_long') : null) : t('vpn.name_required');
    e.privateKey = privateKey ? (isWgKey(privateKey) ? null : t('vpn.key_invalid')) : editing ? null : t('vpn.key_required');
    e.publicKey = isWgKey(publicKey) ? null : publicKey ? t('vpn.key_invalid') : t('vpn.key_required');
    e.presharedKey = presharedKey && !isWgKey(presharedKey) ? t('vpn.key_invalid') : null;
    const addr = splitList(addresses);
    e.addresses = addr.length >= 1 && addr.length <= 4 && addr.every(isCidr) ? null : t('vpn.addresses_invalid');
    e.dns = splitList(dns).every(isIP) && splitList(dns).length <= 4 ? null : t('vpn.dns_invalid');
    const ep = parseEndpoint(endpoint);
    e.endpoint = ep && isEndpointHost(ep.host) ? null : t('vpn.endpoint_invalid');
    const allowed = splitList(allowedIps);
    e.allowedIps = allowed.length >= 1 && allowed.length <= 32 && allowed.every(isCidr) ? null : t('vpn.allowed_invalid');
    const k = Number(keepalive);
    e.keepalive = /^\d+$/.test(keepalive) && k <= 3600 ? null : t('vpn.keepalive_invalid');
    const m = Number(mtu);
    e.mtu = !mtu || (/^\d+$/.test(mtu) && m >= 1280 && m <= 1500) ? null : t('vpn.mtu_invalid');
    return e;
  });
  const valid = $derived(Object.values(errors).every((v) => v === null));

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid) return;
    const ep = parseEndpoint(endpoint)!;
    busy = true;
    const ok = await apply(() =>
      saveVpnProfile({
        id: profile?.id ?? '',
        name: name.trim(),
        private_key: privateKey,
        public_key: publicKey,
        preshared_key: removePsk ? '-' : presharedKey,
        addresses: splitList(addresses),
        dns: splitList(dns),
        endpoint_host: ep.host,
        endpoint_port: ep.port,
        allowed_ips: splitList(allowedIps),
        keepalive: Number(keepalive),
        mtu: Number(mtu || 0),
      }),
    );
    busy = false;
    if (ok) {
      open = false;
      onsaved();
    }
  }

  const sourceOptions = $derived([
    { value: 'paste' as Source, label: t('vpn.source_paste') },
    { value: 'manual' as Source, label: t('vpn.source_manual') },
  ]);
</script>

<Dialog bind:open title={editing ? t('vpn.edit_profile', { name: profile?.name ?? '' }) : t('vpn.add_profile')}>
  {#if !editing}
    <Segmented label={t('vpn.source')} options={sourceOptions} value={source} onchange={(v: Source) => (source = v)} />
  {/if}

  {#if source === 'paste'}
    <div class="paste">
      <p class="hint">{t('vpn.paste_hint')}</p>
      <label class="area">
        <span>{t('vpn.config_text')}</span>
        <textarea bind:value={text} rows="10" spellcheck="false" autocomplete="off"></textarea>
      </label>
      {#if parseProblem}<Banner kind="error">{parseProblem}</Banner>{/if}
      <div class="row">
        <input bind:this={fileInput} type="file" accept=".conf,text/plain" hidden onchange={(e) => {
          const f = e.currentTarget.files?.[0];
          if (f) readFile(f);
        }} />
        <Button icon="upload" onclick={() => fileInput?.click()}>{t('vpn.import_file')}</Button>
        <Button variant="primary" onclick={() => read(text)} disabled={!text.trim()}>{t('vpn.read_config')}</Button>
      </div>
    </div>
  {:else}
    <form id={formId} onsubmit={save}>
      {#if extraPeers > 0}<Banner kind="warning">{t('vpn.extra_peers', { count: extraPeers })}</Banner>{/if}
      <TextField label={t('vpn.name')} bind:value={name} error={name ? errors.name : null} autocomplete="off" />
      <TextField
        label={t('vpn.endpoint')}
        bind:value={endpoint}
        placeholder="vpn.example.com:51820"
        autocomplete="off"
        spellcheck={false}
        error={endpoint ? errors.endpoint : null}
      />
      <TextField label={t('vpn.public_key')} bind:value={publicKey} autocomplete="off" spellcheck={false} error={publicKey ? errors.publicKey : null} />
      <TextField
        label={t('vpn.private_key')}
        type="password"
        revealable
        bind:value={privateKey}
        autocomplete="off"
        placeholder={editing ? t('vpn.keep_key') : ''}
        error={privateKey || !editing ? errors.privateKey : null}
      />
      <TextField
        label={t('vpn.addresses')}
        bind:value={addresses}
        placeholder="10.0.0.2/32"
        hint={t('vpn.list_hint')}
        autocomplete="off"
        error={addresses ? errors.addresses : null}
      />
      <TextField label={t('vpn.dns')} bind:value={dns} placeholder="10.0.0.1" hint={t('vpn.dns_hint')} autocomplete="off" error={errors.dns} />

      <button type="button" class="advanced" aria-expanded={advanced} onclick={() => (advanced = !advanced)}>
        {t('vpn.advanced')}
      </button>
      {#if advanced}
        <TextField label={t('vpn.allowed_ips')} bind:value={allowedIps} hint={t('vpn.allowed_hint')} autocomplete="off" error={errors.allowedIps} />
        <TextField
          label={t('vpn.preshared_key')}
          type="password"
          revealable
          bind:value={presharedKey}
          autocomplete="off"
          placeholder={profile?.has_preshared_key ? t('vpn.keep_key') : t('vpn.optional')}
          error={errors.presharedKey}
        />
        {#if profile?.has_preshared_key}
          <Switch label={t('vpn.remove_psk')} bind:checked={removePsk} />
        {/if}
        <TextField label={t('vpn.keepalive')} bind:value={keepalive} inputmode="numeric" suffix={t('vpn.seconds')} error={errors.keepalive} />
        <TextField label={t('vpn.mtu')} bind:value={mtu} inputmode="numeric" placeholder={t('vpn.optional')} error={errors.mtu} />
      {/if}
    </form>
  {/if}

  {#snippet footer()}
    <Button onclick={() => (open = false)} disabled={busy}>{t('common.cancel')}</Button>
    {#if source === 'manual'}
      <Button variant="primary" type="submit" form={formId} {busy} disabled={!valid}>{t('common.save')}</Button>
    {/if}
  {/snippet}
</Dialog>

<style>
  form,
  .paste {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    margin-top: var(--space-4);
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
    min-height: 180px;
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
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: var(--space-3);
  }

  .advanced {
    align-self: flex-start;
    min-height: var(--touch-target);
    padding: 0;
    border: 0;
    background: none;
    color: var(--color-accent);
    font-weight: 600;
    cursor: pointer;
  }
</style>
