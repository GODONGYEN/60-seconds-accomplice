# Facility Level 01 Layout

This document is the authored spatial contract for `facility_level_01`. The source reference remains an art and topology reference; gameplay uses TileMap layers and independent dynamic scenes.

## Coordinate contract

- Logical size: `26 × 25` cells
- Tile size: `32 × 32` pixels
- World size: `832 × 800` pixels
- Cell coordinates are zero-based: `x = 0..25`, `y = 0..24`
- Rectangles use `[x, y, width, height]`
- A cell center maps to `Vector2((x + 0.5) * 32, (y + 0.5) * 32)`
- Camera bounds are `Rect2(0, 0, 832, 800)`; the initial zoom target is `Vector2(2, 2)`
- Facility loop duration: `60` seconds. The prototype remains `20` seconds.

The machine-readable copy is `resources/maps/facility_level_01_blueprint.json`.

## Rooms

All rectangles below describe walkable floor cells. Solid cells are derived as the complement of rooms, connectors, and dynamic portal spans.

| Room | Rect | Inclusive cells | Purpose |
|---|---:|---|---|
| Upper-left control | `[1, 1, 6, 5]` | `x1..6, y1..5` | Secure objective room and monitor desks |
| Upper central corridor | `[8, 1, 8, 6]` | `x8..15, y1..6` | Vault approach and upper patrol space |
| Upper-right control | `[17, 1, 8, 5]` | `x17..24, y1..5` | Server room and optional interaction space |
| West service corridor | `[1, 7, 2, 10]` | `x1..2, y7..16` | Narrow warning-lit utility route |
| Middle-left enclosed | `[4, 8, 8, 7]` | `x4..11, y8..14` | U-shaped equipment room and visibility test space |
| Center security corridor | `[13, 7, 6, 11]` | `x13..18, y7..17` | Main intersection and Guard sightline |
| Right laser room | `[20, 8, 5, 8]` | `x20..24, y8..15` | Laser, terminal, and courtyard approach |
| Lower-left utility | `[1, 18, 6, 6]` | `x1..6, y18..23` | Pressure plate and distraction endpoint |
| Lower operations | `[8, 19, 10, 5]` | `x8..17, y19..23` | Lower landmark and Ghost lure lane |
| Lower-right courtyard | `[19, 17, 6, 7]` | `x19..24, y17..23` | Safe spawn, exterior treatment, and exit |

## Corridors and portals

| Connection | Rect | Notes |
|---|---:|---|
| West service → upper central | `[3, 6, 5, 2]` | Runs below the objective room without entering it |
| West service → middle-left | `[3, 11, 1, 2]` | Narrow doorway |
| Middle-left → center | `[12, 10, 1, 3]` | Three-cell sightline opening |
| Middle-left → lower utility | `[5, 15, 2, 3]` | Short elbow connector |
| Center → lower operations | `[14, 18, 3, 1]` | Primary Guard-lure opening |
| Lower utility → operations | `[7, 20, 1, 3]` | Wide-enough Ghost and Guard passage |
| Operations → courtyard | `[18, 19, 1, 2]` | Offset from spawn to preserve the safe opening |
| Laser room → courtyard | `[21, 16, 3, 1]` | Alternate live-player route |
| Upper central → upper-right | `[16, 3, 1, 2]` | Static doorway |
| Upper central → center | Direct adjacency | `B x13..15/y6` meets `E x13..18/y7` |

Dynamic portal floor cells remain present beneath their gameplay scenes:

- `door_vault_01`: anchor `(7, 3)`, vertical span `x7/y1..5`. Closed state blocks movement, Guard LOS, and Player light; open state passes all three.
- `laser_right_01`: anchor `(19, 11)`, vertical span `x19/y10..12`. Its active `Area2D` detects the current Player and ends the loop; it is not a movement, light, or sight blocker. `terminal_laser_01` disables it until reset.

## Gameplay objects

| Object | Cell | World center | Rule |
|---|---:|---:|---|
| Player spawn | `(24, 23)` | `(784, 752)` | Courtyard safe start |
| `plate_vault_01` | `(4, 21)` | `(144, 688)` | Holds `door_vault_01` open |
| `terminal_laser_01` | `(22, 13)` | `(720, 432)` | Latches `laser_right_01` off for the current loop |
| `objective_core_01` | `(3, 3)` | `(112, 112)` | Live Player collects it inside the sealed control room |
| `exit_courtyard_01` | `(23, 21)` | `(752, 688)` | Activates after objective collection |
| Offline security camera | `(24, 3)` | `(784, 112)` | Decorative only; crossed-out housing and `OFFLINE` label, no detection or collision |

The vault has no alternate opening. A current Player cannot leave the pressure plate and enter the vault before it closes, so at least two timelines are required.

## Guard routes

`guard_center_01` is the required acceptance Guard:

```text
spawn/P01 (14, 8)
→ P02 (17, 8)
→ P03 (17, 15)
→ P04 (14, 15)
→ P01
```

Each segment is a clear straight line inside the center corridor. The lower leg can see through the center-to-operations portal and follow a visible Ghost west through operations to the pressure plate.

`guard_vault_01` is authored but remains disabled until multi-Guard capture/reset acceptance passes:

```text
spawn/P01 (10, 2)
→ P02 (14, 2)
→ P03 (14, 5)
→ P04 (10, 5)
→ P01
```

This second route stays inside the upper central corridor and does not require pathfinding around corners.

## Props and readability

- Upper-left and upper-right desks stay against the north edges.
- Middle-left crates and terminals stay within `x5..10/y9..13`, leaving both door approaches clear.
- Center corridor props stay on its east edge; the `x14..16` lower sightline remains empty.
- The lower operations island occupies only `x10..12/y20`; a two-cell route remains around it.
- Courtyard plants stay near `(20, 22)` and `(24, 18)`. Spawn, exit, and both facility entries remain clear.
- The current atlas has no approved seamless grass tile. The courtyard therefore uses the authored dark base floor with sparse variation until a validated project-authored grass tile is added.

Decorative TileMap props are non-colliding. Stateful or blocking objects remain independent scenes.

## Collision and occlusion boundary

The map generator treats every in-bounds cell not covered by a room, connector, or dynamic portal span as a wall. This includes the complete outer boundary. The rule provides:

- a closed physics boundary with no edge gaps;
- identical wall cells for Guard LOS blocking;
- a single deterministic cell set for TileSet light occlusion;
- floor underlays beneath the vault door and laser, allowing their scenes to own state transitions.

The `Walls` TileMap layer owns physical collision and enables TileSet light occlusion. Approved wall and corner tiles have matching full-cell physics and occlusion polygons; their collision layer is `World | PlayerVisionBlocker` (`65`). `WallDetails`, `FloorDetails`, and both prop layers remain non-colliding and non-occluding.

## Intended two-loop solution

### Loop 1

The Player enters lower operations, deliberately crosses the center Guard sightline, leads the Guard west, and ends the recording on `plate_vault_01`. Capture or timeout records the final plate position.

### Loop 2

The Ghost repeats the lower route, attracts `guard_center_01`, and holds the vault plate. The live Player uses the courtyard-to-laser route, operates `terminal_laser_01`, passes through the disabled laser and center corridor, enters the open upper-left control room, takes the objective, and returns to the courtyard exit.

Player target priority remains authoritative. The live route is successful because walls separate it from the Guard-distraction lane, not because the Guard ignores the Player.
