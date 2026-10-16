<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Segmented from './Segmented.svelte';
  import { LOCALES, locale, setLocale, t, type Locale } from '../lib/i18n/index.svelte';
  import { THEMES, setThemePreference, themePreference, type ThemePreference } from '../lib/theme.svelte';

  let { compact = false }: { compact?: boolean } = $props();

  const THEME_ICONS = { system: 'monitor', light: 'sun', dark: 'moon' } as const;
  const THEME_LABELS = { system: 'settings.theme_system', light: 'settings.theme_light', dark: 'settings.theme_dark' } as const;

  const localeOptions = $derived(LOCALES.map((value) => ({ value, label: t(`languages.${value}`) })));
  const themeOptions = $derived(
    THEMES.map((value) => ({ value, label: t(THEME_LABELS[value]), icon: THEME_ICONS[value] })),
  );
</script>

<div class="controls" class:compact>
  <div class="control">
    <span class="label" aria-hidden="true">{t('settings.language')}</span>
    <Segmented
      label={t('settings.language')}
      options={localeOptions}
      value={locale()}
      onchange={(value: Locale) => setLocale(value)}
    />
  </div>
  <div class="control">
    <span class="label" aria-hidden="true">{t('settings.theme')}</span>
    <Segmented
      label={t('settings.theme')}
      options={themeOptions}
      value={themePreference()}
      onchange={(value: ThemePreference) => setThemePreference(value)}
    />
  </div>
</div>

<style>
  .controls {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .control {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .label {
    font-size: var(--font-size-sm);
    font-weight: 600;
  }

  .compact .label {
    font-weight: 400;
    color: var(--color-text-muted);
  }

  @media (min-width: 768px) {
    .controls:not(.compact) .control {
      flex-direction: row;
      align-items: center;
      justify-content: space-between;
      gap: var(--space-5);
    }
  }
</style>
