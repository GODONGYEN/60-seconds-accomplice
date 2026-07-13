# Roadmap

This roadmap keeps **Sixty-Second Accomplice** focused on one question: is it satisfying to cooperate with a previous version of yourself? The regression prototype uses 20 seconds; the larger facility mission uses the title's 60-second loop.

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

## Milestone 3 — Facility map and wall visibility

Goal: prove the same loop in a compact multi-room mission where walls hide both rendered space and gameplay information.

Implementation scope:

- Separate `26×25` facility scene at `32 px` per tile; the 20-second prototype remains available for regression
- 60-second level-local duration and bounded `832×800 px` Player camera
- One center-corridor Guard with four deterministic patrol points
- Lower-left pressure plate controlling the upper-left vault door
- Right-room terminal disabling a resettable laser Player trigger
- Objective in the upper-left control room and exit in the lower-right courtyard
- `CanvasModulate`, one Player `PointLight2D`, TileSet wall occlusion, and a dynamic door occluder
- Physics-ray `PlayerVisibilityProbe` plus cached alpha/HUD/prompt gating for Guard, Ghost, and stateful objects
- Source-only `824×807` map reference; no giant runtime background texture

Exit criteria:

1. Topology, collision, portal coordinates, per-level timing, reset, and prototype regression tests pass.
2. A two-loop route demonstrates Ghost distraction and plate occupancy while the current Player uses the terminal/laser route.
3. Closed/open door movement, Guard LOS, Player visibility, and rendered occlusion remain synchronized.
4. Web screenshots show no Guard/Ghost/indicator leak behind walls at `1280×720` and a resized viewport.
5. Web export, local HTTP smoke, browser console, CI, and Pages deployment are independently verified; none is inferred from headless tests.

## Milestone 4 — MVP hardening

Continue after the core loop and stealth acceptance pass consistently.

- Test low frame rates and long frame stalls against replay event ordering
- Test browser focus loss, resize, fullscreen transitions, and audio mute
- Improve first-loop onboarding based on observed player confusion
- Add small readability and feedback improvements without obscuring state
- Profile the eight-Ghost cap on representative Web hardware
- Capture a compact gameplay GIF and verified release screenshots
- Exercise release workflows from a clean public checkout

## Milestone 5 — Vertical-slice decision

This is a decision gate, not a promise of features. Use playtest evidence to choose one narrow extension that deepens time-loop cooperation. Candidate work may include a second deterministic puzzle pattern or a single simple hazard. Any extension must preserve stable replay and fast retries.

## Explicitly out of scope for the MVP

- Multiplayer, accounts, online services, leaderboards, or analytics
- Procedural generation or a campaign
- Additional enemy types, combat AI, bosses, weapon systems, or skill trees
- Meta progression, shops, inventory grids, or save migration
- Mobile touch controls, mod loading, or user-generated content
- Paid assets, ads, or microtransactions

These systems should not receive speculative abstractions before the core loop is validated.
