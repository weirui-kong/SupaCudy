<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import { encode } from 'uqr';

  let { data, label, size = 220 }: { data: string; label: string; size?: number } = $props();

  // One path of 1×1 squares keeps the SVG small; the quiet zone is in the border.
  const qr = $derived(encode(data, { ecc: 'M', border: 2 }));
  const path = $derived(
    qr.data
      .flatMap((row, y) => row.map((dark, x) => (dark ? `M${x} ${y}h1v1h-1z` : '')))
      .join(''),
  );
</script>

<svg
  class="qr"
  role="img"
  aria-label={label}
  width={size}
  height={size}
  viewBox={`0 0 ${qr.size} ${qr.size}`}
  shape-rendering="crispEdges"
>
  <rect width={qr.size} height={qr.size} class="light" />
  <path d={path} class="dark" />
</svg>

<style>
  /* Scanners expect dark modules on a light background in both themes. */
  .light {
    fill: var(--color-qr-light);
  }

  .dark {
    fill: var(--color-qr-dark);
  }

  .qr {
    display: block;
    max-width: 100%;
    height: auto;
    border-radius: var(--radius-md);
  }
</style>
