# Collaboration and harness rules

These apply to everyone working in this repository, people and AI assistants (Claude Code and others) alike.

## Making a change

1. Read the relevant docs and existing code first, and follow the existing style.
2. Feature code, tests and doc updates go in the same change.
3. Run `scripts/test.sh` locally; commit and push only when everything passes.
4. When a roadmap item is done, tick it in `docs/roadmap.md` in the same change.

## Commits

- Commit messages are in English and follow Conventional Commits: `feat(rpcd): add repeater_scan`, `fix(ui): ...`, `docs: ...`, `test: ...`, `build: ...`.
- One commit does one thing; unrelated formatting or refactoring goes in its own commit.
- Never commit build output (`out/`), secrets, factory-partition backups of real devices, or personal network details.

## Pushing

- **All tests must pass before every push.** The repository ships a pre-push hook that runs `scripts/test.sh`; enable it once per clone:

  ```bash
  git config core.hooksPath .githooks
  ```

- Never bypass the hook with `git push --no-verify`, and never edit the hook or the tests to let a failure through.
- Never force-push to `main`.

## Extra rules for AI assistants

- Report test results truthfully: say what was not run, paste the output of failures, and never present "should pass" as "passed".
- Anything only verifiable on a real device (flashing, Wi-Fi, Ethernet) is explicitly marked "not verified on hardware".
- Ask the user before: flashing a real device, changing network settings on a router, pushing, creating or changing GitHub repository settings, or publishing anything.
- When a requirement is unclear, ask instead of widening the scope. Problems found outside the task are reported to the user, not fixed in passing.
- Follow the [coding rules](coding.md), especially the comment rules.

## Versions

- Package versions follow semantic versioning: new features bump the minor version, fixes bump the patch version. Each completed roadmap phase gets a tag (e.g. `v0.2.0` when phase 1 is done).
- Upgrading the OpenWrt base is its own commit and requires the full test suite plus at least one smoke check on real hardware.
