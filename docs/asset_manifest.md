# Asset Manifest

This manifest records the provenance, processing result, runtime use, and known limitations of the MVP art. Machine-readable frame rectangles, source boxes, pixel hashes, FPS, and fallback records live beside each processed atlas in `assets/processed/`.

## Source assets

All three pipeline inputs were supplied to the project as AI-generated concept images. They are preserved byte-for-byte under `assets/source/generated/` and are not loaded by gameplay.

| Source | Measured image | SHA-256 | Observed content | Pipeline use |
|---|---:|---|---|---|
| `player_animation_source.png` | 1448×1086 RGB | `1f77a8deeae04022a2bff8c91af9829ebb64dfd824d950fcfd56975756ffa7e1` | 4×8 character pose sheet with a checkerboard baked into the RGB pixels | 26 selected poses after border-connected background removal |
| `guard_animation_source.png` | 1536×1024 RGBA | `a66592ebbd84c19901ea150875ad319a8aa0212e68faae4af3f1d3797bf33f78` | 20 alpha-separated guard poses in a 4×5 presentation | 16 selected directional poses after alpha/component cleanup |
| `facility_map_tileset_source.png` | 1536×1024 RGB | `c2bb4c0279e5b5de2bbfecd2d199b7ca0ed747189b3df50609e2963c956d0546` | Mixed map preview, floor samples, perspective walls, props, lighting, and guide material | Explicitly classified crops plus deterministic runtime base tiles |

`assets/concept/player_design_reference.png` is a separate 1536×1024 RGBA player design reference (SHA-256 `48d5fbf6e2646ed1f749a40a4a34c257fad1496d73c5b80a38ce93e957cbe2c1`). It is retained as an unused concept reference and is not an input to `tools/asset_pipeline.py` or a runtime dependency.

No externally authored stock, commercial, font, audio, or shader asset was added by this art pass. AI-source disclosure and remaining provenance information are recorded in `THIRD_PARTY_NOTICES.md`.

## Player derivatives

| Item | Value |
|---|---|
| Processed atlas | `assets/processed/characters/player/player_atlas.png` |
| Runtime atlas | `assets/sprites/characters/player_atlas.png` |
| Manifest | `assets/processed/characters/player/player_frames.json` |
| Review contact sheet | `assets/processed/characters/player/player_preview.png` |
| Godot resource | `resources/characters/player_sprite_frames.tres` |
| Atlas size | 384×256 RGBA |
| Logical frame / pivot | 48×64 / `(24, 62)` bottom center |
| Selected source frames | 26 |
| Horizontal flip | None; usable left and right source rows exist |
| Runtime use | `PlayerVisual` on the live player; shared by Ghost presentation |

| Animation | Frames | FPS / loop | Source or fallback status |
|---|---:|---|---|
| `idle_down` | 2 | 3 / yes | Actual front poses |
| `idle_left` | 2 | 3 / yes | Actual left poses |
| `idle_right` | 2 | 3 / yes | Actual right poses |
| `idle_up` | 2 | 3 / yes | Actual back poses |
| `walk_down` | 2 | 4 / yes | Reuses the two stable front/idle poses; later row poses drift sideways |
| `walk_left` | 6 | 8 / yes | Actual left sequence |
| `walk_right` | 6 | 8 / yes | Actual right sequence |
| `walk_up` | 6 | 8 / yes | Actual back sequence |
| `interact_down` | 1 | 6 / no | Static `idle_down` placeholder |
| `interact_left` | 2 | 6 / no | Late left poses reused as a placeholder |
| `interact_right` | 2 | 6 / no | Late right poses reused as a placeholder |
| `interact_up` | 1 | 6 / no | Static `idle_up` placeholder |

Quality limits: the down walk is visibly subtler than side/up motion; interaction is not a fully authored action; and source body proportions vary slightly. Fixed actor-wide scaling and foot-pivot alignment reduce, but do not invent detail or eliminate every source inconsistency.

## Guard derivatives

