<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Shell from './layout/Shell.svelte';
  import Login from './pages/Login.svelte';
  import Overview from './pages/Overview.svelte';
  import Settings from './pages/Settings.svelte';
  import { hasSession, logout, onSessionExpired } from './lib/api';
  import { t } from './lib/i18n/index.svelte';
  import { ROUTES, currentRoute } from './lib/router.svelte';

  let authenticated = $state(hasSession());
  let notice = $state<string | null>(null);

  const route = $derived(currentRoute());
  const title = $derived(t(ROUTES.find((entry) => entry.route === route)!.label));

  $effect(() =>
    onSessionExpired(() => {
      authenticated = false;
      notice = t('errors.denied');
    }),
  );

  $effect(() => {
    document.title = authenticated ? `${title} · ${t('app.name')}` : t('app.name');
  });

  async function signOut() {
    await logout();
    notice = null;
    authenticated = false;
  }
</script>

{#if !authenticated}
  <Login {notice} onlogin={() => ((authenticated = true), (notice = null))} />
{:else}
  <Shell {route} {title} onlogout={signOut}>
    {#if route === 'overview'}
      <Overview />
    {:else if route === 'settings'}
      <Settings onlogout={signOut} />
    {/if}
  </Shell>
{/if}
