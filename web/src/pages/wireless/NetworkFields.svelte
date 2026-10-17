<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Select from '../../components/Select.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import { keyError, ssidError, type Encryption } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';

  let {
    ssid = $bindable(''),
    encryption = $bindable<Encryption>('psk2'),
    key = $bindable(''),
    hidden = $bindable(false),
    encryptions,
    errors = $bindable({ ssid: null, key: null }),
  }: {
    ssid?: string;
    encryption?: Encryption;
    key?: string;
    hidden?: boolean;
    encryptions: readonly Encryption[];
    errors?: { ssid: string | null; key: string | null };
  } = $props();

  const SSID_ERRORS = { empty: 'wifi.ssid_empty', too_long: 'wifi.ssid_too_long' } as const;
  const KEY_ERRORS = { too_short: 'wifi.key_too_short', too_long: 'wifi.key_too_long', invalid: 'wifi.key_invalid' } as const;

  $effect(() => {
    const s = ssidError(ssid);
    const k = keyError(encryption, key);
    errors = { ssid: s ? t(SSID_ERRORS[s]) : null, key: k ? t(KEY_ERRORS[k]) : null };
  });

  const options = $derived(encryptions.map((value) => ({ value, label: t(`wifi.encryption.${value}`) })));
</script>

<TextField label={t('wifi.ssid')} bind:value={ssid} error={errors.ssid} autocomplete="off" spellcheck={false} />
<Select label={t('wifi.security')} bind:value={encryption} {options} hint={t(`wifi.encryption_hint.${encryption}`)} />
{#if encryption === 'none'}
  <Banner kind="warning">{t('wifi.open_warning')}</Banner>
{:else}
  <TextField label={t('wifi.key')} type="password" revealable bind:value={key} error={errors.key} autocomplete="new-password" />
{/if}
<Switch label={t('wifi.hidden')} description={t('wifi.hidden_hint')} bind:checked={hidden} />
