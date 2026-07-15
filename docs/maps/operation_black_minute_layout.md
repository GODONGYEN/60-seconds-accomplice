# Operation: Black Minute — Facility Layout Contract

This document is the authored spatial and progression contract for
`operation_black_minute`. Gameplay must be built from the corresponding
machine-readable blueprint at
`resources/maps/operation_black_minute_blueprint.json`; the map is not a
scaled-up background image.

## Coordinate contract

- Logical size: `64 × 42` cells
- Tile size: `32 × 32` pixels
- World size: `2048 × 1344` pixels
- Cell coordinates are zero based: `x = 0..63`, `y = 0..41`
- Rectangles use `[x, y, width, height]`
- A cell center maps to `Vector2((x + 0.5) * 32, (y + 0.5) * 32)`
- Camera limits are `Rect2(0, 0, 2048, 1344)` with a recommended gameplay
  zoom of `Vector2(2, 2)`
- The complete outer boundary is solid. Every cell outside the authored room,
  connector, and dynamic-portal union is a wall unless explicitly declared as
  glass.

The map is deliberately larger than one screen. Its west side introduces
public and staff spaces, its center holds the security systems, and its east
side escalates through research and vault security. A separate south service
route carries the Core back to the extraction point without forcing the player
to retrace the entire infiltration route.

## Room and zone rectangles

All rectangles describe the walkable envelope before internal solid props are
subtracted. Stateful doors, lasers, terminals, cards, and objectives remain
independent scenes.

| Zone ID | Display name | Rect | Primary purpose |
|---|---|---:|---|
| `external_infiltration_yard` | External Infiltration Yard | `[1, 29, 11, 12]` | Safe spawn, first patrol observation, final extraction |
| `reception_checkpoint` | Reception Checkpoint | `[14, 28, 10, 9]` | Public entry, first camera and checkpoint Guard |
| `staff_office` | Staff Office | `[14, 15, 10, 9]` | Locker clue, optional facility-intel terminal |
| `locker_room` | Locker Room | `[2, 15, 9, 8]` | Level 1 access card; Office Guard periodically visits |
| `security_office` | Security Office | `[27, 28, 10, 9]` | Level 2 access card and maintenance-door control |
| `cctv_control_room` | CCTV Control Room | `[14, 4, 10, 8]` | Network hack terminal and camera status wall |
| `electrical_room` | Electrical Room | `[27, 15, 10, 9]` | Laser-network shutdown terminal and breaker cabinets |
| `server_room` | Server Room | `[27, 4, 10, 8]` | Alternate temporary vault authorization |
| `research_laboratory` | Research Laboratory | `[40, 4, 12, 9]` | Biometric authorization and Chronos research clue |
| `guard_break_room` | Guard Break Room | `[2, 4, 9, 8]` | Optional distraction terminal and patrol timing clue |
| `laser_corridor` | Laser Corridor | `[40, 16, 12, 5]` | Three active laser barriers guarding the vault wing |
| `vault_antechamber` | Vault Antechamber | `[55, 15, 8, 10]` | Level 2 checkpoint and final Guard timing challenge |
| `chronos_vault` | Chronos Vault | `[54, 4, 9, 9]` | Chronos Core landmark and theft interaction |
| `maintenance_passage` | Maintenance Passage | `[40, 24, 12, 8]` | Discoverable shortcut between Security, Electrical, and extraction |
| `extraction_route` | Extraction Route | `[40, 34, 23, 7]` | Core-triggered service return lane to the yard |

The `guard_break_room` is intentionally a useful dead end rather than a
mandatory stop. The `maintenance_passage` is not revealed on the first map;
the Security Office terminal discovers it.

## Connectors

