<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  let { title, children }: { title: string; children: Snippet } = $props();
  const uid = $props.id();
  const headingId = `card-${uid}`;
</script>

<section class="card" aria-labelledby={headingId}>
  <h2 id={headingId}>{title}</h2>
  {@render children()}
</section>

<style>
  .card {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    padding: var(--space-4);
    box-shadow: 0 1px 2px var(--color-shadow);
    min-width: 0;
  }

  h2 {
    font-size: var(--font-size-lg);
    font-weight: 600;
    margin-bottom: var(--space-3);
  }

  @media (min-width: 768px) {
    .card {
      padding: var(--space-5);
    }
  }
</style>
