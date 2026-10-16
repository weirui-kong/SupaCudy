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
| web-unit | `tests/web/unit/` (enabled once the front-end exists) | Components, state and utilities; zh-CN and en i18n keys complete and in sync | Node (Vitest) |
| web-e2e | `tests/web/e2e/` (enabled once the front-end exists) | Every page across the matrix below | Playwright against the api test container |
| hardware | Checklists in `docs/hardware/` | Wi-Fi, Ethernet ports, USB, buttons and anything else only testable on a real device | Real TR3000, run manually |

### web-e2e matrix

Every page is covered for at least:

| Dimension | Values |
|---|---|
| Viewport | Desktop 1280×800, mobile 390×844 |
| Theme | Light, dark |
| Language | zh-CN, en |

Each combination checks: no horizontal scrolling, no missing i18n keys shown as raw keys, and the page's main action can be completed.

## Running

- `scripts/test.sh` is the single entry point. It runs lint → build-packages → build → api → web-unit → web-e2e, prints a summary and exits non-zero if anything fails.
- Full logs for each category are written to `out/test-logs/`.
- When adding a category, wire it into `scripts/test.sh` and update the table above in the same change.
- For changes that can only be verified on a real device, the commit message lists which checklist items were tested.
