<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import Banner from '../../components/Banner.svelte';
  import Button from '../../components/Button.svelte';
  import Card from '../../components/Card.svelte';
  import Switch from '../../components/Switch.svelte';
  import TextField from '../../components/TextField.svelte';
  import { GUARD_LIMITS, getGuard, guardFieldError, setGuard, unbanAddress, type GuardState } from '../../lib/api';
  import { errorMessage } from '../../lib/errors';
  import { formatDuration } from '../../lib/format';
  import { t } from '../../lib/i18n/index.svelte';
  import { apply } from '../../lib/notify.svelte';

  type Field = keyof typeof GUARD_LIMITS;
  const FIELDS: Field[] = ['attempts', 'window', 'ban'];

  let guard = $state<GuardState | null>(null);
  let error = $state<string | null>(null);
  let busy = $state(false);
  let values = $state<Record<Field, string>>({ attempts: '', window: '', ban: '' });

  async function load(fill = false) {
    try {
      const g = await getGuard();
      guard = g;
      if (fill) values = { attempts: String(g.attempts), window: String(g.window), ban: String(g.ban) };
      error = null;
    } catch (err) {
      error = errorMessage(err);
    }
  }

  $effect(() => {
    load(true);
    const timer = setInterval(() => load(), 30_000);
    return () => clearInterval(timer);
  });

  const errors = $derived(
    Object.fromEntries(FIELDS.map((f) => [f, guardFieldError(f, values[f]) ? t('guard.range', { min: GUARD_LIMITS[f][0], max: GUARD_LIMITS[f][1] }) : null])) as Record<Field, string | null>,
  );
  const valid = $derived(FIELDS.every((f) => !errors[f]));
  const changed = $derived(!!guard && FIELDS.some((f) => values[f].trim() !== String(guard![f])));

  async function save(enabled: boolean, numbers: Record<Field, number>) {
    busy = true;
    await apply(() => setGuard({ enabled, ...numbers }));
    busy = false;
    await load(true);
  }

  const saved = () => ({ attempts: guard!.attempts, window: guard!.window, ban: guard!.ban });

  function submit(event: SubmitEvent) {
    event.preventDefault();
    if (!guard || !valid || !changed) return;
    save(guard.enabled, { attempts: Number(values.attempts), window: Number(values.window), ban: Number(values.ban) });
  }

  async function unban(ip: string) {
    busy = true;
    await apply(() => unbanAddress(ip), t('guard.unbanned', { ip }));
    busy = false;
    await load();
  }
</script>

<Card title={t('guard.title')}>
  {#if error}<Banner kind="error">{error}</Banner>{/if}
  {#if guard}
    <form class="stack" onsubmit={submit}>
      <p class="hint">{t('guard.hint', { attempts: guard.attempts, window: guard.window, ban: guard.ban })}</p>
      <Switch label={t('guard.enable')} checked={guard.enabled} disabled={busy} onchange={(v) => save(v, saved())} />
      {#if guard.enabled}
        <div class="fields">
          <TextField label={t('guard.attempts')} bind:value={values.attempts} inputmode="numeric" error={errors.attempts} />
          <TextField label={t('guard.window')} bind:value={values.window} inputmode="numeric" suffix={t('guard.minutes')} error={errors.window} />
          <TextField label={t('guard.ban')} bind:value={values.ban} inputmode="numeric" suffix={t('guard.minutes')} error={errors.ban} />
        </div>
        <div class="actions">
          <Button onclick={() => load(true)} disabled={!changed || busy}>{t('common.reset')}</Button>
          <Button variant="primary" type="submit" {busy} disabled={!changed || !valid}>{t('common.apply')}</Button>
        </div>
        <h3>{t('guard.banned')}</h3>
        {#if guard.banned.length}
          <ul class="banned">
            {#each guard.banned as b (b.ip)}
              <li>
                <span class="ip">{b.ip}</span>
                <span class="left">{b.expires !== null ? t('guard.expires', { time: formatDuration(b.expires, t) }) : ''}</span>
                <Button variant="ghost" onclick={() => unban(b.ip)} disabled={busy}>
                  {t('guard.unban')}<span class="visually-hidden"> {b.ip}</span>
                </Button>
              </li>
            {/each}
          </ul>
        {:else}
          <p class="hint">{t('guard.none')}</p>
        {/if}
        <p class="hint">{t('guard.reboot_hint')}</p>
      {/if}
    </form>
  {/if}
</Card>

<style>
  .stack {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .hint {
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  .fields {
    display: grid;
    gap: var(--space-4);
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
  }

  h3 {
    font-size: var(--font-size-md);
  }

  .banned {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .banned li {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-2) var(--space-3);
    padding: var(--space-2) 0;
    border-top: 1px solid var(--color-border);
  }

  .banned li:first-child {
    border-top: 0;
  }

  .ip {
    font-weight: 600;
    overflow-wrap: anywhere;
  }

  .left {
    flex: 1;
    color: var(--color-text-muted);
    font-size: var(--font-size-sm);
  }

  @media (min-width: 768px) {
    .fields {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }
  }
</style>
