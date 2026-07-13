# Security Systems

## Ownership

`SecuritySystemManager` owns network and alert state. Cameras, lasers, doors, terminals, and Guards keep their local behavior and communicate through typed signals and manager APIs.

```text
camera/Guard/laser observation
→ SecuritySystemManager
→ zone alert and facility alert
→ GuardZoneManager
→ deterministic local/adjacent Guard response
→ HUD/map status
```

## CCTV network

The operation spawns eight cameras from the mission blueprint. Each camera has a stable ID, zone, facing, sweep half-angle, angular speed, start phase, vision distance, and vision half-angle. `start_phase_seconds` advances the triangular sweep itself from the center-facing pose; it is not merely a detection-query stagger.

Detection requires:

- network online;
- detectable Player or Echo candidate;
- candidate inside range and view angle;
- unobstructed physics line of sight;
- threshold exposure time.

Walls and closed access doors block camera LOS. Open doors do not. If the live Player and an Echo are both visible, the live Player receives deterministic priority.

Threshold detection raises a zone alert at the last-seen position. `GuardZoneManager` forwards it to bounded local and adjacent response Guards. Cameras do not directly rewrite Guard state fields.

The CCTV control terminal disables the entire network. Offline cameras stop active sweep/detection and update HUD/map state. Network state, phase, and local exposure state are Recall snapshots and mission-reset state.

## Laser network

Three vertical barriers guard the vault approach. Lasers are triggers rather than movement walls.

- live Player contact while online: raise an alerted zone event and request capture;
- Echo contact: ignored;
- Guard LOS and Player light: not blocked;
- electrical terminal completion: disable all barriers.

Laser offline is mandatory for the vault/Core progression. Laser state is rewindable and returns online at mission-start checkpoint.

## Facility alert

```text
CLEAR → SUSPICIOUS → ALERTED → LOCKDOWN
```

- `CLEAR`: no active facility concern;
- `SUSPICIOUS`: local investigation or camera warning;
- `ALERTED`: confirmed Guard/laser response;
- `LOCKDOWN`: Core theft/extraction phase.

Normal alert levels decay after a configured period without detection. `ALERTED` drops to `SUSPICIOUS`, then zone alerts clear and the facility returns to `CLEAR`. `LOCKDOWN` does not decay in the current mission.

Alert level is global presentation/state; movement response remains zone-bounded. One camera does not make every Guard chase the Player forever.

## Doors and blockers

Closed access doors synchronize four gameplay boundaries:

- CharacterBody collision;
- Guard and camera LOS;
- Player information visibility;
- light occlusion.

Opening a door disables all four. This avoids a visually open door that still blocks detection or a visually closed door that leaks hidden information.

## Guard perception

Guards use cached candidates and test:

1. target eligibility;
2. distance;
3. facing dot product / half-angle;
4. physics LOS;
5. close-proximity awareness;
6. mission/pause/restore gate.

Vision cones communicate approximate range and direction. Physics LOS and proximity are authoritative; cone polygons are not clipped into exact wall silhouettes.

## Core theft

Core theft:

- raises `LOCKDOWN`;
- marks the Core as carried;
- activates extraction;
- opens the authored vault-extraction and yard doors;
- does not spawn reinforcements or begin combat.

## Recall and reset

Recall snapshots include CCTV online state, laser online state, facility alert, zone alert payloads, alert decay time, camera transform/phase, and local device state. Restoring these values emits synchronization signals so scene visuals/triggers match manager state.

Mission-start checkpoint restores CCTV and lasers online, clears alerts, resets cameras/Guards, closes authored doors, and clears terminal completion.

## Performance constraints

- no per-frame `get_nodes_in_group()` candidate rebuild;
- camera/Guard target lists are cached and pruned;
- physics queries exclude the detector itself;
- cone geometry is not regenerated every frame;
- alert recipients are bounded by authored zones;
- network state changes update devices by cached arrays.

## Known limits

- no hearing/noise propagation;
- no reinforcements or multiple enemy types;
- no camera destruction, body discovery, combat, or health;
- no dynamically clipped vision-cone mesh;
- no general building-wide alarm pathfinding.
