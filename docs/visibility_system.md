# Player Visibility and Wall Occlusion

This document describes the wall-based visibility contract used by `facility_level_01`. It is presentation and information filtering layered over the existing deterministic gameplay simulation: an unseen Guard or Ghost continues to move, perceive targets, and replay recordings.

## Runtime flow

```text
Player position
→ PlayerVision PointLight2D
→ TileSet and dynamic LightOccluder2D polygons
→ rendered visible area

PlayerVisibilityProbe
→ radius check and PlayerVisionBlocker physics ray
→ WorldVisibilityController target alpha gate
→ Guard/Ghost/object/indicator and HUD information visibility
```

`FacilityLevel01` owns the composition. The reusable Player scene contains the probe, light, and camera, but they remain disabled in the 20-second prototype level. `configure_facility_view()` configures the facility camera and visibility components while leaving queries and light disabled; the final `set_level_simulation_enabled(true)` step enables them only after deterministic reset assembly finishes.

## Darkness and the Player light

The facility root has a `CanvasModulate` color of `Color(0.015, 0.02, 0.035, 1)`. It keeps rooms outside current light effectively dark while preserving only enough near-edge response for Player-lit wall silhouettes. It is not persistent explored fog-of-war.

The live Player owns one shadow-enabled `PointLight2D` below `PlayerVision`:

- origin: `Vector2(0, -18)` from the Player root;
- default facility radius: `240 px` (export range `160..320 px`);
- radial texture: `resources/vision/player_vision_gradient.tres`;
- light and shadow mask: `1`;
- Compatibility-renderer-safe unfiltered shadows;
- no decorative shadow lights or per-wall light nodes.

The Player camera is enabled only for the facility, uses `2×2` zoom, and is limited to the `832×800 px` map bounds. The prototype retains its existing camera and lighting behavior.

## Static walls

`resources/tilesets/facility_tileset.tres` defines full-cell `32×32 px` physics polygons and `OccluderPolygon2D` data for every approved solid wall tile. The resource has:

```text
physics collision layer: World | PlayerVisionBlocker = 1 | 64 = 65
occlusion light mask: 1
```

Only the `Walls` `TileMapLayer` enables both collision and occlusion. Floor, detail, and prop layers explicitly disable both, so decorative pixels cannot become invisible blockers. The map fills every non-walkable cell, including the complete outer boundary, with a solid wall tile.

The same authored wall geometry is authoritative for movement, Guard line of sight, and Player information visibility. The query masks remain deliberately separate:

- Guard perception queries `World` (`1`);
- `PlayerVisibilityProbe` queries `PlayerVisionBlocker` (`64`);
- a wall or closed door participates in both by using collision layer `65`.

Both systems call `WorldLineOfSight2D`, preventing their open-door handling from drifting while still avoiding unrelated gameplay bodies in Player visibility queries.

## Dynamic door

`SecurityDoor` owns three synchronized states:

```text
closed
→ movement collision enabled
→ Guard World LOS blocked
→ PlayerVisibilityBlocker ray blocked
→ LightOccluder2D visible

open
→ movement collision disabled
→ both LOS queries pass
→ LightOccluder2D hidden
```

The door collision layer is `65`. Its full-height `LightOccluder2D` uses light mask `1`. `reset_for_loop()` closes the door and restores the occluder. Runtime changes are queued onto one deferred commit after physics-query flushing, so logical LOS state, movement collision, the light occluder, visual redraw, and the state signal transition together.

The laser is intentionally different. It is a current-Player detection trigger that ends a loop while active; it is not a wall, movement collider, Guard LOS blocker, or light occluder. The nearby stable-ID terminal latches it off until the next deterministic reset.

## `PlayerVisibilityProbe` API

`scripts/visibility/player_visibility_probe.gd` provides the query boundary:

- `set_query_enabled(enabled)` disables all visibility outside the facility lifecycle;
- `set_visibility_radius(radius)` sets the radial limit;
- `get_visibility_origin()` returns the Player-mounted ray origin;
- `is_world_point_visible(position)` applies the radius and blocker ray;
- `is_actor_visible(actor)` uses `get_visibility_sample_position()` when the target supplies it, otherwise its global position.

A disabled probe, a point outside the radius, or a blocking hit returns `false`. The probe excludes its owning collision body and never searches the scene tree for targets.