| Connector ID | Rect | Connects | Notes |
|---|---:|---|---|
| `yard_reception_gate` | `[12, 32, 2, 3]` | Yard ↔ Reception | Public checkpoint door at its center |
| `reception_west_service` | `[6, 25, 13, 3]` | Reception ↔ west service spurs | Broad public transition hall |
| `locker_service_spur` | `[6, 23, 3, 2]` | Locker ↔ west service hall | Public route to the Level 1 card |
| `staff_service_spur` | `[18, 23, 3, 2]` | Staff ↔ west service hall | Level 1 staff threshold |
| `guard_break_locker_stair` | `[5, 12, 3, 3]` | Guard Break ↔ Locker | Optional distraction approach |
| `guard_break_cctv_link` | `[11, 7, 3, 2]` | Guard Break ↔ CCTV | Narrow service link |
| `locker_staff_doorway` | `[11, 18, 3, 2]` | Locker ↔ Staff | Level 1 staff threshold |
| `cctv_staff_doorway` | `[18, 12, 3, 3]` | CCTV ↔ Staff | Level 1 control-room threshold |
| `cctv_server_link` | `[24, 7, 3, 2]` | CCTV ↔ Server | Server side is Level 2 locked |
| `staff_electrical_link` | `[24, 18, 3, 2]` | Staff ↔ Electrical | Main Level 1 system route |
| `server_electrical_link` | `[31, 12, 3, 3]` | Server ↔ Electrical | Level 2 door on the server side |
| `server_research_link` | `[37, 7, 3, 3]` | Server ↔ Research | Level 2 research checkpoint |
| `reception_security_link` | `[24, 32, 3, 2]` | Reception ↔ Security | Level 1 security-office door |
| `electrical_security_link` | `[31, 24, 3, 4]` | Electrical ↔ Security | Internal staff stair |
| `electrical_laser_link` | `[37, 18, 3, 2]` | Electrical ↔ Laser Corridor | Main vault approach |
| `research_laser_link` | `[45, 13, 3, 3]` | Research ↔ Laser Corridor | Authorization route rejoins the approach |
| `laser_vault_link` | `[52, 18, 3, 3]` | Laser Corridor ↔ Vault Antechamber | Level 2 door after the beam grid |
| `laser_maintenance_link` | `[45, 21, 3, 3]` | Laser Corridor ↔ Maintenance | One-way service stair after discovery |
| `security_maintenance_link` | `[37, 28, 3, 3]` | Security ↔ Maintenance | Hidden Level 2 shortcut |
| `maintenance_extraction_link` | `[45, 32, 3, 2]` | Maintenance ↔ Extraction | Opens when the passage is discovered |
| `vault_ante_vault_link` | `[58, 13, 3, 2]` | Antechamber ↔ Vault | Final authorization door |
| `vault_extraction_link` | `[58, 25, 3, 9]` | Antechamber ↔ Extraction | Lockdown service lift, Core-triggered |
| `extraction_yard_link` | `[12, 38, 28, 2]` | Extraction ↔ Yard | Wide return route, Core-triggered at east end |

## Access progression and locked portals

Access uses the ordered levels `PUBLIC < LEVEL_1 < LEVEL_2 < VAULT`.
`VAULT` is an authorization credential produced by the Research biometric
station or Server override; it is not a physical card.

| Stable ID | Anchor / span | Requirement | Initial state |
|---|---:|---|---|
| `door_reception_checkpoint_01` | `(13,33)` / `[13,32,1,3]` | PUBLIC | Closed, interactable |
| `door_staff_l1_01` | `(19,24)` / `[18,24,3,1]` | LEVEL_1 | Locked |
| `door_staff_locker_l1_01` | `(12,19)` / `[12,18,1,2]` | LEVEL_1 | Locked; Guard has staff authorization |
| `door_cctv_l1_01` | `(19,13)` / `[18,13,3,1]` | LEVEL_1 | Locked |
| `door_cctv_service_l1_01` | `(12,7)` / `[12,7,1,2]` | LEVEL_1 | Locked service entrance |
| `door_server_cctv_l2_01` | `(25,7)` / `[25,7,1,2]` | LEVEL_2 | Locked |
| `door_electrical_l1_01` | `(25,19)` / `[25,18,1,2]` | LEVEL_1 | Locked |
| `door_security_l1_01` | `(25,33)` / `[25,32,1,2]` | LEVEL_1 | Locked; contains Level 2 card beyond it |
| `door_server_l2_01` | `(32,13)` / `[31,13,3,1]` | LEVEL_2 | Locked |
| `door_research_l2_01` | `(39,8)` / `[39,7,1,3]` | LEVEL_2 | Locked |
| `door_vault_ante_l2_01` | `(53,19)` / `[53,18,1,3]` | LEVEL_2 + lasers offline | Locked |
| `door_vault_authorization_01` | `(59,14)` / `[58,14,3,1]` | VAULT authorization | Locked |
| `door_maintenance_l2_01` | `(39,29)` / `[39,28,1,3]` | LEVEL_2 + passage discovered | Hidden/locked |
| `door_vault_extraction_01` | `(59,32)` / `[58,32,3,1]` | Chronos Core stolen | Locked |
| `door_extraction_yard_01` | `(39,38)` / `[39,38,1,2]` | Chronos Core stolen | Locked |

