// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

/// <reference types="vitest/config" />
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// The dev server proxies the API to a router or to the smoke-test container
// (scripts/smoke-test.sh --keep), so the UI can be developed without flashing.
const target = process.env.SUPACUDY_TARGET ?? 'http://localhost:8080';

export default defineConfig({
  plugins: [svelte()],
  base: './',
  build: {
    outDir: '../packages/supacudy-ui/htdocs',
    emptyOutDir: true,
    assetsInlineLimit: 0,
  },
  server: {
    proxy: { '/ubus': target },
  },
  resolve: process.env.VITEST ? { conditions: ['browser'] } : undefined,
  test: {
    environment: 'jsdom',
    include: ['tests/unit/**/*.test.ts'],
    setupFiles: ['tests/unit/setup.ts'],
  },
});
