# Guard Zones and Patrol Scheduling

## Why zones exist

Ten independent Guards should create pressure without becoming a building-wide swarm. The blueprint divides the facility into seven response zones and declares which adjacent zones each Guard may enter during investigation/chase.

| Zone | Intended coverage | Capacity |
|---|---|---:|
| `zone_outer_yard` | infiltration and extraction yard | 2 |
| `zone_reception` | public checkpoint/security approach | 1 |
| `zone_office` | locker and staff offices | 1 |
| `zone_cctv` | break room and CCTV sector | 1 |
| `zone_electrical` | electrical/security links | 1 |
| `zone_research` | server and research sector | 2 |
| `zone_vault` | laser, antechamber, vault, extraction link | 2 |

The exact rectangles, anchors, adjacency, assignments, and choke references are data in the operation blueprint.

## GuardZoneManager

Responsibilities:

- parse and validate zone IDs, rectangles, anchors, capacities, and adjacency;
- validate the declared Guard-to-zone assignment;
- register runtime Guard instances by stable ID;
- find or clamp positions inside home/adjacent chase bounds;
- select deterministic local and adjacent alert recipients;
- retain value-only active zone alerts;
- reset alert state without deleting authored assignments.

It does not own Guard animation, suspicion, movement velocity, or state transitions.

## Alert propagation

```text
source detects target
→ SecuritySystemManager stores zone alert
→ GuardZoneManager gets home + adjacent zone recipients
→ recipient IDs sorted deterministically
→ each valid Guard receives last-seen position/source/zone
→ Guard state machine investigates
```

An unknown zone or Guard ID is reported. Scene-tree order is not used for priority.

## Authored routes

Every Guard has:

- stable Guard ID;
- home zone;
- spawn cell;
- initial facing;
- `LOOP` or explicit route mode;
- 2–4 authored waypoints;
- per-waypoint waits;
- deterministic start phase;
- movement speed;
- allowed chase zones;
- return point and reservation group.

There is no random waypoint selection.

## PatrolScheduler

The scheduler coordinates compact authored routes without pretending that a `NavigationObstacle2D` is a complete dynamic pathfinding solution.

Runtime responsibilities:

- map world positions to 32 px cells;
- register Guard positions;
- collect movement intents;
- resolve intents in stable Guard-ID order;
- deny occupied or already reserved cells;
- enforce choke capacity;
- track blocked duration;
- release stale reservations on unregister/reset.

The Guard keeps collision-aware movement responsibility. A denied reservation delays movement rather than teleporting or pushing another Guard.

## Choke points and fairness

The blueprint declares 15 choke rectangles. Each has:

- capacity;
- waiting/hold cells;
- relevant Guard IDs;
- cycle duration;
- one or more safe windows.

Every declared safe window must be at least 3 seconds. The current blueprint's minimum is 3.5 seconds. This is a data contract for a plausible crossing window, not a guarantee that every first-time player will see it immediately.

## Virtual patrol simulation

`PatrolScheduler.run_patrol_simulation()` performs a fixed-step 180-second simulation twice. It reports:

- Guard count;
- same-cell overlaps;
- choke-capacity violations;
- zone violations;
- deadlocks/maximum blocked time;
- minimum declared safe window;
- simulated choke-capacity-open opportunity count and longest interval;
- trace digest and repeated digest;
- deterministic equality.

The production contract requires 10 Guards and zero overlap, choke-capacity, zone, and deadlock violations. Declared safe windows remain authored design inputs. The separately named simulated capacity-open intervals report when a reservation slot was actually available; they do not claim LOS-safe Player passage. A deterministic virtual pass does not measure rendered FPS or replace manual play.

## Chase and return

Guards may pursue the current visible target only inside that Guard's explicit `allowed_chase_zones`; adjacency is validation authority, not an automatic runtime grant. When sight is lost they move to the bounded last-seen position, search deterministically, then return to the interrupted route or a valid zone return point.

Closed doors block LOS and movement. A Guard does not continuously target a Player behind a closed door: target loss moves the Guard into search/return behavior.

## Reset

Mission-start reset clears:

- active zone alerts;
- scheduler reservations/intents/blocked timers;
- Guard position, facing, state, route index, wait/phase timers;
- suspicion/current target/last seen/search/capture state;
- navigation velocity/target;
- visual indicators.

Runtime Guard registrations and authored assignments remain valid and are rechecked.

## Known limits

- authored straight/compact movement rather than arbitrary navmesh paths;
- no local avoidance crowd simulation beyond reservations and capacity;
- no door-breaching or alternate-route replanning;
- no hearing propagation;
- zone rectangles can overlap by design, so authored home ID remains authoritative.
