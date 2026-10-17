<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../components/Banner.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import DataRow from '../components/DataRow.svelte';
  import Switch from '../components/Switch.svelte';
  import TextField from '../components/TextField.svelte';
  import WebAccessDialog from './adblock/WebAccessDialog.svelte';
  import {
    addAdguardList, filterUrlError, getAdguard, lines, listNameOf, removeAdguardList, setAdguardEnabled,
    setAdguardList, setAdguardLogging, setAdguardProtection, setAdguardRules, setAdguardWeb, type AdguardState,
  } from '../lib/api';
  import { errorMessage } from '../lib/errors';
  import { locale, t } from '../lib/i18n/index.svelte';
  import { apply } from '../lib/notify.svelte';

  let ag = $state<AdguardState | null>(null);
  let error = $state<string | null>(null);
  let rulesText = $state('');
  let newUrl = $state('');
  let busy = $state(false);
  let confirmOff = $state(false);
  let confirmWebOff = $state(false);
  let webDialog = $state(false);

  // The rules box is only refilled when it has no unsaved edits, so the
  // periodic refresh never throws away typing.
  async function load(refillRules = false) {
    try {
      const next = await getAdguard();
      if (refillRules || (ag && lines(rulesText).join('\n') === (ag.rules ?? []).join('\n')))
        rulesText = (next.rules ?? []).join('\n');
      ag = next;
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load(true);
    const timer = setInterval(() => load(), 15_000);
    return () => clearInterval(timer);
  });

  async function change(call: () => Promise<unknown>, reloadAfterMs = 0): Promise<boolean> {
    busy = true;
    const ok = (await apply(call)) !== null;
    busy = false;
    confirmOff = false;
    confirmWebOff = false;
    // Re-read after a failure too, so the switches show what is really set.
    await load(true);
    if (ok && reloadAfterMs) setTimeout(() => load(true), reloadAfterMs);
    return ok;
  }

  async function addList() {
    const url = newUrl.trim();
    if (await change(() => addAdguardList(url, listNameOf(url)))) newUrl = '';
  }

  const number = (n: number) => new Intl.NumberFormat(locale()).format(n);
  const blockedPct = $derived(ag?.stats?.queries ? Math.round((ag.stats.blocked / ag.stats.queries) * 1000) / 10 : 0);
  const badUrl = $derived(newUrl.trim() !== '' && filterUrlError(newUrl.trim()));
  const rulesChanged = $derived(!!ag?.rules && lines(rulesText).join('\n') !== ag.rules.join('\n'));
  const host = $derived(location.hostname.includes(':') ? `[${location.hostname}]` : location.hostname);
  const webUrl = $derived(ag ? `http://${host}:${ag.web.port}/` : '');
  const live = $derived(!!ag && ag.enabled && ag.filters != null);
</script>

