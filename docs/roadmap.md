# Roadmap

The project is now centered on a stealth heist with limited Recall. The original full-loop puzzle remains a regression tool, not the default product direction.

`AGENTS.md`, `game_design.md`, and `architecture.md` remain the authority over this roadmap.

## Completed foundation — Full-loop prototype

- 20-second deterministic loop and 20 Hz hybrid recording;
- immutable Ghost playback with stable-ID events;
- pressure plate, door, objective, exit;
- Guard patrol/perception/capture and Ghost distraction;
- pause/restart/reset race handling;
- Web/desktop export automation and public repository baseline.

Role now: fast technology, Guard, asset, and reset regression.

## Completed foundation — Facility regression

- separate 26×25, 60-second TileMap mission;
- terminal-controlled laser and plate-controlled vault door;
- Guard distraction route;
- wall collision, light occlusion, and information visibility probe;
- bounded camera and regression acceptance coverage.

Role now: visibility and multi-room full-loop regression.

## Current milestone — Operation: Black Minute

Implemented architecture and content:

- explicit GameMode and menu → briefing → formal mission flow;
- blueprint-driven 64×42 facility with 15 rooms;
- 10 deterministic Guards across 7 bounded response zones;
- 8 CCTV cameras and 3 laser barriers;
- Level 1 / Level 2 / Vault access progression;
- server or biometric Vault authorization;
- acyclic objective graph and Core/extraction lifecycle;
- three-charge, ten-second Chrono Recall with bounded history;
- rewindable value snapshots and maximum three Echoes;
- tactical pause map and heist HUD;
- mission solvability validator;
- deterministic 180-second patrol simulation;
- typed mission-beat feedback and procedural operation audio;
- Recall-persistent performance directives and extraction debrief.

Automated acceptance now covers the complete collision-respecting no-Recall route, bounded Recall/Echo behavior, capture recovery, deterministic patrols, extraction scoring, and responsive debrief bounds. Local-HTTP browser checks cover the 1280×720 reference viewport and a resized 1024×768 viewport. Clean Web export, console review, CI, Pages deployment, and deployed HTTP confirmation remain mandatory per-release checks rather than unfinished gameplay scope.

Remaining manual acceptance work must be reported from actual execution, not inferred:

1. complete the full formal operation with a Recall-assisted Echo-distraction route;
2. repeat capture → Recall and capture → checkpoint with first-time players;
3. profile 10 Guards + 3 Echoes + 8 cameras on representative Web hardware.

## Next milestone — Heist usability hardening

- observe first-time players and tune objective wording/patrol windows;
- add an explicit tutorial-message replay setting;
- improve tactical-map legend and locked-door readability;
- verify fullscreen/mute presentation in every GameMode and browser environment;
- audit repeated Recall/checkpoint cycles for orphan nodes and stale signals;
- capture verified screenshots/GIF after browser visual acceptance.

## Completed decision gate — Score and optional directives

The selected deeper-heist choice is session-only mission performance. It adds positive-only `SHADOW`, temporal-style, `UNTOUCHABLE`, and `BLACKOUT` directives without a leaderboard, grind, or time-pressure score. Both no-Recall and useful-Echo mastery remain first-class.

The unselected candidates remain deferred:

- one additional mission with a different security order;
- one non-combat gadget that deepens route planning;
- one additional deterministic security device;

Do not build all deferred candidates at once. Any future choice must preserve no-Recall solvability, stable IDs, bounded Recall history, and fast restart.

## Deferred infrastructure

- persistent mission/campaign save and schema migration;
- controller rebinding and touch input;
- localization pipeline beyond current labels;
- signed/notarized desktop release;
- generalized navigation for arbitrary generated layouts.

## Explicitly out of scope

- multiplayer, accounts, online services, leaderboards, analytics;
- procedural generation or user-generated content;
- combat, weapons, health, bosses, reinforcement AI;
- skill trees, shops, inventory grids, meta progression;
- hearing/noise simulation, cover, crouch;
- ads, microtransactions, paid-asset dependencies.
