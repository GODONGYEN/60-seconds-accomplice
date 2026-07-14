# Operation: Black Minute

## Mission card

| Field | Value |
|---|---|
| Operation | OPERATION: BLACK MINUTE / 작전명: 검은 1분 |
| Facility | HELIX TEMPORAL RESEARCH FACILITY / 헬릭스 시간 연구시설 |
| Primary target | CHRONOS CORE / 크로노스 코어 |
| Insertion/extraction | External Infiltration Yard |
| Recall allowance | 3 charges, up to 10 seconds each |
| Formal mission timer | No forced full-mission loop timer |
| Checkpoint | Mission start only |

The default application flow is Main Menu → Mission Briefing → this operation. The briefing cannot be confused with the preserved developer regression levels.

## Facility contract

- grid: 64×42 cells;
- tile size: 32 px;
- world: 2048×1344 px;
- named rooms/spaces: 15;
- Guards: 10;
- Guard response zones: 7;
- CCTV cameras: 8;
- laser barriers: 3;
- dynamic portals: 15;
- declared choke points: 15.

The blueprint and detailed coordinate tables live in [operation_black_minute_blueprint.json](../../resources/maps/operation_black_minute_blueprint.json) and [the layout document](../maps/operation_black_minute_layout.md).

## Security progression

### 1. Infiltrate reception

The player starts in the external yard with enough space to read the HUD and open the tactical map. Opening/crossing the reception checkpoint completes infiltration.

### 2. Acquire Level 1

The Level 1 card is in the locker room, which is reachable with public access. Staff, CCTV, electrical, and security routes then become available through Level 1 doors.

### 3. Handle CCTV

The player can reach the CCTV control room and disable the network, or keep it online and cross camera sweeps using timing and cover. CCTV disable is useful and represented as an optional objective; a perfect stealth route is not forced to hack it.

### 4. Disable laser power

The electrical-room terminal disables all three barriers. This step is mandatory before Core acquisition and vault entry.

### 5. Acquire Level 2

The Level 2 card is in the security office, behind Level 1 rather than behind its own access tier.

### 6. Obtain Vault authorization

Either path is valid:

- temporary server override in the server room; or
- biometric authorization in the research laboratory.

Both paths require reaching the Level 2 sector. Neither is placed behind Vault access.

### 7. Enter the vault

The vault path requires laser offline, Level 2 routing, and Vault authorization. Door interaction, collision, LOS, Player visibility blocking, and light occlusion change together.

### 8. Steal the Core

Only the live Player can collect the Core. Theft sets facility `LOCKDOWN`, activates extraction, and opens the authored extraction doors. Echoes cannot complete this step.

### 9. Extract

Return to `extraction_yard_01` with the Core. Extraction ends simulation and shows the immutable operation report. Both a clean no-Recall route and a clean Recall route whose Echo is actually detected can reach S rank; elapsed time is reported but not scored. See [Mission Performance and Debrief](../mission_performance.md).

## Route contracts

### No-Recall route

The declared route completes every access and security prerequisite with deterministic patrol timing and no Recall. CCTV may be disabled or bypassed. Vault authorization may use either source.

Static validation proves that the required rooms and objects form an acyclic, connected declaration and that safe windows exist. It does not replace a human playthrough or certify route comfort.

### Recall-assisted route

The same acyclic progression applies, but one dangerous segment can be rewound. The abandoned segment becomes an Echo, allowing the live Player to take a different line while Guards and CCTV react to the projection.

Recall is useful for:

- recovering just before capture;
- redirecting a local Guard response;
- crossing a camera/Guard overlap with an Echo distraction;
- retrying a vault approach without restarting the whole operation.

## Capture and checkpoint

Capture freezes mission simulation and presents a decision:

- **Recall** when charge and recent history are available;
- **Checkpoint** to reset the full operation to mission start.

The current MVP has no Core-theft or extraction-phase checkpoint. Checkpoint reset removes Echoes and restores cards, access, doors, terminals, security networks, alert, Guards, Core, extraction, objectives, Recall history, and all three charges.

## Optional information

- staff intel identifies the locker-room card;
- security-map terminal reveals the maintenance passage on the tactical map;
- break-room distraction raises a deterministic local alert;
- the tactical map shows systems and room structure but not a solved route or live Guard positions.

## Completion criteria

- briefing and mission map load;
- all generated runtime population counts match the blueprint;
- security progression is completable without circular access;
- Core cannot be collected early or by an Echo;
- extraction cannot complete without the Core;
- Recall route can restore and continue without duplicate objective completion;
- checkpoint reset returns every mission system to initial state;
- regression modes remain separately playable.

Automated completion evidence and manual browser evidence must be reported separately.