{#if error}<Banner kind="error">{error}</Banner>{/if}

{#if ag && !ag.installed}
  <Banner kind="warning">{t('adblock.missing')}</Banner>
{:else if ag}
  <div class="grid">
    <Card title={t('adblock.title')}>
      <div class="stack">
        <p class="hint">{t('adblock.hint')}</p>
        <Switch
          label={t('adblock.enable')}
          description={t('adblock.enable_hint')}
          checked={ag.enabled}
          disabled={busy}
          onchange={(v) => (v ? change(() => setAdguardEnabled(true), 5000) : (confirmOff = true))}
        />
        {#if ag.enabled}
          {#if ag.protection != null}
            <Switch
              label={t('adblock.protection')}
              description={t('adblock.protection_hint')}
              checked={ag.protection}
              disabled={busy}
              onchange={(v) => change(() => setAdguardProtection(v))}
            />
          {/if}
          {#if ag.fallback}
            <Banner kind="warning">{t('adblock.fallback')}</Banner>
          {:else if ag.locked}
            <Banner kind="warning">{t('adblock.locked')}</Banner>
          {:else if !ag.running}
            <Banner kind="warning">{t('adblock.not_running')}</Banner>
          {/if}
        {/if}
      </div>
    </Card>

    {#if live && ag.logging}
      {@const logging = ag.logging}
      <Card title={t('adblock.stats')}>
        <div class="stack">
          <Switch
            label={t('adblock.keep_stats')}
            description={t('adblock.keep_stats_hint')}
            checked={logging.statistics}
            disabled={busy}
            onchange={(v) => change(() => setAdguardLogging({ ...logging, statistics: v }))}
          />
          <Switch
            label={t('adblock.keep_querylog')}
            description={t('adblock.keep_querylog_hint')}
            checked={logging.querylog}
            disabled={busy}
            onchange={(v) => change(() => setAdguardLogging({ ...logging, querylog: v }))}
          />
          {#if !logging.statistics}
            <p class="hint">{t('adblock.stats_off')}</p>
          {:else if ag.stats}
            <div>
              <h3>{t('adblock.stats_period')}</h3>
              <dl>
                <DataRow label={t('adblock.queries')}>{number(ag.stats.queries)}</DataRow>
                <DataRow label={t('adblock.blocked')}>{t('adblock.blocked_value', { count: number(ag.stats.blocked), pct: blockedPct })}</DataRow>
                <DataRow label={t('adblock.avg')}>{t('adblock.avg_value', { ms: ag.stats.avg_ms })}</DataRow>
              </dl>
            </div>
            {#if ag.stats.top_blocked.length}
              <div>
                <h3>{t('adblock.top_blocked')}</h3>
                <ol class="top">
                  {#each ag.stats.top_blocked as d (d.name)}<li><span>{d.name}</span><span>{number(d.count)}</span></li>{/each}
                </ol>
              </div>
            {/if}
          {/if}
        </div>
      </Card>
    {/if}

    {#if live && ag.filters}
      <Card title={t('adblock.lists')}>
        <div class="stack">
          {#each ag.filters as f (f.url)}
            <div class="list">
              <Switch
                label={f.name}
                description={f.rules != null && f.enabled ? t('adblock.rules_count', { count: number(f.rules) }) : f.url}
                checked={f.enabled}
                disabled={busy}
                onchange={(on) => change(() => setAdguardList({ url: f.url, name: f.name, enabled: on }))}
              />
              <Button variant="ghost" icon="trash" label={t('common.delete_named', { name: f.name })} disabled={busy}
                onclick={() => change(() => removeAdguardList(f.url))} />
            </div>
          {/each}
          {#if !ag.filters.length}<p class="hint">{t('adblock.no_lists')}</p>{/if}
          {#each ag.suggested as s (s.url)}
            <Switch label={s.name} description={t('adblock.suggested')} checked={false} disabled={busy}
              onchange={() => change(() => addAdguardList(s.url, s.name))} />
          {/each}
          <form class="add" onsubmit={(e) => { e.preventDefault(); if (!badUrl && newUrl.trim()) addList(); }}>
            <TextField label={t('adblock.add_list')} hint={t('adblock.add_list_hint')} type="url" bind:value={newUrl}
              error={badUrl ? t('adblock.url_bad', { value: newUrl.trim() }) : null} autocomplete="off" spellcheck="false" />
            <Button type="submit" icon="plus" {busy} disabled={badUrl || !newUrl.trim()}>{t('adblock.add')}</Button>
          </form>
        </div>
      </Card>

      <Card title={t('adblock.rules')}>
        <div class="stack">
          <label class="area">
            <span class="hint">{t('adblock.rules_hint')}</span>
            <textarea aria-label={t('adblock.rules')} bind:value={rulesText} rows="6" spellcheck="false" autocomplete="off"></textarea>
          </label>
          <div class="actions">
            <Button variant="primary" {busy} disabled={!rulesChanged} onclick={() => change(() => setAdguardRules(lines(rulesText)))}>
              {t('common.apply')}
            </Button>
          </div>
        </div>
      </Card>
    {/if}

    {#if ag.enabled}
      <Card title={t('adblock.web_title')}>
        <div class="stack">
          <p class="hint">{t('adblock.web_hint')}</p>
          {#if ag.web.enabled && !ag.web.synced}
            <Banner kind="warning">{t('adblock.web_unsynced')}</Banner>
          {/if}
          {#if ag.web.enabled}
            <dl>
              <DataRow label={t('adblock.web_address')}>{webUrl}</DataRow>
              <DataRow label={t('adblock.web_user')}>{ag.web.user}</DataRow>
              <DataRow label={t('adblock.web_password')}>{t('adblock.web_password_same')}</DataRow>
            </dl>
            <div class="actions wrap">
              <Button variant="ghost" disabled={busy} onclick={() => (confirmWebOff = true)}>{t('adblock.web_off')}</Button>
              {#if !ag.web.synced}
                <Button disabled={busy} onclick={() => (webDialog = true)}>{t('adblock.web_sync')}</Button>
              {/if}
              <a class="button-link" href={webUrl} target="_blank" rel="noopener">
                {t('adblock.web_open')}<span class="visually-hidden"> {t('common.new_window')}</span>
              </a>
            </div>
          {:else}
            <div class="actions">
              <Button variant="primary" disabled={busy}
                onclick={() => (ag!.web.synced ? change(() => setAdguardWeb(true), 3000) : (webDialog = true))}>{t('adblock.web_on')}</Button>
            </div>
          {/if}
        </div>
      </Card>
    {/if}
  </div>
{:else if !error}
  <p>{t('common.loading')}</p>
{/if}

<WebAccessDialog
  bind:open={webDialog}
  {busy}
  onsubmit={async (password) => {
    if (await change(() => setAdguardWeb(true, password), 3000)) webDialog = false;
  }}
/>

<ConfirmDialog
  bind:open={confirmOff}
  title={t('adblock.disable_title')}
  message={t('adblock.disable_confirm')}
  consequence={t('adblock.disable_consequence')}
  confirmLabel={t('adblock.disable')}
  {busy}
  onconfirm={() => change(() => setAdguardEnabled(false), 4000)}
/>

<ConfirmDialog
  bind:open={confirmWebOff}
  title={t('adblock.web_off')}
  message={t('adblock.web_off_confirm')}
  consequence={t('adblock.web_off_consequence')}
  confirmLabel={t('adblock.web_off')}
  {busy}
  onconfirm={() => change(() => setAdguardWeb(false), 3000)}
/>

<style>
  .grid {
    display: grid;
    gap: var(--space-4);
    align-items: start;
  }

  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
    font-weight: 400;
  }

  dl {
    margin: 0 0 var(--space-3);
  }

  h3 {
    font-size: var(--font-size-md);
    margin-bottom: var(--space-2);
  }

  .top {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .top li {
    display: flex;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-1) 0;
    border-top: 1px solid var(--color-border);
    font-size: var(--font-size-sm);
    overflow-wrap: anywhere;
  }

  .list {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .list > :global(:first-child) {
    flex: 1;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .add {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    align-items: stretch;
  }

  .area {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  textarea {
    width: 100%;
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface);
    color: var(--color-text);
    font-family: var(--font-mono);
    font-size: var(--font-size-sm);
    resize: vertical;
  }

  textarea:focus-visible {
    outline: 2px solid var(--color-focus);
    outline-offset: 1px;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }

  .wrap {
    flex-wrap: wrap;
  }

  .button-link {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding: 0 var(--space-4);
    border-radius: var(--radius-md);
    background: var(--color-accent);
    color: var(--color-on-accent);
    font-weight: 600;
    text-decoration: none;
  }

  .button-link:hover {
    background: var(--color-accent-hover);
  }

  .button-link:focus-visible {
    outline: 2px solid var(--color-focus);
    outline-offset: 2px;
  }

  @media (min-width: 640px) {
    .add {
      flex-direction: row;
      align-items: flex-start;
    }

    .add > :global(:first-child) {
      flex: 1;
    }

    .add > :global(button) {
      margin-top: calc(var(--font-size-sm) * 1.5 + var(--space-1));
    }
  }

  @media (min-width: 1200px) {
    .grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
</style>
