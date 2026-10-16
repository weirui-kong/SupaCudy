# Testing rules

## Requirements

- **Every requirement ships with thorough test cases**, committed in the same change as the feature.
- Each feature's tests cover the happy path, invalid or malformed input, and permission boundaries (rejected when not logged in or not allowed).
- When fixing a bug, first write a test that reproduces it, then fix it.
- Tests must be deterministic: no dependence on run order, the internet (except `opkg` installing official packages inside the test container) or wall-clock time.
- Never make tests pass by deleting, skipping or loosening assertions. If a test genuinely has to change, say why in the commit message.

## Test categories

| Category | Location | Covers | Runs in |
|---|---|---|---|
| lint | `tests/lint/` | `shellcheck` on host scripts (bash) and on-device scripts (POSIX sh) | Host, needs `shellcheck` |
| build | `tests/build/` | Built packages: architecture, version, declared dependencies, file list, ownership and permissions, ACL matching the plugin's methods | Host, reads `out/packages/` |
| api | `scripts/smoke-test.sh`; future cases go in `tests/api/` | Calls through `/ubus`: login, ACL enforcement, success and error responses of every `supacudy.*` method | Official OpenWrt rootfs container |
| web-unit | `web/tests/unit/` | `svelte-check` type check, then components, state and utilities; zh-CN and en i18n keys complete and in sync | Node (Vitest + jsdom) |
| web-e2e | `web/tests/e2e/`, run by `scripts/test-e2e.sh` | Every page across the matrix below | Playwright (Chromium) against the api test container |
| emulator | `tests/emulator/` | A fresh QEMU VM of the full system with the emulated network ([docs/emulator.md](../emulator.md)): WAN, LAN clients over DHCP, Wi-Fi association, upstream hotspots visible to the router, UI reachable. Network features (repeater, clients, Wi-Fi, LAN) add their end-to-end checks here | QEMU (HVF on macOS, KVM or TCG on Linux) |
| hardware | Checklists in `docs/hardware/` | Wi-Fi, Ethernet ports, USB, buttons and anything else only testable on a real device | Real TR3000, run manually |

### web-e2e matrix

Every page is covered for at least:

| Dimension | Values |
|---|---|
| Viewport | Desktop 1280×800, mobile 390×844 |
| Theme | Light, dark |
| Language | zh-CN, en |

Each combination checks: no horizontal scrolling, no missing i18n keys shown as raw keys (rendered as `⟦key⟧`), no axe violations for WCAG 2.1 A/AA (which includes color contrast), touch targets of at least 44×44px, and that the page's main action can be completed. `expectPageQuality()` in `web/tests/e2e/helpers.ts` bundles the first three; call it on every new page and dialog.

## Running

- `scripts/test.sh` is the single entry point. It runs lint → web-unit → build-packages → build → api → web-e2e → emulator, prints a summary and exits non-zero if anything fails.
- Full logs for each category are written to `out/test-logs/`.
- When adding a category, wire it into `scripts/test.sh` and update the table above in the same change.
- For changes that can only be verified on a real device, the commit message lists which checklist items were tested.
