// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// The source of truth for message keys; zh-CN.ts must mirror this shape.
const en = {
  app: {
    name: 'SupaCudy',
    skip_to_content: 'Skip to content',
  },
  nav: {
    main: 'Main navigation',
    overview: 'Overview',
    settings: 'Settings',
    logout: 'Log out',
  },
  login: {
    title: 'Log in',
    subtitle: 'Enter the admin password to manage your router.',
    password: 'Admin password',
    show_password: 'Show password',
    hide_password: 'Hide password',
    submit: 'Log in',
    submitting: 'Logging in…',
    wrong_password: 'Wrong password. Please try again.',
  },
  overview: {
    title: 'Overview',
    device: 'Device',
    model: 'Model',
    board: 'Board',
    openwrt: 'OpenWrt',
    supacudy: 'SupaCudy',
    system: 'System',
    uptime: 'Up time',
    load: 'Load average',
    load_hint: 'Average number of processes waiting for the CPU over the last 1, 5 and 15 minutes. Values above the number of CPU cores mean the router is busy.',
    load_value: '{one} / {five} / {fifteen}',
    cpus: 'CPU cores',
    memory: 'Memory',
    memory_value: '{used} of {total} used',
    memory_hint: 'Memory available to Linux. Part of the physical memory is reserved for Wi-Fi, so the total is lower than the hardware spec.',
    refresh_failed: 'Could not refresh the status. Retrying automatically.',
  },
  settings: {
    title: 'Settings',
    appearance: 'Appearance',
    language: 'Language',
    theme: 'Theme',
    theme_system: 'System',
    theme_light: 'Light',
    theme_dark: 'Dark',
    session: 'Session',
    logout_hint: 'Log out of the admin panel on this browser.',
  },
  time: {
    minutes: '{m} min',
    hours_minutes: '{h} h {m} min',
    days_hours: '{d} d {h} h',
  },
  common: {
    unavailable: '—',
    more_info: 'More information',
    close: 'Close',
    loading: 'Loading…',
  },
  errors: {
    network: 'Cannot reach the router. Check your connection and try again.',
    denied: 'Your session has expired. Please log in again.',
    unknown: 'Something went wrong (error {code}). Please try again.',
  },
  languages: {
    en: 'English',
    'zh-CN': '简体中文',
  },
};

export default en;