## World actors, indicators, prompts, and HUD

`WorldVisibilityController` keeps a cached target list and refreshes it at `20 Hz` (`0.05 s`). The facility registers:

- the authored Guard;
- every spawned Ghost;
- pressure plate, security door, laser, terminal, objective, and exit;
- the decorative offline security camera.

Visibility is applied to the target root's alpha, preserving each sprite's base modulation. A hidden actor is not freed and its process mode is not changed. Because a Guard's cone, `?`/`!` indicator, and label are children of that root, they disappear with the Guard and cannot reveal a room through the wall. Ghost playback and Guard AI continue behind walls.

The Player interactor uses the same probe before showing or accepting a nearby target. This prevents an interaction prompt from leaking a terminal or objective through a wall. The HUD reports `GUARD — OUT OF SIGHT` instead of exposing state, suspicion, or target data for a hidden Guard. Reset disables the controller, clears runtime Ghost targets, hides all registered targets, then re-enables queries only after the new live Player exists.

## Adding a wall tile

1. Add or classify the tile through `tools/asset_pipeline.py`; do not hand-edit `.import` files.
2. Give every tile intended as a solid wall both a full-cell physics polygon and an occlusion-layer polygon in the generated TileSet resource.
3. Keep the TileSet physics layer on `65` and occlusion light mask on `1`.
4. Place the tile only on the collision/occlusion-enabled `Walls` layer.
5. Run the asset validator and Godot tests, then verify the shadow in an exported Web build.

```bash
.tools/venv/bin/python tools/asset_pipeline.py process-tileset
.tools/venv/bin/python tools/asset_pipeline.py validate
GODOT_BIN=godot tools/run_tests.sh
```

## Adding a dynamic occluder

1. Keep the stateful object as an independent scene, not a baked TileMap tile.
2. Put its blocking `CollisionObject2D` on collision layer `65` if it must block movement and both LOS systems.
3. Add a matching `LightOccluder2D` with light mask `1`.
4. Change collision, logical LOS state, visual state, and occluder state through one method.
5. Restore all four in `reset_for_loop()` and test the open/closed transition plus reset.

If an object should block only one system, use the narrowest layer instead of copying the door contract. The laser is the current example of a visible trigger that intentionally blocks neither LOS system.

## Debugging light leaks

- Confirm the cell is on `Walls`, not `WallDetails` or a prop layer.
- Confirm the chosen atlas tile has an occlusion polygon as well as a physics polygon.
- Check that `Walls.occlusion_enabled` is true and the Player light's shadow mask matches occlusion mask `1`.
- For a door, compare `is_open`, collision-shape disabled state, and `LightOccluder2D.visible` after a physics frame.
- Use the probe's point query separately from the rendered light. A correct physics ray does not prove that Compatibility-renderer shadows rendered correctly.
- Inspect doorway seams at both `1280×720` and a resized browser viewport; full-cell polygons can expose gaps if a portal scene is offset from the authored cell span.

## Validation and renderer limits

Logic and resource validation can run headlessly:

```bash
godot --headless --path . --import
GODOT_BIN=godot tools/run_tests.sh
godot --headless --path . --export-release "Web" build/web/index.html
python3 -m http.server --directory build/web 8000
```

Headless tests can verify radius/LOS decisions, collision masks, occluder resource presence, target alpha gating, and reset. They cannot certify the pixels produced by `PointLight2D` shadows. A release candidate therefore still requires browser screenshots for closed/open doors, corners, hidden Guard/Ghost indicators, and resized viewports, plus console inspection. Do not mark that rendering check complete based only on a parse or Web export.

Known limitations:

- the rendered light is radial, not a fully clipped room polygon or persistent explored-map fog;
- actor reveal uses one sample point, so large future actors may need multiple samples;
- target alpha changes at 20 Hz and may pop at a sharp doorway instead of fading;
- TileSet and `LightOccluder2D` shadow edges can vary slightly across WebGL/Compatibility-renderer implementations;
- unlit rooms are driven close to black by `CanvasModulate`; Player-lit wall faces remain readable, while gameplay actors and information are additionally strict-gated;
- browser screenshot and console validation must be repeated for each deployment and is not implied by automated test success.
