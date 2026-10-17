<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import TextField from '../../components/TextField.svelte';
  import { ApiError, PASSWORD_MAX, PASSWORD_MIN, passwordError, setAdminPassword, verifyPassword } from '../../lib/api';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  let current = $state('');
  let password = $state('');
  let confirm = $state('');
  let wrongCurrent = $state(false);
  let busy = $state(false);
  const uid = $props.id();
  const formId = `password-${uid}`;

  const newError = $derived.by(() => {
    if (!password) return null;
    const problem = passwordError(password);
    if (problem === 'too_short') return t('settings.password_too_short', { min: PASSWORD_MIN });
    if (problem === 'too_long') return t('settings.password_too_long', { max: PASSWORD_MAX });
    if (problem === 'invalid') return t('settings.password_invalid');
    if (problem === 'default') return t('settings.password_default');
    return password === current ? t('settings.password_same') : null;
  });
  const confirmError = $derived(confirm && confirm !== password ? t('settings.password_mismatch') : null);
  const ready = $derived(!!password && !!confirm && !newError && !confirmError);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!ready) return;
    busy = true;
    wrongCurrent = false;
    const ok = await apply(async () => {
      if (!(await verifyPassword(current))) {
        wrongCurrent = true;
        throw new ApiError('rejected', null, 'wrong_password');
      }
      return setAdminPassword(password);
    }, t('settings.password_changed'));
    busy = false;
    if (ok) current = password = confirm = '';
  }
</script>

<Card title={t('settings.password')}>
  <form id={formId} onsubmit={save}>
    <p class="hint">{t('settings.password_hint')}</p>
    <TextField
      label={t('settings.password_current')}
      type="password"
      revealable
      autocomplete="current-password"
      bind:value={current}
      oninput={() => (wrongCurrent = false)}
      error={wrongCurrent ? t('errors.reasons.wrong_password') : null}
    />
    <TextField
      label={t('settings.password_new')}
      type="password"
      revealable
      autocomplete="new-password"
      bind:value={password}
      hint={t('settings.password_rule', { min: PASSWORD_MIN })}
      error={newError}
    />
    <TextField
      label={t('settings.password_confirm')}
      type="password"
      revealable
      autocomplete="new-password"
      bind:value={confirm}
      error={confirmError}
    />
    <div class="actions">
      <Button variant="primary" type="submit" {busy} disabled={!ready}>{t('settings.password_change')}</Button>
    </div>
  </form>
</Card>

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

  .actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
