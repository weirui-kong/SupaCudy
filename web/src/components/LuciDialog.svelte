<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts">
  import ConfirmDialog from './ConfirmDialog.svelte';
  import { t } from '../lib/i18n/index.svelte';

  let { open = $bindable(false) }: { open?: boolean } = $props();

  // Opened from the confirm click, so popup blockers allow it.
  function proceed() {
    open = false;
    window.open('/cgi-bin/luci/', '_blank', 'noopener');
  }
</script>

<ConfirmDialog
  bind:open
  title={t('luci.title')}
  message={t('luci.message')}
  consequence={t('luci.consequence')}
  confirmLabel={t('luci.confirm')}
  danger
  onconfirm={proceed}
/>
