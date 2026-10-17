<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import Switch from '../../components/Switch.svelte';
  import NetworkFields from './NetworkFields.svelte';
  import ShareDialog from './ShareDialog.svelte';
  import { setGuestWifi, type Encryption, type Radio } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let { radio, subnet, onsaved }: { radio: Radio; subnet: string | null; onsaved: () => void } = $props();

  let enabled = $state(false);
  let ssid = $state('');
  let encryption = $state<Encryption>('psk2');
  let key = $state('');
  let hidden = $state(false);
  let errors = $state({ ssid: null as string | null, key: null as string | null });
  let busy = $state(false);
  let sharing = $state(false);

  const bandName = $derived(t(`bands.${radio.band}`));

  // A guest network that was never set up starts from a suggested name.
  function fill(r: Radio) {
    enabled = r.guest?.enabled ?? false;
    ssid = r.guest?.ssid ?? `${r.main.ssid}-Guest`.slice(0, 32);
    encryption = r.guest?.encryption ?? r.encryptions[0] ?? 'psk2';
    key = r.guest?.key ?? '';
    hidden = r.guest?.hidden ?? false;
  }

  $effect(() => fill(radio));

  const original = $derived(radio.guest ?? { enabled: false, ssid: '', encryption: 'psk2', key: '', hidden: false });
  const dirty = $derived(
    enabled !== original.enabled ||
      (enabled && (ssid !== original.ssid || encryption !== original.encryption || key !== original.key || hidden !== original.hidden)),
  );
  const valid = $derived(!enabled || (errors.ssid === null && errors.key === null));

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!valid || !dirty) return;
    busy = true;
    const ok = await apply(() => setGuestWifi({ radio: radio.name, enabled, ssid, encryption, key, hidden }));
    busy = false;
    if (ok) onsaved();
  }
</script>

<Card title={t('wifi.guest_title', { band: bandName })}>
  <form class="form" onsubmit={save}>
    <Switch label={t('wifi.guest_enable', { band: bandName })} description={t('wifi.guest_hint')} bind:checked={enabled} disabled={!radio.enabled} />
    {#if !radio.enabled}
      <p class="muted">{t('wifi.guest_needs_radio', { band: bandName })}</p>
    {:else if enabled}
      <NetworkFields bind:ssid bind:encryption bind:key bind:hidden bind:errors encryptions={radio.encryptions} />
      <Banner kind="info">
        {subnet ? t('wifi.guest_isolation_subnet', { subnet }) : t('wifi.guest_isolation')}
      </Banner>
    {/if}
    <div class="actions">
      {#if radio.enabled && radio.guest?.enabled}
        <span class="share"><Button icon="qr" variant="ghost" onclick={() => (sharing = true)}>{t('wifi.share')}</Button></span>
      {/if}
      <Button onclick={() => fill(radio)} disabled={!dirty || busy}>{t('common.reset')}</Button>
      <Button variant="primary" type="submit" {busy} disabled={!dirty || !valid}>{t('common.apply')}</Button>
    </div>
  </form>
</Card>

{#if radio.guest}
  <ShareDialog bind:open={sharing} network={radio.guest} />
{/if}

<style>
  .form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .muted {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .share {
    margin-right: auto;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
  }
</style>