| Item | Value |
|---|---|
| Processed atlas | `assets/processed/characters/guard/guard_atlas.png` |
| Runtime atlas | `assets/sprites/characters/guard_atlas.png` |
| Manifest | `assets/processed/characters/guard/guard_frames.json` |
| Review contact sheet | `assets/processed/characters/guard/guard_preview.png` |
| Godot resource | `resources/characters/guard_sprite_frames.tres` |
| Atlas size | 384×128 RGBA |
| Logical frame / pivot | 48×64 / `(24, 62)` bottom center |
| Selected source frames | 16 of 20 detected candidates |
| Horizontal flip | None; directional source poses were selected directly |
| Runtime use | Deterministic tutorial Guard patrol, suspicion, chase, search, and capture presentation |

| Animation group | Frames per direction | FPS / loop | Source or fallback status |
|---|---:|---|---|
| `idle_down/left/right/up` | 1 | 3 / yes | First-row directional poses |
| `walk_down/left/right/up` | 2 | 6 / yes | Two subtle source poses; incomplete walk-cycle placeholder |
| `alert_down/left/right/up` | 2 | 6 / no | Equipment poses used as the clearest available alert cue |

Quality limits: left/right are three-quarter views rather than strict profiles; cap, badge, and equipment placement vary slightly; the source has no complete authored patrol or alert sequence. Equipment direction is presentation-only and is not used as authoritative vision data. Guard perception uses controller-facing vector math and physics LOS, never pixels in the equipment pose.

## Facility derivatives

| Item | Value |
|---|---|
| Processed atlas | `assets/processed/environment/facility_tileset.png` |
| Runtime atlas | `assets/sprites/environment/facility_tileset.png` |
| Manifest | `assets/processed/environment/facility_tileset_manifest.json` |
| Review contact sheet | `assets/processed/environment/facility_tileset_preview.png` |
| Reference-only map crop | `assets/processed/environment/facility_map_reference.png` |
| Godot resource | `resources/tilesets/facility_tileset.tres` |
| Atlas size | 256×128 RGBA |
| Tile size | 32×32 |
| Classified entries | 32 |
| Runtime use | 30×16 tutorial presentation grid; stateful objects remain scenes |

### Classification and use

| Category | Runtime decision |
|---|---|
| `floor` | A deterministic seamless dark base is used across the room. `floor_panel_a`, `floor_panel_b`, and `floor_dark_panel` appear only as sparse detail because source edges do not tile seamlessly. |
| `wall`, `wall_corner` | All AI wall candidates were rejected for perspective/size mismatch. Deterministic project-authored tiles use the source palette. The TileSet stores wall collision metadata. |
| `door` | Source crop is reference-only; the resettable `SecurityDoor` scene owns visuals and collision. |
| `obstacle`, `terminal`, `server`, `crate`, `decoration` | Reviewed source crops are optional presentation props. Tutorial placements are currently non-colliding; some TileSet entries retain collision metadata for a future explicitly collision-enabled authored layer. |
| `pressure_plate`, `objective`, `exit` | Reference classifications only; runtime objects remain stable-ID gameplay scenes with triggers and reset state. |
| `laser`, `light`, `unused_reference` | Not used by the tutorial. Baked lighting and guide material are unsuitable for reusable terrain. |

The left-side finished map preview is never placed behind the level. The runtime `FacilityMap` uses three collision-disabled `TileMapLayer` children so visual tiles cannot create double collision. Existing authored `StaticBody2D` boundaries and the stateful door remain the collision authority; this preserves deterministic movement and reset behavior while the TileSet retains reusable collision definitions for future authored maps.

## Runtime dependency boundary

The generated Godot resources reference only these runtime PNGs:

```text
assets/sprites/characters/player_atlas.png
assets/sprites/characters/guard_atlas.png
assets/sprites/environment/facility_tileset.png
```

Source sheets, concept references, processed atlases, manifests, previews, and the map reference are not gameplay dependencies. `tools/asset_pipeline.py validate` scans `.gd`, `.tscn`, `.tres`, and `project.godot` files and fails if a runtime resource points into `assets/source/`, `assets/processed/`, or `assets/concept/`.
