<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Select from '../../components/Select.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import { EAP_METHODS, EAP_PHASE2, validDomain, type EapSettings } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';

  let {
    eap = $bindable(),
    savedPassword = false,
    valid = $bindable(false),
  }: {
    eap: EapSettings;
    /** The router has a password for this network, so the field may stay empty. */
    savedPassword?: boolean;
    valid?: boolean;
  } = $props();

  let advanced = $state(false);

  const methodOptions = EAP_METHODS.map((value) => ({ value, label: t(`internet.eap_method_${value}`) }));
  const phase2Options = $derived(EAP_PHASE2[eap.method].map((value) => ({ value, label: t(`internet.eap_phase2_${value}`) })));

  $effect(() => {
    if (!EAP_PHASE2[eap.method].includes(eap.phase2)) eap.phase2 = EAP_PHASE2[eap.method][0];
  });

  const identityError = $derived(eap.identity.trim() === '' ? t('internet.eap_identity_empty') : null);
  const passwordError = $derived(eap.password === '' && !savedPassword ? t('internet.eap_password_empty') : null);
  const domainError = $derived(eap.validate && !validDomain(eap.domain) ? t('internet.eap_domain_bad') : null);
  // Errors show once the user has typed, so the form does not open in red.
  let touched = $state({ identity: false, password: false, domain: false });

  $effect(() => {
    valid = !identityError && !passwordError && !domainError;
  });
</script>

<Select label={t('internet.eap_method')} bind:value={eap.method} options={methodOptions} hint={t('internet.eap_method_hint')} />
<TextField
  label={t('internet.eap_identity')}
  bind:value={eap.identity}
  autocomplete="username"
  spellcheck={false}
  error={touched.identity ? identityError : null}
  oninput={() => (touched.identity = true)}
/>
<TextField
  label={t('internet.eap_password')}
  type="password"
  revealable
  bind:value={eap.password}
  autocomplete="current-password"
  placeholder={savedPassword ? t('internet.saved_password') : ''}
  error={touched.password ? passwordError : null}
  oninput={() => (touched.password = true)}
/>
<Switch label={t('internet.eap_validate')} description={t('internet.eap_validate_hint')} bind:checked={eap.validate} />
{#if eap.validate}
  <TextField
    label={t('internet.eap_domain')}
    hint={t('internet.eap_domain_hint')}
    bind:value={eap.domain}
    spellcheck={false}
    autocomplete="off"
    error={touched.domain ? domainError : null}
    oninput={() => (touched.domain = true)}
  />
{:else}
  <Banner kind="warning">{t('internet.eap_no_validate')}</Banner>
{/if}

<button type="button" class="disclosure" aria-expanded={advanced} onclick={() => (advanced = !advanced)}>
  {t('wifi.advanced')}
</button>
{#if advanced}
  <div class="advanced">
    <Select label={t('internet.eap_phase2')} bind:value={eap.phase2} options={phase2Options} />
    <TextField
      label={t('internet.eap_anonymous')}
      hint={t('internet.eap_anonymous_hint')}
      bind:value={eap.anonymous_identity}
      spellcheck={false}
      autocomplete="off"
    />
  </div>
{/if}

<style>
  .disclosure {
    align-self: flex-start;
    min-height: var(--touch-target);
    padding: 0;
    border: 0;
    background: none;
    color: var(--color-accent);
    font-weight: 600;
    cursor: pointer;
  }

  .disclosure::after {
    content: ' ▾';
  }

  .disclosure[aria-expanded="true"]::after {
    content: ' ▴';
  }

  .advanced {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    padding-left: var(--space-3);
    border-left: 2px solid var(--color-border);
  }
</style>
