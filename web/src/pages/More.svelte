<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Card from '../components/Card.svelte';
  import Icon from '../components/Icon.svelte';
  import LuciDialog from '../components/LuciDialog.svelte';
  import { t } from '../lib/i18n/index.svelte';
  import { GROUPS, ROUTES, href } from '../lib/router.svelte';

  let { onlogout }: { onlogout: () => void } = $props();
  let luci = $state(false);

  const sections = GROUPS.map(({ group, label }) => ({
    group,
    label,
    entries: ROUTES.filter((entry) => entry.group === group && !entry.primary),
  })).filter((section) => section.entries.length > 0);
</script>

<div class="stack">
  {#each sections as section (section.group)}
    <Card title={section.label ? t(section.label) : t('nav.more')}>
      <ul>
        {#each section.entries as entry (entry.route)}
          <li>
            <a href={href(entry.route)}>
              <Icon name={entry.icon} />
              <span>{t(entry.label)}</span>
              <Icon name="chevron-right" size={18} />
            </a>
          </li>
        {/each}
      </ul>
    </Card>
  {/each}

  <button type="button" class="action" onclick={() => (luci = true)}>
    <Icon name="link" />
    {t('nav.luci')}
  </button>

  <button type="button" class="action danger" onclick={onlogout}>
    <Icon name="logout" />
    {t('nav.logout')}
  </button>
</div>

<LuciDialog bind:open={luci} />

<style>
  .stack {
    display: grid;
    gap: var(--space-4);
  }

  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  a {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    min-height: 52px;
    color: var(--color-text);
    text-decoration: none;
    border-top: 1px solid var(--color-border);
  }

  li:first-child a {
    border-top: 0;
  }

  a span {
    flex: 1;
  }

  a :global(svg:last-child) {
    color: var(--color-text-muted);
  }

  .action {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    min-height: var(--touch-target);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface);
    color: var(--color-text);
    font-weight: 600;
    cursor: pointer;
  }

  .danger {
    color: var(--color-danger);
  }
</style>
