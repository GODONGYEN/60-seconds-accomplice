# Art Direction

This document defines the visual rules for the playable MVP. It is subordinate to `AGENTS.md`, the gameplay requirements in `docs/game_design.md`, and the system boundaries in `docs/architecture.md`.

## Readability goal

The player should understand the time-loop puzzle from the playfield without relying on decoration or color alone. The live player, Ghosts, pressure plate, door, objective, and exit take visual priority over the room dressing. Decorative detail must not hide a walkable boundary or imply collision where none exists.

The reference viewport is 1280×720. The tutorial uses a compact 32 px grid so the player and roughly 8–12 nearby tiles remain readable at the default view.

## Visual hierarchy

| Role | Primary treatment | Secondary cue |
|---|---|---|
| Live player | Bright, opaque cyan accents on a dark silhouette | Solid shadow and full-strength animation |
| Ghost | Player silhouette and animation, blue/cyan modulation at reduced opacity | `GHOST` loop label; no player collision |
| Guard / alert | Dark navy uniform with orange or yellow equipment | Alert indicator or state animation |
| Locked / failure | Red | Text, closed shape, or blocked silhouette |
| Objective | Violet or bright cyan | Pulse and objective text/icon |
| Active exit | Green/cyan | Open shape and explicit exit label |
| Neutral environment | Dark navy, charcoal, and cool gray | Floor/wall value separation |

Critical states always combine color with text, shape, opacity, or motion. Flashing is kept minimal, screen shake is weak or absent, and all puzzle labels must remain legible when audio is muted.

## Pixel and scale contract

- Environment tile: 32×32 logical pixels.
- Player and guard frame: 48×64 logical pixels.
- Character pivot: bottom center at `(24, 62)`.
- Character content: no more than 46×60 pixels, leaving transparent edge padding.
- Resampling: nearest-neighbor only.
- Texture filtering: nearest; mipmaps and repeat disabled for pixel-art atlases.
- Character collision: lower body/feet, not the full hood or head silhouette.

The 48×64 character frame is deliberate. A 32×48 reduction erased the cyan visor, equipment, and guard badge more aggressively, while 64×64 made the actors too wide for a 32 px corridor. A single actor-wide scale is used within each atlas, and every pose is aligned by the foot center to prevent apparent size changes between frames.

Subpixel gameplay motion remains independent of sprite pixels. Presentation should not quantize the deterministic player or Ghost path merely to make a sprite land on whole pixels. Texture filtering and consistent pivots are preferred over changing the simulation.

## Character language

### Player

The player is a short, compact infiltrator with a dark hood and tactical suit, a bright cyan visor, cyan equipment accents, and a small backpack. The visor and hood form the primary recognition shape. Direction changes must preserve the apparent body scale and keep the feet anchored.

The generated source does not contain a complete authored set. Downward walking and interaction poses use documented fallbacks; they must not be presented as newly illustrated animation. See `docs/asset_manifest.md` for the exact frame mappings.

### Ghost

Ghosts share the player `SpriteFrames`; they do not have a separate atlas. Use blue/cyan modulation and approximately 45–60% opacity, with lower saturation or brightness than the live player. A small loop label provides a non-color cue. Ghost presentation follows recorded facing, movement, and interaction state, but never changes replay physics or timing.

### Guard

The guard uses dark navy/gray, an orange or yellow badge/equipment accent, and a cap to separate its silhouette from the hooded player. Directional equipment is a presentation hint only and is not authoritative vision data. The source provides three-quarter side views and only subtle pose changes, so the patrol and alert cycles remain prototype placeholders.

The gameplay vision cone is a low-alpha cyan shape during patrol, orange with a `?` during suspicion/search, and red with a `!` during chase. Physics line-of-sight remains authoritative when a wall or closed door overlaps the un-clipped presentation cone. The per-Guard meter and HUD text make suspicion readable without color or audio.

## Facility language

The formal heist environment follows `docs/environment_art_bible.md`, which is the source of truth for its canonical palette, material ramps, lighting constraints, dressing density, and room identity. The rules below remain the common minimum for preserved prototype/facility modes.

The tutorial room is a dark science-fiction security facility:

- Floors are low-contrast dark panels.
- Walls are brighter and heavier than floors, with a continuous collision boundary.
- Cyan and violet gameplay objects sit in visually quiet areas.
- Orange is reserved for guard/danger emphasis.
- Small props do not block movement unless their collision is clearly visible.

The AI facility image is a concept sheet, not a production TileSet. Its left-side map preview, perspective wall pieces, baked lighting examples, and non-seamless floor variations are reference-only. Preserved regression maps use deterministic project-authored derivatives. Operation: Black Minute uses a second deterministic HELIX atlas with seven floor families, walkable-neighbor wall masks, semantic furniture aligned to existing blueprint solids, and a vault signature circuit. Door, pressure plate, objective, exit, access card, terminal, camera, and laser remain stateful scenes rather than baked map tiles.

## UI integration

UI panels use dark navy or charcoal with high-contrast text. Time and Ghost information use cyan; warnings use orange/red; the active exit uses green/cyan. Text remains the authoritative cue for remaining time, loop number, objective, pause, and victory state. Decorative borders may echo facility panels but must not reduce label contrast or responsive layout space.

## Source and licensing rule

The three generated source sheets and the HELIX environment direction board are project-supplied or project-generated AI concept inputs retained for reproducibility. They are never referenced directly by gameplay. Derivative atlases, metadata, and previews are produced by `tools/asset_pipeline.py` and `tools/environment_art_pipeline.py`; runtime resources reference only `assets/sprites/`.

No externally sourced commercial art, audio, font, or shader is used by this pipeline. Any future third-party asset must be license-reviewed and entered in `THIRD_PARTY_NOTICES.md` before it can be committed or shipped.
