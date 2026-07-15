# Asset Manifest

This manifest records the provenance, processing result, runtime use, and known limitations of the MVP art. Machine-readable frame rectangles, source boxes, pixel hashes, FPS, and fallback records live beside each processed atlas in `assets/processed/`.

## Source assets

All three art-pipeline inputs and the separate map blueprint reference were supplied to the project as AI-generated images. They are preserved byte-for-byte under `assets/source/generated/` and are not loaded by gameplay.

| Source | Measured image | SHA-256 | Observed content | Pipeline use |
|---|---:|---|---|---|
| `player_animation_source.png` | 1448×1086 RGB | `1f77a8deeae04022a2bff8c91af9829ebb64dfd824d950fcfd56975756ffa7e1` | 4×8 character pose sheet with a checkerboard baked into the RGB pixels | 26 selected poses after border-connected background removal |
| `guard_animation_source.png` | 1536×1024 RGBA | `a66592ebbd84c19901ea150875ad319a8aa0212e68faae4af3f1d3797bf33f78` | 20 alpha-separated guard poses in a 4×5 presentation | 16 selected directional poses after alpha/component cleanup |
| `facility_map_tileset_source.png` | 1536×1024 RGB | `c2bb4c0279e5b5de2bbfecd2d199b7ca0ed747189b3df50609e2963c956d0546` | Mixed map preview, floor samples, perspective walls, props, lighting, and guide material | Explicitly classified crops plus deterministic runtime base tiles |
| `facility_map_reference.png` | 824×807 RGBA | `64cedbee9b003678b4ffbf80e77c9918080cab62fb9c62f7ff7204ae38498cc5` | Top-down facility blueprint with control rooms, corridors, laser room, courtyard, props, lighting, and example characters | Source-only topology/art reference for the authored 26×25 facility; never copied to a runtime texture |

`assets/concept/player_design_reference.png` is a separate 1536×1024 RGBA player design reference (SHA-256 `48d5fbf6e2646ed1f749a40a4a34c257fad1496d73c5b80a38ce93e957cbe2c1`). It is retained as an unused concept reference and is not an input to `tools/asset_pipeline.py` or a runtime dependency.

`assets/source/environment/helix_environment_concept_v1.png` is a 1536×1024 RGB direction board generated for this project (SHA-256 `b66dabd4a5ea38373b6d1f6cfa9e8ec9d03bcf25ee31a608c689d05e48239c93`). It establishes HELIX material and room-identity targets but is not sampled, cropped, or loaded by gameplay. Deterministic pixel assets are generated from the reviewed JSON specification instead.

That character/environment art pass added no external stock or commercial art, audio, font, or shader. The later Operation briefing adds one open-source Noto Sans KR subset; its provenance and SIL OFL 1.1 terms are recorded below and in `THIRD_PARTY_NOTICES.md`.

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
| Runtime use | Preserved 30×16 prototype presentation and separate 26×25 facility TileMap; stateful objects remain scenes |

### Classification and use

| Category | Runtime decision |
|---|---|
| `floor` | A deterministic seamless dark base is used across the room. `floor_panel_a`, `floor_panel_b`, and `floor_dark_panel` appear only as sparse detail because source edges do not tile seamlessly. |
| `wall`, `wall_corner` | All AI wall candidates were rejected for perspective/size mismatch. Deterministic project-authored tiles use the source palette. Approved solid tiles store full-cell physics and light-occlusion polygons. |
| `door` | Source crop is reference-only; the resettable `SecurityDoor` scene owns visuals and collision. |
| `obstacle`, `terminal`, `server`, `crate`, `decoration` | Reviewed source crops are optional presentation props. Tutorial placements are currently non-colliding; some TileSet entries retain collision metadata for a future explicitly collision-enabled authored layer. |
| `pressure_plate`, `objective`, `exit` | Reference classifications only; runtime objects remain stable-ID gameplay scenes with triggers and reset state. |
| `laser`, `light`, `unused_reference` | Source crops remain reference-only. Facility laser behavior is an independent resettable scene, and facility illumination uses Godot `CanvasModulate`/`PointLight2D` rather than baked source lighting. |

