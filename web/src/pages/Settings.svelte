<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import AppearanceControls from '../components/AppearanceControls.svelte';
  import Card from '../components/Card.svelte';
  import Icon from '../components/Icon.svelte';
  import PasswordCard from './settings/PasswordCard.svelte';
  import TimeCard from './settings/TimeCard.svelte';
  import { t } from '../lib/i18n/index.svelte';

  let { onlogout }: { onlogout: () => void } = $props();
</script>

<div class="stack">
  <Card title={t('settings.appearance')}>
    <AppearanceControls />
  </Card>

  <TimeCard />
  <PasswordCard />

  <Card title={t('settings.session')}>
    <div class="session">
      <p>{t('settings.logout_hint')}</p>
      <button type="button" class="logout" onclick={onlogout}>
        <Icon name="logout" />
        {t('nav.logout')}
      </button>
    </div>
  </Card>
</div>

<style>
  .stack {
    display: grid;
    gap: var(--space-4);
    max-width: 760px;
  }

  .session {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    align-items: flex-start;
  }

  p {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .logout {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    min-height: var(--touch-target);
    padding: 0 var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface);
    cursor: pointer;
  }

  .logout:hover {
    background: var(--color-surface-muted);
  }

  @media (min-width: 768px) {
    .session {
      flex-direction: row;
      align-items: center;
      justify-content: space-between;
    }
  }
</style>
