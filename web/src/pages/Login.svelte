<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Icon from '../components/Icon.svelte';
  import AppearanceControls from '../components/AppearanceControls.svelte';
  import { ApiError, login } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { t } from '../lib/i18n/index.svelte';

  let { onlogin, notice = null }: { onlogin: () => void; notice?: string | null } = $props();

  let password = $state('');
  let visible = $state(false);
  let busy = $state(false);
  let error = $state<string | null>(null);

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    busy = true;
    error = null;
    try {
      await login(password);
      password = '';
      onlogin();
    } catch (err) {
      error = err instanceof ApiError && err.code === 'denied' ? t('login.wrong_password') : errorMessage(err);
    } finally {
      busy = false;
    }
  }
</script>

<main class="page">
  <div class="panel">
    <span class="brand"><Icon name="router" size={28} />{t('app.name')}</span>
    <h1>{t('login.title')}</h1>
    <p class="subtitle">{t('login.subtitle')}</p>

    {#if notice && !error}
      <Banner kind="warning">{notice}</Banner>
    {/if}

    <form onsubmit={submit}>
      <label for="password">{t('login.password')}</label>
      <div class="field">
        <input
          id="password"
          type={visible ? 'text' : 'password'}
          autocomplete="current-password"
          bind:value={password}
          disabled={busy}
          aria-invalid={error ? 'true' : undefined}
          aria-describedby={error ? 'login-error' : undefined}
        />
        <button
          type="button"
          class="reveal"
          aria-label={visible ? t('login.hide_password') : t('login.show_password')}
          aria-pressed={visible}
          onclick={() => (visible = !visible)}
        >
          <Icon name={visible ? 'eye-off' : 'eye'} />
        </button>
      </div>

      {#if error}
        <div id="login-error"><Banner kind="error">{error}</Banner></div>
      {/if}

      <button type="submit" class="submit" disabled={busy}>
        {busy ? t('login.submitting') : t('login.submit')}
      </button>
    </form>

    <div class="appearance">
      <AppearanceControls compact />
    </div>
  </div>
</main>

<style>
  .page {
    min-height: 100vh;
    min-height: 100dvh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-4);
  }

  .panel {
    width: 100%;
    max-width: 400px;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    padding: var(--space-5);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    box-shadow: 0 4px 16px var(--color-shadow);
  }

  .brand {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-weight: 700;
    font-size: var(--font-size-lg);
  }

  h1 {
    font-size: var(--font-size-xl);
  }

  .subtitle {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
    margin-top: calc(var(--space-3) * -1);
  }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  label {
    font-size: var(--font-size-sm);
    font-weight: 600;
  }

  .field {
    display: flex;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface-muted);
  }

  .field:focus-within {
    border-color: var(--color-accent);
  }

  input {
    flex: 1;
    min-width: 0;
    min-height: var(--touch-target);
    padding: 0 var(--space-3);
    border: 0;
    background: transparent;
    outline: none;
  }

  .reveal {
    width: var(--touch-target);
    border: 0;
    background: none;
    color: var(--color-text-muted);
    cursor: pointer;
  }

  .submit {
    min-height: var(--touch-target);
    border: 0;
    border-radius: var(--radius-md);
    background: var(--color-accent);
    color: var(--color-on-accent);
    font-weight: 600;
    cursor: pointer;
  }

  .submit:hover:not(:disabled) {
    background: var(--color-accent-hover);
  }

  .submit:disabled {
    cursor: progress;
    opacity: 0.8;
  }

  .appearance {
    padding-top: var(--space-3);
    border-top: 1px solid var(--color-border);
  }
</style>