Neither the processed preview nor the 824×807 blueprint reference is placed behind a level. `FacilityLevelMap` rebuilds the facility from deterministic rooms/connectors across six `TileMapLayer` children. Only `Walls` enables collision and light occlusion; floor, detail, and prop layers explicitly disable both. The TileSet's approved wall tiles use physics collision layer `65` (`World | PlayerVisionBlocker`) and light-occlusion mask `1`. The stateful door, pressure plate, terminal, laser, objective, and exit remain independent scenes.

The facility blueprint describes `26×25` logical cells at `32×32 px` (`832×800 px` world bounds). Runtime topology and object coordinates are documented in `docs/maps/facility_level_01_layout.md`. Wall/light/information visibility is documented in `docs/visibility_system.md`.

## Authored Operation environment derivatives

| Item | Value |
|---|---|
| Specification | `assets/source/environment/facility_environment_spec.json` |
| Direction reference | `assets/source/environment/helix_environment_concept_v1.png` |
| Processed atlas | `assets/processed/environment/authored/facility_environment_atlas.png` |
| Runtime atlas | `assets/sprites/environment/facility_environment_atlas.png` |
| Manifest | `assets/processed/environment/authored/facility_environment_manifest.json` |
| Review contact sheet | `assets/processed/environment/authored/facility_environment_preview.png` |
| Palette preview | `assets/processed/environment/authored/facility_palette_preview.png` |
| Godot resource | `resources/tilesets/facility_environment_art.tres` |
| Generated runtime catalog | `resources/environment/facility_environment_catalog.gd` |
| Atlas / tile size | 512×448 RGBA / 32×32 |
| Named cells | 182 |
| Runtime collision / occlusion | 0 / 0; visual-only |
| Runtime use | `OperationBlackMinuteMap` floor/detail/wall/solid layers plus `OperationEnvironmentPresenter` heroes, state motion, and painted practical pools |

The atlas defines seven room material families, deterministic floor variants,
sparse overlays, 16 neighbor masks with two wall variants, 33 reusable
multi-cell furniture segments, a nine-cell Chronos Vault circuit, 15 room
signatures, 30 hero segments, 30 animation cells, five state cells, and a
deep-wall pair. Every blueprint room has a validated profile. Every one of the
16 `internal_solid_rects` maps to an explicit motif covering 64 already-solid
cells. No visual placement creates new collision.

The original `Walls` TileMap remains present, collision-enabled, occlusion-enabled, and visually transparent. `WallArt` supplies the visible reinforced panels without becoming gameplay geometry. Dynamic doors and mission objects remain independent scenes.

## Bilingual UI font

The Operation: Black Minute briefing uses `assets/fonts/noto_sans_kr_ui_subset.ttf`, a 70 KB weight-500 subset of Noto Sans KR containing printable ASCII plus the Korean mission-identity glyphs used by that screen. This is a runtime dependency, not an AI-generated asset. Its source revision, hashes, copyright, and SIL OFL 1.1 license are recorded in `THIRD_PARTY_NOTICES.md`; the license text is stored at `assets/fonts/OFL-NotoSansKR.txt`.

## Runtime dependency boundary

The generated Godot resources and bilingual briefing reference only these committed runtime assets:

```text
assets/sprites/characters/player_atlas.png
assets/sprites/characters/guard_atlas.png
assets/sprites/environment/facility_tileset.png
assets/sprites/environment/facility_environment_atlas.png
assets/fonts/noto_sans_kr_ui_subset.ttf
```

Source sheets, concept references, processed atlases, manifests, previews, and
both map references are not gameplay dependencies. `tools/asset_pipeline.py
validate` scans runtime text resources and rejects references into source,
processed, or concept directories. `tools/environment_art_pipeline.py validate`
additionally verifies every room profile and semantic solid, exact generated
pixels, 182 unique registered tiles, RGBA/alpha/grid integrity, transparent
unused cells, source concept hash, runtime/processed equality, generated
catalog equality, and zero physics/occlusion in the art TileSet.
