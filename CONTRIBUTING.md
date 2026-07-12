# Contributing

Thank you for helping improve **Sixty-Second Accomplice**. The current priority is a small, deterministic, browser-playable MVP. Changes should strengthen that experience before expanding its scope.

## Development setup

1. Install the standard GDScript build of Godot Engine 4.7 stable and its matching export templates.
2. Fork and clone the repository.
3. Create a focused branch from the latest `main`.
4. Import and open the project:

   ```bash
   godot --headless --path . --import
   godot --editor --path .
   ```

If your executable is `godot4`, use that name instead.

## Before changing code

Read these sources of truth in order:

1. `AGENTS.md`
2. `docs/architecture.md`
3. `docs/game_design.md`

Preserve the hybrid replay design, stable object IDs, explicit loop reset contract, typed GDScript, and Input Map actions. Do not record node paths or permanent `Node` references in a recording. Do not add a global event bus or unrelated abstraction for hypothetical future features.

Discuss large features in an issue before implementation. Multiplayer, accounts, leaderboards, procedural generation, complex combat, meta progression, mobile controls, analytics, and monetization are outside the MVP.

## Branches and commits

- Branch from `main` and keep each branch focused on one concern.
- Use short, imperative commit messages; Conventional Commit prefixes such as `feat:`, `fix:`, `test:`, `ci:`, and `docs:` are encouraged.
- Do not rewrite shared history or force-push an active review branch.
- Do not commit `.godot/`, exported builds, logs, credentials, signing material, or editor-specific files.
- Preserve unrelated work already present in the branch.

## Tests and validation

Run the checks relevant to your change before opening a pull request:

```bash
godot --headless --path . --import
godot --headless --path . --quit
GODOT_BIN=godot tools/run_tests.sh
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
```

For gameplay changes, also play the acceptance path manually:

1. Record the live player moving onto the pressure plate.
2. Start a second loop and verify that the Ghost repeats the route.
3. Cross the open door while the Ghost holds the plate.
4. Collect the objective and reach the exit.
5. Repeat after pause, manual restart, and natural timeout.

Never hide a failing test by skipping it. If a check cannot be run locally, state that explicitly in the pull request.

## Issues

Search existing issues first. Use the provided Bug report or Feature request form and include the smallest reproducible scope. Security-sensitive reports and private conduct reports must not be filed as public issues.

## Pull requests

A reviewable pull request should:

- explain what changed and why;
- link the relevant issue when one exists;
- list the exact validation commands and results;
- include a screenshot or short video for visible gameplay/UI changes;
- keep scene, script, and data responsibilities separated;
- document any new stable object IDs, Input Map actions, or required scene nodes;
- update public documentation when behavior or release commands change;
- avoid unrelated formatting or generated build artifacts.

Reviewers will prioritize deterministic replay, safe reset ordering, Web compatibility, accessibility, and clarity for a first-time player.

## Asset licensing

Prefer Godot primitives and original project assets. Before adding any external asset:

1. Verify that commercial use, modification, redistribution, and repository distribution are allowed.
2. Preserve the source URL, author, exact license, and required attribution.
3. Add the notice to `THIRD_PARTY_NOTICES.md` in the same pull request.
4. Do not add an asset if its license is missing or unclear.

Avoid unnecessary font binaries and paid-asset dependencies. Keep source assets when they are required to reproduce an export.

## Community conduct

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
