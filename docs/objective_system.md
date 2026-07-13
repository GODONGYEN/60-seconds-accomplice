# Objective System

## Purpose

The formal mission uses explicit objective state rather than one mutable HUD sentence. `MissionDirector` translates semantic mission events into an `ObjectiveGraph`; HUD and tactical map are read-only consumers of the resulting actionable objective list.

## States

```text
LOCKED → AVAILABLE → ACTIVE → COMPLETED
                         └──→ FAILED
```

- `LOCKED`: prerequisites are not met;
- `AVAILABLE`: prerequisites are met but the objective is not yet selected for display;
- `ACTIVE`: currently actionable and eligible for completion;
- `COMPLETED`: terminal state, emitted once;
- `FAILED`: reserved terminal state for authored failure rules.

Completion from an invalid state is rejected with a warning. Repeated signals cannot silently complete the same objective twice.

## Graph rules

Each objective has:

- stable `StringName` ID;
- player-facing title;
- `all_of` prerequisites;
- optional `any_of` prerequisites;
- optional flag;
- deterministic insertion/topological order.

`ObjectiveGraph.validate()` rejects missing prerequisite IDs and cycles. The standalone mission validator also checks the blueprint topological order and catches reversed dependencies.

## Operation graph

```text
Infiltrate
└── Acquire Level 1
    ├── Disable CCTV (optional)
    ├── Disable lasers
    ├── Acquire Level 2
    │   ├── Biometric authorization (optional source)
    │   └── Server override (optional source)
    └────────────┬───────────────────────────────
                 └── Vault authorization (ANY source)

Disable lasers + Level 2 + Vault authorization
→ Enter vault
→ Steal Chronos Core
→ Extract
```

CCTV disable is not a mandatory gate because camera avoidance is a supported no-hack route. Laser disable, Level 2, and one Vault source are mandatory.

## Semantic event boundary

World objects do not set graph fields directly.

```text
card/terminal/trigger/Core/extraction event
→ OperationBlackMinuteLevel handler
→ MissionDirector.report_event or request_extraction
→ ObjectiveGraph state transition
→ objective signal
→ HUD/map update
```

Examples:

| Event | Objective effect |
|---|---|
| `facility_entered` | complete infiltration |
| `level_1_acquired` | complete Level 1 |
| `cctv_disabled` | complete optional CCTV objective |
| `laser_disabled` | complete mandatory laser objective |
| `level_2_acquired` | complete Level 2 |
| `server_override` or `biometric_authorization` | complete one source, then Vault authorization |
| `vault_entered` | complete vault entry |
| `chronos_core_stolen` | set Core carried and unlock extraction objective |
| extraction request | complete mission only when Core is carried |

## Recall behavior

Objective graph state and Core-carried state are rewindable value snapshots. Recall may undo an objective completed inside the abandoned segment. The Echo replay must still pass normal state checks; it cannot duplicate a terminal completion or collect the Core.

Mission completion is never emitted merely because a completed snapshot is restored. The current implementation prevents further Recall after victory by stopping mission simulation.

## Reset behavior

Mission-start checkpoint calls `MissionDirector.reset_mission()`, reinitializes the graph, clears Core ownership, then calls `begin_mission()` to activate the first valid objectives.

## Validation and tests

Tests should cover:

- initial active/actionable set;
- all-of and any-of prerequisites;
- optional CCTV not blocking Core progression;
- repeated completion safety;
- cycle and missing-ID rejection;
- Recall restore without duplicate completion;
- extraction before/after Core;
- full reset.
