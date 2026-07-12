## What changed

<!-- Describe the smallest coherent change. -->

## Why

<!-- Explain the player/developer problem and why this approach fits the MVP. -->

## Related issue

Closes #

## Test results

<!-- List exact commands and PASS/FAIL/NOT RUN. Do not claim checks you did not run. -->

```text
PASS/FAIL/NOT RUN: Godot import
PASS/FAIL/NOT RUN: Headless project boot
PASS/FAIL/NOT RUN: Automated tests
PASS/FAIL/NOT RUN: Web export
PASS/FAIL/NOT RUN: Local HTTP browser smoke test
```

## Screenshot or video

<!-- Required for visible gameplay/UI changes; otherwise write "Not applicable." -->

## Checklist

- [ ] I read `AGENTS.md`, `docs/architecture.md`, and `docs/game_design.md`.
- [ ] The change stays within the requested scope and preserves responsibility boundaries.
- [ ] Gameplay input uses Input Map actions, not hard-coded physical keys.
- [ ] Recordings contain stable object IDs and data, not node paths or permanent `Node` references.
- [ ] Reset behavior is explicit and deterministic.
- [ ] Pause, restart, timeout, and victory races were considered.
- [ ] New or changed public behavior is documented.
- [ ] New external assets have verified redistribution terms and a `THIRD_PARTY_NOTICES.md` entry.
- [ ] Generated builds, caches, logs, secrets, and signing material are not included.
- [ ] I reported every validation I could not run.
