# HELIX Environment Art Bible

This is the visual source of truth for **Operation: Black Minute**. Gameplay topology, collision, visibility, access progression, stable IDs, and Chrono Recall remain authoritative in their existing blueprints and systems. Environment art may explain those rules, but may not redefine them.

## Pixel contract

| Element | Contract |
|---|---|
| Logical tile | 32×32 px |
| Character frame | 48×64 px; bottom-center pivot `(24, 62)` |
| Small prop | 32×32 px |
| Tall prop | 32×64 or 32×96 px, assembled on solid cells |
| Room landmark | 64×64 px (2×2 logical cells); larger only when blueprint solids already support it |
| Outline | 1 px interior detail; up to 2 px for a hero silhouette |
| Wall height cue | top cap 3–5 px, face/body, then a base/threshold strip |
| Key light | upper-left; highlights must not reverse between rooms |
| Contact shadow | short, dark lower edge; never a long directional cast shadow |
| Sampling | nearest-neighbor only; no bilinear/bicubic resize |
| Import | nearest filter, mipmaps off, repeat off, lossless PNG |
| Sorting | actors use feet as the Y-sort reference; decorative TileMap layers do not move gameplay pivots |

Pixel snapping is a presentation choice, not a simulation rule. Player, Guard, Ghost, and Recall positions remain subpixel and deterministic.

## Canonical palette

The machine-readable palette is `assets/source/environment/facility_environment_spec.json`. New environment colors should be chosen from it or be a documented value ramp derived from it.

| Role | Canonical color | Use |
|---|---|---|
| Deep background navy | `#07111D` | void, deep recess, preview board |
| Outline | `#080F18` | prop separation and contact edge |
| Wall dark | `#0B1724` | recess and wall shadow |
| Wall face | `#122638` | primary reinforced panel |
| Wall mid | `#1A344A` | bevel and secondary structure |
| Wall top | `#33556D` | upper-left cap highlight |
| Steel | `#22384A` | furniture shells |
| Steel light | `#31536B` | upper faces and handles |
| Temporal cyan | `#30DDE3` | Player/time hero information only |
| Dim systems cyan | `#168B9A` | environment terminals and trim |
| Security amber | `#E6A83A` | power, hazard, Guard-supporting cues |
| Danger red | `#D9565F` | locked/alert states; never ambient filler |
| Temporal violet | `#A77BFF` | Chronos Core, vault circuitry |
| Confirmed green | `#5CCB96` | access confirmation and safe state |
| Practical warm | `#F2D58A` | sparse human/workplace lighting |

Environment cyan must remain dimmer and less saturated than the live Player visor. A room uses the shared palette plus one dominant and at most one supporting accent.

## Material grammar

| Material | Highlight | Midtone | Shadow | Wear / edge rule |
|---|---|---|---|---|
| Painted metal | narrow cool upper-left line | even blue-gray panel | dark lower/right seam | sparse chips on outer corners only |
| Raw dark metal | muted gunmetal cap | low-value broad face | deep navy recess | rivets and scratches, never noise on every tile |
| Reinforced wall | bright 3–5 px cap | segmented face | strong base strip | walkable-facing edge gets the clearest bevel |
| Glass | cyan/white short diagonal | transparent navy | dark frame | one controlled reflection; no full-screen glow |
| Monitor glass | cyan trace on near-black | blue-black screen | black bezel | feed variation inside one silhouette family |
| Concrete / yard | cool gray flecks | desaturated charcoal | irregular dark crack | cracks and drains are sparse overlays |
| Grass / grass edge | cool desaturated green tip | deep blue-green body | navy soil seam | reserved for exterior margins; never competes with the extraction ring or implies a walkable shortcut |
| Rubber floor | soft blue-black | almost uniform | narrow recessed seam | no specular cyan accents |
| Hazard stripe | amber | amber-brown | navy separator | reserved for power/service boundaries |
| Cable | one-pixel accent | dark insulated body | contact line | bends follow 90-degree grid logic |
| Plant | desaturated green | dark green | navy base | never brighter than access green |
| Water stain | one-value lift | translucent cool patch | none | broad irregular shape, no interaction-like outline |
| Temporal energy | cyan/violet core | violet mid | navy halo edge | concentric, stable geometry; restrained pulse |
| Laser emitter | hot magenta/red | steel shell | black recess | beam remains the brightest red element |

## Lighting rules

- `CanvasModulate` establishes ambient darkness; it must not erase traversable floor boundaries.
- Player visibility lighting remains gameplay-authoritative. Decorative lighting may not reveal a hidden room through a closed wall or door.
- Prefer painted emissive pixels and small stateful sprites over additional shadow-enabled `PointLight2D` nodes.
- One dominant practical-light color and one supporting accent are allowed per room.
- CCTV uses dim cyan plus a small amber status cue; Electrical uses amber plus red status; Research uses cool cyan plus violet experiment cues; Vault uses violet plus cyan at the Core.
- Emergency flashes, if added later, must be low-frequency, phase-stable, pause-safe, and accompanied by a non-color state cue.
- No screen-reading shaders, broad bloom, or light radius shared indiscriminately across rooms.

The accepted presentation pass uses low-alpha painted polygons clipped to each
room rectangle. These pools establish focal hierarchy without becoming
visibility authority, casting shadows, or leaking through walls. They are drawn
by one pause-safe presenter; no additional `PointLight2D` is used.