Card placement cannot be circular:

- `keycard_level_1_01` is at `(6, 19)` in the PUBLIC Locker Room.
- `keycard_level_2_01` is at `(32, 32)` behind only the Level 1 Security
  Office door.
- Vault authorization comes from either `terminal_server_override_01` at
  `(32, 7)` or `terminal_research_biometric_01` at `(46, 8)`, both reachable
  with Level 2.

Cards belong to the current mission-timeline Player inventory. Recall restores
the inventory snapshot for the recalled instant; spent Recall charges remain
spent. Echoes may replay a previously authorized door interaction, but cannot
pick up, duplicate, or transfer a card or vault credential.

## Security systems

### CCTV network

Eight rotating cameras are authored at Reception `(17,30)`, Staff `(22,17)`,
CCTV `(15,6)`, Security `(29,34)`, Electrical `(35,20)`, Research `(42,7)`,
Laser Corridor `(50,18)`, and Vault Antechamber `(61,22)`. Each uses an
authored sweep range and phase from the blueprint. Walls and closed doors block
the authoritative detection ray.

`terminal_cctv_network_01` at `(18,7)` takes `3.0 s` to hack. Completion sets
the complete CCTV network offline, changes every camera cone/light, and
completes the CCTV branch. A skilled player may leave the network online and
cross each deterministic scan during its documented safe window; one clean
crossing of the laser-wing threshold marks `cctv_safe_route_confirmed`.

### Laser network

Three independent beam spans cross the Laser Corridor at `x = 44`, `47`, and
`50`, each covering `y = 16..20`. Their red gameplay beams are detection
triggers, not walls or visibility occluders. The `3.0 s`
`terminal_laser_network_01` at `(32,19)` disables all three. This shutdown is
required for the no-Recall route and for normal Core acquisition; the Recall
ability is recovery/distraction, not a mandatory laser exploit.

### Vault authorization

The Research biometric interaction takes `2.5 s`; the Server override takes
`3.5 s`. Either grants the mission-timeline VAULT credential. Both interactions
are positioned in cover pockets with a patrol window longer than their hold
duration. The final vault door additionally checks that the laser network is
offline and Level 2 access has been acquired.

## Objective anchors

| Anchor | Cell | Rule |
|---|---:|---|
| Player spawn | `(7,38)` | South-west yard, outside both opening patrol lanes and proximity detection |
| First checkpoint trigger | `(15,33)` | Completes facility infiltration |
| Level 1 card | `(6,19)` | Public Locker Room |
| Level 2 card | `(32,32)` | Level 1 Security Office |
| CCTV terminal | `(18,7)` | Optional `3.0 s` network shutdown |
| Laser terminal | `(32,19)` | Required `3.0 s` network shutdown |
| Server authorization | `(32,7)` | `3.5 s` alternate authorization |
| Research biometric | `(46,8)` | `2.5 s` default authorization |
| Chronos Core | `(58,8)` | `1.2 s` live-Player-only theft interaction |
| Extraction | `(4,39)` | Active only while the live Player carries the Core |

Core theft raises facility alert by one step but does not reveal the Player's
location to every Guard. It opens the two extraction service doors and activates
the yard extraction marker.

## Guard zones and patrol routes

Ten Guards are distributed across seven bounded patrol zones. Patrol is fully
deterministic; no random waypoint choice is allowed.

| Zone | Guards | Coverage |
|---|---:|---|
| `zone_outer_yard` | 2 | Yard edge and extraction return lane |
| `zone_reception` | 1 | Reception checkpoint only |
| `zone_office` | 1 | Staff/Locker link, including periodic locker visit |
| `zone_cctv` | 1 | CCTV room and west service link |
| `zone_electrical` | 1 | Electrical cabinets and system terminal |
| `zone_research` | 2 | One Server patrol and one Research patrol |
| `zone_vault` | 2 | One Antechamber patrol and one Vault patrol |

