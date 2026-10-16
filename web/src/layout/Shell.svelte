<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon from '../components/Icon.svelte';
  import { t } from '../lib/i18n/index.svelte';
  import { ROUTES, href, type Route } from '../lib/router.svelte';

  let {
    route,
    title,
    onlogout,
    children,
  }: { route: Route; title: string; onlogout: () => void; children: Snippet } = $props();
</script>

<a class="skip" href="#main">{t('app.skip_to_content')}</a>

<div class="shell">
  <header class="topbar">
    <span class="brand"><Icon name="router" size={22} />{t('app.name')}</span>
  </header>

  <nav class="sidebar" aria-label={t('nav.main')}>
    <span class="brand"><Icon name="router" size={24} />{t('app.name')}</span>
    <ul>
      {#each ROUTES as entry (entry.route)}
        <li>
          <a href={href(entry.route)} aria-current={entry.route === route ? 'page' : undefined}>
            <Icon name={entry.icon} />
            <span>{t(entry.label)}</span>
          </a>
        </li>
      {/each}
    </ul>
    <button type="button" class="logout" onclick={onlogout}>
      <Icon name="logout" />
      <span>{t('nav.logout')}</span>
    </button>
  </nav>

  <main id="main" tabindex="-1">
    <h1>{title}</h1>
    {@render children()}
  </main>

  <nav class="bottom-nav" aria-label={t('nav.main')}>
    {#each ROUTES as entry (entry.route)}
      <a href={href(entry.route)} aria-current={entry.route === route ? 'page' : undefined}>
        <Icon name={entry.icon} size={22} />
        <span>{t(entry.label)}</span>
      </a>
    {/each}
  </nav>
</div>

<style>
  .skip {
    position: absolute;
    left: var(--space-2);
    top: -100px;
    z-index: 100;
    display: inline-flex;
    align-items: center;
    min-height: var(--touch-target);
    padding: 0 var(--space-4);
    background: var(--color-surface);
    border-radius: var(--radius-sm);
  }

  .skip:focus {
    top: var(--space-2);
  }

  .brand {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-weight: 700;
    color: var(--color-text);
  }

  /* Phone: top bar, content, fixed bottom navigation. */
  .topbar {
    position: sticky;
    top: 0;
    z-index: 5;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    height: 56px;
    padding: 0 var(--space-4);
    background: var(--color-nav-bg);
    border-bottom: 1px solid var(--color-border);
  }

  .sidebar {
    display: none;
  }

  main {
    padding: var(--space-4);
    padding-bottom: calc(var(--bottom-nav-height) + var(--space-5) + env(safe-area-inset-bottom));
    max-width: var(--content-max-width);
    outline: none;
  }

  h1 {
    font-size: var(--font-size-xl);
    margin-bottom: var(--space-4);
  }

  .bottom-nav {
    position: fixed;
    inset: auto 0 0;
    z-index: 5;
    display: flex;
    height: calc(var(--bottom-nav-height) + env(safe-area-inset-bottom));
    padding-bottom: env(safe-area-inset-bottom);
    background: var(--color-nav-bg);
    border-top: 1px solid var(--color-border);
  }

  .bottom-nav a {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 2px;
    min-height: var(--touch-target);
    color: var(--color-text-muted);
    font-size: var(--font-size-xs);
    text-decoration: none;
  }

  .bottom-nav a[aria-current="page"] {
    color: var(--color-nav-active-text);
    font-weight: 600;
  }

  /* Tablet and desktop: persistent sidebar, no bottom bar. */
  @media (min-width: 768px) {
    .topbar,
    .bottom-nav {
      display: none;
    }

    .shell {
      display: grid;
      grid-template-columns: var(--sidebar-width) minmax(0, 1fr);
      min-height: 100vh;
    }

    .sidebar {
      position: sticky;
      top: 0;
      height: 100vh;
      display: flex;
      flex-direction: column;
      gap: var(--space-5);
      padding: var(--space-5) var(--space-3);
      background: var(--color-nav-bg);
      border-right: 1px solid var(--color-border);
    }

    .sidebar .brand {
      padding: 0 var(--space-3);
      font-size: var(--font-size-lg);
    }

    .sidebar ul {
      list-style: none;
      margin: 0;
      padding: 0;
      display: flex;
      flex-direction: column;
      gap: var(--space-1);
    }

    .sidebar a,
    .logout {
      display: flex;
      align-items: center;
      gap: var(--space-3);
      width: 100%;
      min-height: var(--touch-target);
      padding: 0 var(--space-3);
      border-radius: var(--radius-md);
      color: var(--color-text);
      text-decoration: none;
      font-size: var(--font-size-md);
    }

    .sidebar a:hover,
    .logout:hover {
      background: var(--color-surface-muted);
    }

    .sidebar a[aria-current="page"] {
      background: var(--color-nav-active-bg);
      color: var(--color-nav-active-text);
      font-weight: 600;
    }

    .logout {
      margin-top: auto;
      border: 0;
      background: none;
      color: var(--color-text-muted);
      cursor: pointer;
    }

    main {
      padding: var(--space-6);
      width: 100%;
    }

    h1 {
      font-size: var(--font-size-2xl);
      margin-bottom: var(--space-5);
    }
  }
</style>