## Dressing density

Every room is composed in this order:

1. One label-blind, 2×2 landmark with a room-specific silhouette.
2. Existing functional gameplay objects.
3. One or two supporting prop groups placed only on blueprint solid cells.
4. Sparse micro detail, normally around 6% of floor cells.
5. Clear breathing space for navigation, Guard cones, prompts, and silhouettes.

No tall decorative prop may be placed on a walkable cell unless gameplay collision is deliberately authored and validated in the blueprint. Decorative marks may not resemble keycards, interaction brackets, lasers, exits, or Guard indicators.

## Room identity sheet

| Room | Material family | Hero / signature | Accent | Breathing-space rule |
|---|---|---|---|---|
| External Infiltration Yard | rough outdoor metal/concrete | fence, floodlight, loading stripe | weathered amber | preserve the broad onboarding and extraction lane |
| Reception Checkpoint | clean corporate panels | HELIX seal, scanner pedestal, turnstile line | dim cyan | clear path between public gate and checkpoint |
| Staff Office | corporate panels | paired workstations, noticeboard, plant | cyan + warm cue | desks remain on declared solids; work aisles stay empty |
| Locker Room | corporate panels | open locker and bench | muted steel + amber | Level 1 card silhouette must remain isolated |
| Security Office | corporate/security | situation map and security shield | amber | Level 2 card and door approaches remain quiet |
| CCTV Control Room | systems floor | six-feed video wall and operator console | cyan + amber | hacking terminal and Guard cone remain unobscured |
| Electrical Room | systems floor | paired breaker banks and bus lightning mark | amber + red | central terminal approach stays open |
| Server Room | systems floor | three rack faces and fan/LED language | cyan LEDs + violet | rack aisles remain legible and walkable |
| Research Laboratory | clean research floor | specimen pod and biometric chamber | cool cyan + violet | experiment floor stays bright enough for actors |
| Guard Break Room | corporate foundation | vending machine, sofa, and steaming mug | warm amber | preserve patrol turn radius |
| Laser Corridor | research/security floor | paired emitter housings and beam stack | magenta/red | minimal dressing; lasers own the focal hierarchy |
| Vault Antechamber | vault panels | reinforced circular portal and authorization scanner | restrained violet | intentionally sparse security threshold |
| Chronos Vault | vault panels | containment arms and temporal ring | violet + cyan | Core silhouette and acquisition prompt always win |
| Maintenance Passage | service floor | pipe manifold, valves, and service trench | amber utility | narrow path must never read as blocked by decoration |
| Extraction Route | service floor | runway rails, arrows, and departure strobe | green + cyan | long escape lane stays uncluttered |

## Layer and geometry authority

`OperationBlackMinuteMap` uses the following split:

- `Walls`: invisible original TileSet cells; authoritative collision and occlusion.
- `WallArt`: visual-only reinforced walkable-facing masks plus a two-cell deep-wall ring.
- `Floor` and `FloorDetails`: visual-only room-family materials and sparse overlays.
- `PropsAbove`: visual-only semantic furniture placed exactly on existing `internal_solid_rects`.
- `HeroDetails`: one visual-only 2×2 landmark for each of the 15 rooms (60 cells total).
- `AnimatedDetails`: one state/motion cell per room, refreshed at a fixed presentation tick.
- `EnvironmentPresenter`: room-clipped painted practical pools and deterministic state routing.
- Dynamic doors, cards, terminals, lasers, Core, extraction, Guards, cameras, Player, and Echoes remain independent scenes.

`resources/tilesets/facility_environment_art.tres` must always contain zero physics layers and zero occlusion layers. A visual cycle that requires new geometry must be treated as a gameplay change and reviewed separately.

## Animation and VFX restraint

- Only hero/status elements should animate: monitor feeds, server LEDs, breaker status, Core, laser, extraction.
- Use deterministic phase offsets derived from stable IDs; avoid runtime randomness.
- One to three subtle moving elements per room is enough.
- Pause and Recall behavior must be explicit before adding an animation.
- The current pass uses one fixed 6 Hz visual clock and stable room phases.
  CCTV/laser shutdown, facility alert, stolen Core, and active extraction select
  explicit state tiles. Reset returns every room to tick zero. No new particle,
  shader, physics, occlusion, or shadow-casting light node is added.

## Review gates

Keep an art change only when:

- a six-tile run is not dominated by an obvious repeated accent rhythm;
- all 15 rooms can be identified from their landmark silhouette in a label-hidden review; labels are only a secondary confirmation cue;
- the Level 1 card and other mandatory pickups remain visually dominant from at least two tiles away;
- wall art agrees exactly with collision and door openings;
- Player, Ghost, Guard, keycards, terminals, lasers, Core, doors, and extraction remain more prominent than decoration;
- no hidden-room information leaks through lighting;
- Web export has no new console errors and payload growth is explained;
- all 15 rooms pass clean-art, initial-gameplay, and late-state 1280×720 captures;
- a 1024×768 browser viewport retains HUD and object readability.

Revert when decoration weakens gameplay recognition, implies false collision, introduces perspective/pixel-density drift, produces more repetition, or materially degrades Web performance.
