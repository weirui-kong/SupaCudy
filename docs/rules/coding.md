# Coding rules

## Comments

- **Comments are always in English.**
- **Only write what the code cannot say itself**: why it is done this way, non-obvious constraints, the reason for an upstream workaround, protocol or format conventions.
- **Not allowed**:
  - Comments describing what a function or variable is or does, e.g. `// Parse the release file`, `# Output directory`. A good name makes them unnecessary.
  - Comments restating the next line, e.g. `// increment counter`.
  - Repetitive or wordy comments; explain each thing in one place only.
  - Commented-out code. Delete unused code; git keeps the history.
- Keep it short: if one line is enough, do not write a paragraph.
- Every source file starts with the license header (`SPDX-License-Identifier: Apache-2.0`).

## General

- Names must explain themselves; prefer long over vague. Only use common abbreviations (`wan`, `ssid`, `acl`).
- A function does one thing; if it no longer fits on a screen, consider splitting it.
- No leftover debug output. Do not commit TODOs; put planned work in `docs/roadmap.md` or an issue.
- Indentation follows `.editorconfig`: tabs under `packages/`, 2 spaces elsewhere.

## Shell

- Host scripts (`scripts/`, `tests/`) use bash and start with `set -euo pipefail`.
- Scripts that run on the router (`packages/*/files/`) use only POSIX sh supported by BusyBox ash, no bash features.
- Always quote variables. Create temporary files with `mktemp` and clean them up in a `trap`.
- Scripts must pass `shellcheck`; any ignored warning states why, inline.

## ucode (rpcd plugin)

- Start files with `'use strict';`.
- Method names are lower_snake_case and live under the `supacudy` object. Every new method is added to `acl.d/supacudy.json` in the same change: reads under `read`, anything that changes configuration under `write`.
- Validate the type and range of every argument. Invalid input returns a ubus error status instead of throwing.
- Read and write configuration only through the `uci` module, never by editing `/etc/config/*` directly.
- **Never build shell commands by string concatenation.** When running an external program, no argument may contain unvalidated user input.
- Apply configuration changes with `reload`; only `restart` a service when reload is not enough.

## OpenWrt packages

- Package names start with `supacudy-` and use `PKGARCH:=all`.
- Any change that ends up in an `.ipk` bumps `PKG_VERSION` or `PKG_RELEASE`.
- Declare every dependency in `DEPENDS`; never rely on a package that happens to be in the image.
- A new dependency needs a stated reason and a check that the image still fits the 256MB TR3000 (the only supported model).

## Front-end

- Svelte + TypeScript, with zero type errors.
- All text goes through i18n; components contain no literal Chinese or English text.
- Colors, spacing, radii and font sizes come only from CSS-variable design tokens; no hard-coded color values.
- Mobile-first CSS: write the phone styles first, then adapt to wider screens with `min-width` media queries.
- Size budget: the built output is at most 300KB gzipped in total; going over needs a stated reason.
- All API calls go through one wrapper module; components never build JSON-RPC requests themselves.

## Security

- Passwords, keys and session IDs never appear in logs, error messages or URLs.
- The front-end never stores the session in `localStorage`; use `sessionStorage` or memory only.
- ACLs follow least privilege: only expose methods the front-end actually calls.
