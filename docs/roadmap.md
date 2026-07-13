# Roadmap

This roadmap keeps **Sixty-Second Accomplice** focused on one question: is it satisfying to cooperate with a previous 20-second version of yourself?

The source-of-truth gameplay and technical constraints remain `game_design.md`, `architecture.md`, and `AGENTS.md`. A roadmap item does not override those documents.

## Milestone 1 — Browser-playable MVP

Goal: a first-time player can open one link and complete the tutorial room in two or more timelines.

- Godot 4.7 stable project using the Compatibility renderer
- Responsive 1280×720 top-down presentation
- Input Map-driven keyboard/mouse controls
- 20-second timeline and 20 Hz transform recording
- Timestamped interaction events with stable object IDs
- Frame-rate-independent Ghost interpolation
- Deterministic player, object, UI, and playback reset
- Pressure plate, linked door, objective, and exit puzzle
- Contextual onboarding, pause, restart, fullscreen, and mute controls
- Headless data/integration test harness
- Web export with top-level `index.html`
- CI, GitHub Pages deployment, and unsigned desktop release automation
- Public repository documentation and licensing

Exit criteria:

1. The first loop records the player holding the plate.
2. The second loop spawns a Ghost from that immutable recording.
3. The Ghost activates the plate while the live player crosses the door.
4. The live player collects the objective and reaches the exit.
5. Pause, restart, timeout, and victory do not race or leak mutable state.
6. Headless tests and a local HTTP Web smoke test pass without fatal errors.

## Milestone 2 — Deterministic stealth Guard

Goal: turn a failed approach into a useful Guard distraction without adding combat.

Current implementation scope:

- One collision-aware Guard following an authored two-point upper-corridor route on the starting side
- Explicit idle, patrol, suspicious, chase, search, and return states
- Distance, view-angle, wall, and closed-door line-of-sight checks
- Delta-based suspicion gain/loss and capture hold timing
- Deterministic target priority: live Player before active Ghost recordings
- Capture finalizes the current recording and starts the next loop
- Full Guard reset between loops, with a short perception grace period
- Vision cone, `?`/`!` indicators, HUD suspicion meter, and capture feedback
- Upper-corridor Ghost lure paired with a lower-vault live-player objective route

Acceptance criteria:

1. The Guard patrols and changes animation in the direction of travel.
2. Walls and a closed door block detection; the open door permits it.
3. A caught run is retained and appears as a Ghost on the next timeline.
4. The Guard follows the upper-corridor Ghost while the live player can cross into the lower vault lane.
5. Losing a target leads through search and return instead of nondeterministic wandering.
6. Pause, victory, restart, timeout, and capture preserve one deterministic loop outcome.

This milestone deliberately excludes health, weapons, damage, hearing, reinforcements, and general-purpose enemy navigation.

## Milestone 3 — MVP hardening

Continue after the core loop and stealth acceptance pass consistently.

- Test low frame rates and long frame stalls against replay event ordering
- Test browser focus loss, resize, fullscreen transitions, and audio mute
- Improve first-loop onboarding based on observed player confusion
- Add small readability and feedback improvements without obscuring state
- Profile the eight-Ghost cap on representative Web hardware
- Capture a compact gameplay GIF and verified release screenshots
- Exercise release workflows from a clean public checkout

## Milestone 4 — Vertical-slice decision

This is a decision gate, not a promise of features. Use playtest evidence to choose one narrow extension that deepens time-loop cooperation. Candidate work may include a second deterministic puzzle pattern or a single simple hazard. Any extension must preserve stable replay and fast retries.

## Explicitly out of scope for the MVP

- Multiplayer, accounts, online services, leaderboards, or analytics
- Procedural generation or a campaign
- Additional enemy types, combat AI, bosses, weapon systems, or skill trees
- Meta progression, shops, inventory grids, or save migration
- Mobile touch controls, mod loading, or user-generated content
- Paid assets, ads, or microtransactions

These systems should not receive speculative abstractions before the core loop is validated.
