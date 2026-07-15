# Visual Quality Scorecard

This scorecard uses a reproducible **10-point room-completeness gate**. A `10/10`
means that the room satisfies every authored visual and gameplay-readability
contract below; it is not a claim that subjective art can no longer improve.

The review set covers all 15 authored rooms in three deterministic states at
1280×720:

- [clean art matrix](screenshots/environment/final/art_clean_15_room_contact_1280x720.png)
- [initial gameplay matrix](screenshots/environment/final/gameplay_initial_15_room_contact_1280x720.png)
- [late-state gameplay matrix](screenshots/environment/final/gameplay_late_15_room_contact_1280x720.png)

## Ten-point gate

Each room earns one point for each independently inspectable contract:

1. a canonical material family and accent palette;
2. a unique two-cell hero silhouette;
3. at least two room-specific signature marks (large rooms receive more);
4. a room-clipped practical-light recipe;
5. a deterministic, pause-safe micro-animation;
6. a stable presentation phase with no runtime randomness;
7. reinforced wall/door depth that agrees with the gameplay opening;
8. preserved walkable space, collision, occlusion, and Guard sight lines;
9. Player, Echo, Guard, objective, and interaction contrast above decoration;
10. clean-art, initial-gameplay, and late-state capture evidence.

The asset validator checks profile completeness, unique/bounded placements, and
atlas determinism. The Godot runtime suite checks pause/reset stability, room
frame ownership, state wiring, geometry, collision, and occlusion boundaries.
Manual review of the complete screenshot matrix checks actor/gameplay contrast
and supplies the final evidence point. Dynamic objects remain scenes; the
environment TileSet has zero collision and occlusion layers.

| Room | Material | Hero | Signatures | Light | Motion | Stable | Depth | Gameplay | Contrast | Evidence | Score |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| External Infiltration Yard | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Reception Checkpoint | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Staff Office | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Locker Room | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Security Office | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| CCTV Control Room | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Electrical Room | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Server Room | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Research Laboratory | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Guard Break Room | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Laser Corridor | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Vault Antechamber | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Chronos Vault | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Maintenance Passage | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |
| Extraction Route | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **10/10** |

## Verified global improvements

| Area | Accepted result | Evidence |
|---|---|---|
| Tile repetition | Sparse seeded details replace the former global checker rhythm | clean-art matrix and deterministic atlas fingerprint |
| Room identity | Every room has a unique hero, two signatures, palette, light anchors, and motion cell | generated manifest and 15-room matrix |
| Wall depth | A reinforced walkable-facing mask plus a deep-wall ring replaces the infinite panel field | overview and wall-layer assertions |
| Door integration | Access ranks now have distinct frames, hazard language, exact spans, and open/closed silhouettes | initial/late matrices and exact-shape assertions |
| Practical lighting | Low-alpha painted pools are clipped inside each room and never become visibility authority | presenter node audit and no-`PointLight2D` assertion |
| Environment motion | One fixed 6 Hz visual tick with stable room phases; pause/reset are deterministic | presenter tests |
| Stateful feedback | CCTV, laser, alert, stolen-Core, extraction, and door state have visible alternatives | late-state matrix and state-tile tests |
| Performance safety | One presenter and two visual TileMap layers; no per-cell nodes, shaders, particles, physics, or occlusion | runtime tree and TileSet validation |

## Honest interpretation

The `10/10` values above certify implementation completeness against the
project's room contract. They do not substitute for independent taste testing,
long-session playtesting, or measured browser frame-time profiling. Those remain
valid future polish inputs even though every room now passes the release gate.
