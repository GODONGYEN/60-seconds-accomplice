# Visual Quality Scorecard

This scorecard separates **structural completeness** from **perceptual quality**.
Generated metadata, a unique atlas hash, or the presence of a room marker can
prove that content exists; none of those facts proves that a player can actually
recognize the room. A `10/10` may only be assigned after the label-hidden and
gameplay-state reviews below pass in real rendered builds.

The committed matrices below were regenerated from the current 64×64 landmark
pass on 2026-07-15:

- [label-hidden clean-art matrix](screenshots/environment/final/art_clean_15_room_contact_1280x720.png)
- [initial-gameplay matrix](screenshots/environment/final/gameplay_initial_15_room_contact_1280x720.png)
- [late-state matrix](screenshots/environment/final/gameplay_late_15_room_contact_1280x720.png)

## Ten-point perceptual gate

Each room earns one point only when the rendered result satisfies the criterion:

1. its material family and dominant accent differ from adjacent rooms;
2. its 64×64 landmark has a unique silhouette visible at normal gameplay zoom;
3. the landmark still identifies the room when all room-name plaques are hidden;
4. at least two supporting signatures reinforce rather than duplicate the landmark;
5. practical lighting leads the eye to the room function without revealing hidden space;
6. pause-safe motion or state feedback communicates a real room function;
7. wall and door depth agrees with collision and the active opening;
8. the walkable route, Guard sight line, and interaction approach remain clear;
9. Player, Echo, Guard, cards, terminals, Core, doors, and extraction outrank decoration;
10. clean, initial-gameplay, and late-state 15-room Compatibility captures pass
    at 1280×720; the Web export also passes representative gameplay/map frames
    at 1280×720 and a 1024×768 overflow/readability check.

The asset validator covers atlas bounds, uniqueness, deterministic generation,
and geometry overlap. Runtime tests cover the 60-cell landmark placement,
pause/reset stability, and state wiring. Those are release prerequisites, but
points 1–3, 5, 8–10 still require rendered visual judgment.

## Current room review ledger

Review date: 2026-07-15. All three 15-room matrices were inspected at original
resolution. The clean matrix hides plaques, the gameplay matrix includes actors,
cones, HUD and interactions, and the late matrix includes network shutdown,
alert, open-door, stolen-Core and active-extraction states. The single-threaded
Web export was then checked over local HTTP at 1280×720 and 1024×768 with zero
browser warnings or errors. Runtime tests separately verify collision, portal,
pause/reset, and state wiring.

| Room | Label-blind landmark | Rendered review result | Numeric score |
|---|---|---|---:|
| External Infiltration Yard | fence + floodlight + loading stripe | 10 gates passed; broad outdoor negative space retained | 10/10 |
| Reception Checkpoint | HELIX seal + scanner | 10 gates passed; corporate entry focal point is immediate | 10/10 |
| Staff Office | workstations + noticeboard + plant | 10 gates passed; lived-in office silhouette remains route-safe | 10/10 |
| Locker Room | open locker + bench | 10 gates passed; L1 beacon remains dominant over furniture | 10/10 |
| Security Office | situation map + shield | 10 gates passed; command identity differs from CCTV | 10/10 |
| CCTV Control Room | six-feed video wall | 10 gates passed; online/offline feed state stays legible | 10/10 |
| Electrical Room | breaker banks + power bolt | 10 gates passed; amber power language differs from Server | 10/10 |
| Server Room | triple racks + fan/LED language | 10 gates passed; rack aisle and override terminal stay clear | 10/10 |
| Research Laboratory | specimen pod + biometric chamber | 10 gates passed; violet lab silhouette is unique | 10/10 |
| Guard Break Room | vending machine + sofa + mug | 10 gates passed; warm human space contrasts security rooms | 10/10 |
| Laser Corridor | paired emitters + beam stack | 10 gates passed; danger geometry matches the physical lane | 10/10 |
| Vault Antechamber | circular portal + authorization scanner | 10 gates passed; reinforced threshold reads before the Vault | 10/10 |
| Chronos Vault | containment arms + temporal ring | 10 gates passed; Core remains the highest-value focal point | 10/10 |
| Maintenance Passage | pipe manifold + valves | 10 gates passed; service identity survives low illumination | 10/10 |
| Extraction Route | runway rails + directional arrows | 10 gates passed; active state communicates escape direction | 10/10 |

These scores are a recorded pass of the explicit gate above, not a claim that
the art can never improve. Any future atlas, HUD, lighting, or map change
invalidates the affected rows until the same evidence is regenerated.

## Global safety gates

- The visual TileSet owns no physics or occlusion layers.
- Landmarks occupy only four validated decorative cells and never redefine
  blueprint topology.
- Room-name plaques are a secondary navigation cue, not a substitute for art.
- The brighter ambient must preserve stealth contrast and actor silhouettes.
- Web export must have no new console errors or unexplained payload growth.
