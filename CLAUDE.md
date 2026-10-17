# SupaCudy

Firmware for the Cudy TR3000 built on official OpenWrt, with a mobile-first web UI. See [docs/architecture.md](docs/architecture.md) for the architecture and [docs/development.md](docs/development.md) for the development workflow.

## Hard rules

1. Every requirement ships with thorough test cases, filed by category.
2. All tests must pass before every push (`scripts/test.sh`; the pre-push hook runs it).
3. The web UI must work well on both desktop and mobile.
4. Only Simplified Chinese and English are supported; light and dark mode are both required.
5. Code comments are in English, short and useful. No comments that restate the code or describe what a function or variable is.

The detailed rules are split by category below; all of them apply:

- Product rules: @docs/rules/product.md
- Coding rules: @docs/rules/coding.md
- Testing rules: @docs/rules/testing.md
- Collaboration and harness rules: @docs/rules/workflow.md

## Common commands

```bash
scripts/test.sh                         # all automated tests (required before push)
scripts/build-packages.sh               # build the .ipk packages
scripts/build-image.sh cudy-tr3000-256mb-v1  # build a firmware image (256MB TR3000 only)
scripts/smoke-test.sh --keep            # run in a container, open http://localhost:8080/supacudy/
npm --prefix web run dev                # front-end dev server, proxies /ubus to that container
scripts/test-e2e.sh                     # only the Playwright tests
scripts/emulator.sh start               # full system in QEMU with emulated Wi-Fi and clients, http://127.0.0.1:8088/supacudy/
scripts/deploy-dev.sh root@192.168.1.1  # push files to a real router for debugging
```
