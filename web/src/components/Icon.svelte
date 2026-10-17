<!--
  Copyright 2026 SupaCudy contributors
  SPDX-License-Identifier: Apache-2.0
-->
<script lang="ts" module>
  export type IconName =
    | 'home' | 'settings' | 'logout' | 'info' | 'warning' | 'error' | 'check'
    | 'eye' | 'eye-off' | 'sun' | 'moon' | 'monitor' | 'globe' | 'router'
    | 'close' | 'refresh' | 'wifi' | 'ethernet' | 'phone' | 'laptop' | 'desktop'
    | 'tablet' | 'tv' | 'camera' | 'printer' | 'speaker' | 'watch' | 'game'
    | 'appliance' | 'nas' | 'device' | 'more' | 'edit' | 'block' | 'speed'
    | 'trash' | 'plus' | 'network' | 'arrow-up' | 'arrow-down' | 'chevron-right' | 'chevron-down'
    | 'shield' | 'key' | 'lock' | 'apps' | 'power' | 'upload' | 'clock' | 'link'
    | 'qr' | 'usb' | 'list' | 'guest' | 'dns' | 'pin' | 'download';

  const PATHS: Record<IconName, string> = {
    home: 'M3 11.5 12 4l9 7.5M5.5 9.8V20h13V9.8M10 20v-5.5h4V20',
    settings: 'M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4ZM19.4 13.5a7.6 7.6 0 0 0 0-3l2-1.6-2-3.4-2.4.9a7.7 7.7 0 0 0-2.6-1.5L14 2.5h-4l-.4 2.4A7.7 7.7 0 0 0 7 6.4l-2.4-.9-2 3.4 2 1.6a7.6 7.6 0 0 0 0 3l-2 1.6 2 3.4 2.4-.9c.8.7 1.6 1.2 2.6 1.5l.4 2.4h4l.4-2.4c1-.3 1.8-.8 2.6-1.5l2.4.9 2-3.4-2-1.6Z',
    logout: 'M15 4h3.5A1.5 1.5 0 0 1 20 5.5v13a1.5 1.5 0 0 1-1.5 1.5H15M10 16l-4-4 4-4M6 12h10',
    info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 11v5.5M12 7.6v.4',
    warning: 'M10.3 4.2 2.6 18a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 4.2a2 2 0 0 0-3.4 0ZM12 9.5v4.5M12 17.2v.3',
    error: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM9 9l6 6M15 9l-6 6',
    check: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM8 12.3l2.7 2.7L16 9.6',
    eye: 'M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12ZM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
    'eye-off': 'M4 4l16 16M9.9 6A9.9 9.9 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-2.6 3.3M6.4 7.6A16.8 16.8 0 0 0 2.5 12S6 18.5 12 18.5c1.5 0 2.9-.4 4.1-1M9.9 9.9a3 3 0 0 0 4.2 4.2',
    sun: 'M12 16.5a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9ZM12 2v2M12 20v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M2 12h2M20 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
    moon: 'M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11Z',
    monitor: 'M3.5 5h17v11h-17zM9 20h6M12 16v4',
    globe: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9s-1.2 6.4-3.7 9c-2.5-2.6-3.7-5.6-3.7-9S9.5 5.6 12 3Z',
    router: 'M4 13.5h16v5H4zM7.5 16h.01M11 16h.01M8 10a5.5 5.5 0 0 1 8 0M5.5 7.5a9 9 0 0 1 13 0',
    close: 'M6 6l12 12M18 6 6 18',
    refresh: 'M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5',
    wifi: 'M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.6 16a5 5 0 0 1 6.8 0M12 19.5h.01',
    ethernet: 'M5 4h14v11h-3v3H8v-3H5zM9 8v3M12 8v3M15 8v3M9 21h6',
    phone: 'M8 2.5h8a1.5 1.5 0 0 1 1.5 1.5v16a1.5 1.5 0 0 1-1.5 1.5H8A1.5 1.5 0 0 1 6.5 20V4A1.5 1.5 0 0 1 8 2.5ZM11 18.5h2',
    laptop: 'M5 5.5h14v9.5H5zM2.5 18.5h19',
    desktop: 'M3 4.5h18v11.5H3zM9 20h6M12 16v4',
    tablet: 'M6 2.5h12A1.5 1.5 0 0 1 19.5 4v16a1.5 1.5 0 0 1-1.5 1.5H6A1.5 1.5 0 0 1 4.5 20V4A1.5 1.5 0 0 1 6 2.5ZM11 18.5h2',
    tv: 'M3 6h18v11.5H3zM8 21h8M9 2.5l3 3 3-3',
    camera: 'M4 7.5h3l1.5-2h7l1.5 2h3v11H4zM12 16a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
    printer: 'M7 9V3.5h10V9M6 18H4V9h16v9h-2M7 14h10v6.5H7z',
    speaker: 'M6.5 2.5h11v19h-11zM12 18a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM12 7.5h.01',
    watch: 'M8 6.5h8v11H8zM9.5 6.5 10 2.5h4l.5 4M9.5 17.5l.5 4h4l.5-4',
    game: 'M6.5 8h11a4 4 0 0 1 3.9 4.9l-.9 4a2.5 2.5 0 0 1-4.3 1.1L14.5 16h-5l-1.7 2a2.5 2.5 0 0 1-4.3-1.1l-.9-4A4 4 0 0 1 6.5 8ZM8 11v3M6.5 12.5h3M15.5 12h.01M17.5 13.5h.01',
    appliance: 'M5 2.5h14v19H5zM5 8h14M12 15.5a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM8 5.2h.01',
    nas: 'M5 3.5h14v7H5zM5 13.5h14v7H5zM8 7h.01M8 17h.01M12 7h4M12 17h4',
    device: 'M4 5h16v10.5H4zM8 19.5h8M12 15.5v4',
    more: 'M5.5 12h.01M12 12h.01M18.5 12h.01',
    edit: 'M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4',
    block: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM5.6 5.6l12.8 12.8',
    speed: 'M4.5 17a8.5 8.5 0 1 1 15 0M12 13l4-5M12 14a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z',
    trash: 'M4 6.5h16M9.5 6.5V4h5v2.5M6.5 6.5l1 14h9l1-14M10 10.5v6M14 10.5v6',
    plus: 'M12 5v14M5 12h14',
    network: 'M12 3.5v5M5 15.5v-3.5h14v3.5M9.5 3.5h5v5h-5zM2.5 15.5h5v5h-5zM9.5 15.5h5v5h-5zM16.5 15.5h5v5h-5zM12 12v3.5',
    'arrow-up': 'M12 19V5M6 11l6-6 6 6',
    'arrow-down': 'M12 5v14M6 13l6 6 6-6',
    'chevron-right': 'M9 5l7 7-7 7',
    'chevron-down': 'M5 9l7 7 7-7',
    shield: 'M12 2.5 20 6v6c0 4.7-3.4 8.4-8 9.5-4.6-1.1-8-4.8-8-9.5V6zM8.5 12l2.5 2.5 4.5-5',
    key: 'M14.5 9.5a5 5 0 1 0-4.6 5L12 16.5h2.5V19H17v2.5h4V18l-6.5-6.5a5 5 0 0 0 0-2ZM16 7h.01',
    lock: 'M5.5 10.5h13v10h-13zM8.5 10.5V7a3.5 3.5 0 0 1 7 0v3.5M12 14.5v2.5',
    apps: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
    power: 'M12 3v8M6.4 6.4a8 8 0 1 0 11.2 0',
    upload: 'M12 16V4M7 9l5-5 5 5M4 16v4h16v-4',
    clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 7v5l3.5 2',
    link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
    qr: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2.5v2.5H14zM17.5 17.5H20V20h-2.5zM14 18h1.5v2H14zM18 14h2v1.5h-2z',
    usb: 'M12 21V7M8.5 7 12 3l3.5 4M7 11v3l5 3M17 10v2l-5 3M6 9h2v2H6zM16 8h2v2h-2z',
    list: 'M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01',
    guest: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 6.5M18.5 14.5a6.5 6.5 0 0 1 3 5.5',
    dns: 'M3.5 4.5h17v6h-17zM3.5 13.5h17v6h-17zM7 7.5h.01M7 16.5h.01',
    download: 'M12 4v11M7 10.5l5 5 5-5M4 20h16',
    pin: 'M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11ZM12 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z',
  };
</script>

<script lang="ts">
  let { name, size = 20 }: { name: IconName; size?: number } = $props();
</script>

<svg
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.8"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
  focusable="false"
>
  <path d={PATHS[name]} />
</svg>
