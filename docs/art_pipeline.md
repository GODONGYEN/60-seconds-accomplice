# Asset Pipeline

`tools/asset_pipeline.py` converts the immutable AI-generated concept sheets into deterministic Godot-ready derivatives. Gameplay resources must reference only the atlases in `assets/sprites/`; `assets/source/` and `assets/processed/` are pipeline inputs, metadata, and review outputs.

## Inputs and outputs

```text
assets/source/generated/              immutable source sheets
assets/processed/characters/          review atlases, JSON manifests, previews
assets/processed/environment/         classified TileSet derivative and references
assets/sprites/                       runtime PNGs referenced by Godot
resources/characters/                 generated SpriteFrames resources
resources/tilesets/                   generated TileSet resource
```

The tool verifies the committed SHA-256 digest of each configured pipeline input before processing. This makes an accidental pipeline-input edit fail loudly instead of silently changing every derivative. The separate facility map reference is source-only and is not a `process-all` input. Do not crop, paint over, or resave a file in `assets/source/generated/`.

## Tool setup

The pipeline uses Python, Pillow, and NumPy. Versions are pinned in `requirements-tools.txt` and are build-time dependencies only.

```bash
python3 -m venv .tools/venv
.tools/venv/bin/python -m pip install --requirement requirements-tools.txt
```

On Windows, use `.tools\venv\Scripts\python.exe` in place of `.tools/venv/bin/python`.

## Commands

Run commands from the repository root:

```bash
.tools/venv/bin/python tools/asset_pipeline.py inspect
.tools/venv/bin/python tools/asset_pipeline.py process-player
.tools/venv/bin/python tools/asset_pipeline.py process-guard
.tools/venv/bin/python tools/asset_pipeline.py process-tileset
.tools/venv/bin/python tools/asset_pipeline.py process-all
.tools/venv/bin/python tools/asset_pipeline.py validate
.tools/venv/bin/python tools/asset_pipeline.py fingerprint
```

| Command | Effect |
|---|---|
| `inspect` | Prints source dimensions, color modes, alpha statistics, dominant colors, detected layouts, and candidate boxes as JSON. It does not rewrite assets. |
| `process-player` | Extracts and normalizes player poses, then writes the atlas, manifest, preview, runtime copy, and `SpriteFrames`. |
| `process-guard` | Extracts the 20 alpha-separated guard candidates, selects directional poses, and writes the equivalent guard outputs. |
| `process-tileset` | Classifies facility crops, writes the derivative atlas and manifest, preserves the map crop as reference-only, and generates the `TileSet`. |
| `process-all` | Regenerates every derivative and resource, then runs `validate`. |
| `validate` | Checks committed source hashes, images, metadata, resources, and runtime-reference boundaries without rewriting outputs. |
| `fingerprint` | Prints platform-neutral hashes of decoded PNG pixels, canonical JSON, and normalized resource text so CI can compare outputs before and after regeneration. |

`process-all` is the canonical clean-checkout command. The generated JSON and `.tres` files should not be hand-edited; change source mappings or generation rules in the tool and regenerate them together.

## Player extraction

The 1448×1086 player sheet is RGB and has a light checkerboard baked into its pixels. It is divided into the observed 4×8 candidate layout, then each candidate is processed independently:

1. Detect near-neutral bright checker colors.
2. Flood-fill only background candidates connected to the crop border.
3. Clear two exposed neutral fringe passes while preserving enclosed highlights.
4. Keep the largest significant foreground component.
5. Crop to the real alpha bounds.
6. Apply one fixed actor-wide scale with nearest-neighbor resampling.
7. Align the detected foot center to the `(24, 62)` pivot in a 48×64 RGBA canvas.

This is not a global white color key. Enclosed visor highlights and bright equipment pixels remain because border connectivity, not whiteness alone, determines removal. The manifest records the method and every selected source bounding box.

The atlas selects 26 actual source poses. The available front row has only two stable poses, so `walk_down` reuses them at 4 FPS. Down/up interactions are static fallbacks; side interactions reuse the last available side poses. No horizontal flips are currently required because usable left and right source rows exist.

`player_preview.png` includes the twelve runtime animation thumbnails and all 32 detected source candidates. Cyan borders mark selected candidates; orange borders identify poses retained for review but excluded from the runtime atlas.

## Guard extraction

The 1536×1024 guard sheet is RGBA and contains 20 foreground components in a 4×5 presentation. Source alpha is treated as authoritative:

1. Detect components at alpha 16 or greater.
2. Require exactly 20 significant components.
3. Group them into four rows and five columns by position.
4. Zero hidden transparent RGB and discard unrelated components.
5. Select the down, left, right, and up columns used by the animation map.
6. Normalize with nearest-neighbor scaling and the same 48×64 canvas/pivot contract as the player.