Routes, wait times, start phases, return points, and chase-zone boundaries are
fully specified in the JSON blueprint. The two-Guard zones use spatially
separate loops rather than opposite-direction passes through the same choke.
After SEARCH, every Guard returns to its own zone anchor or nearest authored
waypoint.

## Chokes, reservations, and safe windows

Narrow connectors have a capacity of one Guard and use lightweight route
reservations. The extraction service corridor has capacity two. Guards wait at
the authored hold cell instead of pushing or oscillating.

Every mandatory connector declares at least one `3.0 s` or longer passage
window per `30 s` schedule cycle. The five longest objective interactions have
an authored cover strategy:

- CCTV terminal: monitor-bank blind pocket, `4.5 s` minimum window.
- Laser terminal: breaker-cabinet blind pocket, `4.0 s` minimum window.
- Server override: server-aisle blind pocket, `4.5 s` minimum window.
- Research biometric: lab-bench blind pocket, `4.0 s` minimum window.
- Core pedestal: inner-vault patrol turn, `3.5 s` minimum window.

These values are design inputs, not measured acceptance results. The patrol
validator simulates `180 s`, reports actual overlap/capacity/deadlock/zone
violations plus capacity-open reservation opportunities, and validates the
declared window contract. A capacity-open interval is not proof of LOS-safe
Player passage; that remains a gameplay acceptance check.

## Collision, LOS, and visibility occlusion

- Floor has no collision or light occlusion.
- The complement of rooms/connectors/dynamic portal underlays is a solid wall.
- Row `y=28` remains solid between the Yard and west service hall. This prevents
  a floor seam from bypassing the reception gate on the way to the Locker Room.
- The map boundary is closed.
- Static walls and listed internal cabinets use the existing
  `World | PlayerVisionBlocker` collision contract and matching TileSet light
  occlusion.
- Closed security doors block movement, Guard/CCTV LOS, Player information
  visibility, and light. Open doors pass all four.
- Active lasers detect the live Player but do not block Guard LOS or light.
- Glass observation windows remain physically solid but allow Guard/CCTV LOS
  and light. They require a separate glass collision layer and must not be
  generated as an ordinary wall tile.
- Decorative floor and wall details never own collision.

Internal solid props are kept against room edges or in short islands so every
mandatory route remains at least two cells wide. Server aisles and Electrical
cabinet rows are staggered; they do not form an unbroken wall across a room.

## Intended progression

### No-Recall route

1. Observe the two Yard routes, pass Reception, and follow the Staff clue to
   `keycard_level_1_01` in the Locker Room.
2. Use Level 1 to hack CCTV (recommended) and the Electrical laser network.
3. Enter the Security Office with Level 1 and take `keycard_level_2_01`.
4. Choose one authorization route: Research biometric (shorter, more exposed)
   or Server override (longer hack, stronger aisle cover).
5. Cross the disabled Laser Corridor, pass the Level 2 antechamber checkpoint,
   and open the vault with the acquired authorization.
6. Take the Chronos Core. Use the service lift and south Extraction Route to
   return to the yard extraction marker.

### Alternate and Recall-assisted routes

- CCTV is optional: deterministic camera sweeps leave a no-alert route through
  Staff and Electrical.
- The hidden Maintenance Passage, discovered in the Security Office, links the
  central systems wing to the extraction route and provides a faster retreat.
- Research biometric and Server override are an OR branch; neither is placed
  behind the other.
- A Recall-created Echo can draw the Office, Research, or Antechamber Guard
  away from an interaction pocket, but does not grant access or complete Core
  theft.
- A perfect completion uses zero Recalls. The expected first success uses one
  to three charges for recovery or distraction.

## Objective dependency audit

The blueprint's topological order is:

```text
infiltrate
→ acquire_level_1
→ {neutralize_or_bypass_cctv, disable_lasers, acquire_level_2}
→ acquire_vault_authorization (Research OR Server)
→ enter_vault
→ steal_chronos_core
→ extract
```

No card, terminal, or authorization is placed behind the door it unlocks. The
Core requires `laser_network_offline`, `vault_authorized`, and an open final
vault door. Extraction requires `chronos_core_stolen`.
