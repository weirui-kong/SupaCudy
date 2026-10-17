<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Shell from './layout/Shell.svelte';
  import Login from './pages/Login.svelte';
  import Clients from './pages/Clients.svelte';
  import AdBlock from './pages/AdBlock.svelte';
  import Remote from './pages/Remote.svelte';
  import Dns from './pages/Dns.svelte';
  import Internet from './pages/Internet.svelte';
  import Lan from './pages/Lan.svelte';
  import Logs from './pages/Logs.svelte';
  import Maintenance from './pages/Maintenance.svelte';
  import PortForwarding from './pages/PortForwarding.svelte';
  import Restarting from './pages/Restarting.svelte';
  import Schedules from './pages/Schedules.svelte';
  import Setup from './pages/Setup.svelte';
  import More from './pages/More.svelte';
  import Overview from './pages/Overview.svelte';
  import Settings from './pages/Settings.svelte';
  import Vpn from './pages/Vpn.svelte';
  import Wireless from './pages/Wireless.svelte';
  import { getSetupStatus, hasSession, logout, onSessionExpired, type SetupStatus } from './lib/api';
  import { t } from './lib/i18n/index.svelte';
  import { currentRoute, entryFor, navigate } from './lib/router.svelte';
  import { endRestart, restarting } from './lib/restart.svelte';

  let authenticated = $state(hasSession());
  let notice = $state<string | null>(null);
  let setup = $state<SetupStatus | null>(null);

  async function loadSetup() {
    // Without an answer the normal pages show; they report errors themselves.
    setup = await getSetupStatus().catch(() => null);
  }

  $effect(() => {
    loadSetup();
  });

  const route = $derived(currentRoute());
  const title = $derived(t(entryFor(route).label));

  $effect(() =>
    onSessionExpired(() => {
      authenticated = false;
      notice = t('errors.denied');
    }),
  );

  $effect(() => {
    const kind = restarting();
    const page = kind ? t(`restart.title_${kind}`)
      : !authenticated ? null
        : setup && !setup.setup_done ? t('setup.welcome') : title;
    document.title = page ? `${page} · ${t('app.name')}` : t('app.name');
  });

  async function signOut() {
    await logout();
    notice = null;
    authenticated = false;
  }
</script>

{#if restarting()}
  <Restarting
    kind={restarting()!}
    ondone={async () => {
      // Sessions do not survive a restart.
      await logout();
      authenticated = false;
      endRestart();
      navigate('overview');
    }}
  />
{:else if !authenticated}
  <Login
    {notice}
    fresh={setup?.password_set === false || !!setup?.default_password}
    defaultPassword={!!setup?.default_password}
    rescue={setup?.rescue ?? null}
    onlogin={() => {
      authenticated = true;
      notice = null;
      loadSetup();
    }}
  />
{:else if setup && !setup.setup_done}
  <Setup passwordSet={setup.password_set && !setup.default_password}
    ondone={() => (setup = { setup_done: true, password_set: true, default_password: false, rescue: setup!.rescue })} />
{:else}
  <Shell {route} {title} onlogout={signOut}>
    {#if route === 'overview'}
      <Overview />
    {:else if route === 'internet'}
      <Internet />
    {:else if route === 'wireless'}
      <Wireless />
    {:else if route === 'clients'}
      <Clients />
    {:else if route === 'vpn'}
      <Vpn />
    {:else if route === 'lan'}
      <Lan />
    {:else if route === 'dns'}
      <Dns />
    {:else if route === 'adblock'}
      <AdBlock />
    {:else if route === 'remote'}
      <Remote />
    {:else if route === 'ports'}
      <PortForwarding />
    {:else if route === 'logs'}
      <Logs />
    {:else if route === 'schedules'}
      <Schedules />
    {:else if route === 'maintenance'}
      <Maintenance />
    {:else if route === 'settings'}
      <Settings onlogout={signOut} />
    {:else if route === 'more'}
      <More onlogout={signOut} />
    {/if}
  </Shell>
{/if}