The resulting atlas contains 16 selected source poses. Idle uses one pose per direction; walk uses two subtle poses; alert uses two equipment poses. These are explicit prototype fallbacks, not a claim that the source contains complete patrol or alert animation. No horizontal flips are currently used.

`guard_preview.png` includes the runtime animation thumbnails plus all 20 detected source candidates with the same selected/review-only border language.

## Facility classification

The 1536×1024 facility input is an RGB concept sheet that mixes a finished map preview, floor samples, perspective wall pieces, doors, props, lighting examples, and guide material. The tool uses explicit reviewed crop boxes rather than treating the sheet as a uniform atlas.

The derivative has a 32×32 logical tile grid:

- `floor_panel_a`, `floor_panel_b`, and `floor_dark_panel` are source crops permitted only as sparse detail panels because their edges are not seamless.
- Source crates, console, rack, and plant are classified as optional props.
- The source door, pressure plate-like panel, colored lights, laser, and unused props are reference-only.
- Every AI wall piece is rejected as runtime collision terrain because its perspective and dimensions are inconsistent.
- The seamless base floor and collision wall/corner are deterministic project-authored placeholders that use the source palette.
- The left map preview is copied to `facility_map_reference.png` for review and is never loaded by gameplay.

Door, pressure plate, objective, and exit retain their existing stateful scenes. They must not become baked TileMap cells because their collision, reset, registry, and signal behavior belongs to gameplay code.

## Atlas and pivot contract

Both character atlases use a regular 48×64 grid with eight columns. Every referenced frame is non-empty RGBA, fits inside its cell, retains transparent padding, and is bottom-center aligned at pivot `(24, 62)`. Animation rectangles, frame indices, FPS, loop flags, and fallbacks are stored in the JSON manifest and generated into the matching Godot `SpriteFrames` resource in the same run.

The processed and runtime atlas copies have identical pixel hashes. Runtime scenes use:

```text
res://assets/sprites/characters/player_atlas.png
res://assets/sprites/characters/guard_atlas.png
res://assets/sprites/environment/facility_tileset.png
```

They never use a source sheet, preview, or processed-reference path.

## Godot import rules

Pixel-art atlases use nearest filtering, no mipmaps, no repeat, and lossless PNG data. The project uses the Compatibility renderer. Import cache files under `.godot/` are reproducible and are not committed.

Global nearest filtering is configured in `project.godot`, and presentation nodes may also request nearest filtering explicitly. Pixel transform snapping is not used to quantize gameplay motion: the player and Ghost must preserve smooth, timestamp-based simulation and replay. The common fixed pivot and no-filter textures prevent most shimmer without changing recorded positions.

After regenerating assets, import and parse them with the same Godot version used by the project:

```bash
godot --headless --path . --import
godot --headless --path . --quit
```

## Validation coverage

`validate` checks:

- required pipeline input/output files and pinned configured-input hashes;
- RGBA output and real transparent padding;
- regular frame/tile dimensions and in-bounds rectangles;
- non-empty frames and a single significant actor component;
- residual player checkerboard pixels and unexpected connected background;
- consistent 48×64 frame size and `(24, 62)` pivot;
- JSON parsing, expected animation ordering, valid indices, positive FPS, and valid fallback targets;
- processed/runtime atlas pixel equality and manifest pixel hashes;
- `SpriteFrames` animation names and texture path agreement;
- TileSet collision flags and world collision layer;
- absence of `res://assets/source/`, `res://assets/processed/`, or `res://assets/concept/` references in gameplay resources.

Godot import, scene parsing, gameplay tests, and Web export are separate release checks; see `README.md` and `docs/release.md`.

## Replacing a generated source

1. Retain the old source when provenance/history requires it; never silently overwrite an input and commit only new derivatives.
2. Inspect the replacement with `inspect` and review its real alpha, candidate layout, bounding boxes, and color distribution.
3. Update the expected SHA-256 and explicit frame/crop mappings in `tools/asset_pipeline.py`.
4. Keep or deliberately revise the shared frame size/pivot contract. A scale change requires scene and collision review.
5. Run `process-all`.
6. Inspect all contact-sheet previews at nearest-neighbor zoom, including feet, visor/equipment, alpha fringes, and direction labels.
7. Run the asset validator, Godot import, headless tests, main-scene smoke test, and Web export.
8. Update `docs/asset_manifest.md` and `THIRD_PARTY_NOTICES.md` if provenance, fallbacks, use, or licensing changed.

Do not accept a frame because its source label says `32×48` or `32×32`; the pipeline uses measured pixels and explicit validation.
