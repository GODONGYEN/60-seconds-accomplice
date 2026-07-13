# Chrono Recall

## Player-facing rule

Chrono Recall rewinds up to the last ten seconds of the current branch. The restored Player takes a new action while the abandoned movement and eligible interactions replay once as an **Echo**.

Defaults:

| Setting | Value |
|---|---|
| Input | `Q` |
| Charges | 3 per mission start |
| Rewind duration | up to 10 seconds |
| Sampling | 20 Hz |
| Maximum Echoes | 3 |
| Capture policy | explicit Recall/checkpoint choice |

The operation is completable without Recall. Recall is recovery and improvisation, not a mandatory key.

## Bounded branch history

`RecallHistory` stores recent typed transform samples and timestamped stable-ID events. It does not keep an unlimited recording of the full mission.

- timestamps are monotonic;
- samples/events are deep-copied into segments;
- events at the same timestamp preserve stable insertion order;
- future or out-of-order event insertion is rejected;
- empty/too-short history cannot create a Recall.

After every Recall, the old bounded history is discarded and a new branch begins. A later Recall cannot cross an earlier Recall boundary.

## Monotonic world time

Recall restores world state to a historical snapshot but deliberately keeps the mission clock monotonic.

```text
world time 31s, restore snapshot representing 21s state
→ world state resembles 21s
→ new branch still starts at monotonic 31s
→ Echo plays the abandoned 21–31s segment
```

This avoids event-order reversal and makes Echo scheduling independent of a clock that jumps backward.

## Snapshot registry

`RewindStateRegistry` discovers or registers objects with a stable Recall ID and value-only contract:

```gdscript
func get_recall_state_id() -> StringName
func capture_recall_state() -> Dictionary
func restore_recall_state(snapshot: Dictionary) -> bool
```

Restore order is deterministic. Empty/duplicate IDs, missing methods, incomplete snapshots, and embedded Object references are errors. Snapshots are deep-copied so later mutation does not corrupt history.

## Rewindable state

- live Player position, rotation, velocity, facing, inventory/objective indicator;
- mission objective graph and Core-carried state;
- access tier and credential sources;
- cards, doors, terminals;
- CCTV/laser/alert state;
- Guards: transform, state, target/suspicion/timers/patrol position;
- cameras: sweep/detection state;
- Core and extraction activation;
- operation discovery/tutorial flags.

## Mission-persistent state

- spent Recall charge;
- current monotonic world time;
- Echo sequence and three-Echo cap;
- branch boundary.

Charge consumption occurs before restore and is not part of a rewindable snapshot. A failed restore is reported rather than silently pretending the Recall succeeded.

## Recall transaction

```text
request
→ verify RUNNING, simulation enabled, charge, history, snapshot
→ build abandoned LoopRecording
→ enter RESTORING
→ spend charge
→ restore registered world state
→ restore Player state
→ spawn/configure Echo
→ start new bounded branch
→ resume RUNNING
```

During restore, live gameplay input and detector simulation are gated by the operation. This prevents capture/restart callbacks from entering the transaction twice.

## Echo policy

Echoes share Player SpriteFrames, use translucent cyan presentation, do not collide with the live Player, and interpolate recorded transform samples against their playback time.

Echoes may:

- draw Guard and CCTV attention;
- occupy compatible pressure plates;
- replay explicitly allowed door/terminal interactions.

Echoes may not:

- collect cards;
- grant or transfer access;
- collect the Chronos Core;
- complete extraction;
- trigger lasers as a captured live Player;
- create another Recall.

When a fourth Echo would spawn, the oldest Echo is hidden, detached from active bookkeeping, and queued for deletion before the new one is added.

## Capture integration

Capture sets a re-entry guard, disables simulation, and asks `MissionDirector` to enter `CAPTURE_DECISION`.

- if Recall is available, the HUD offers `RECALL` and `CHECKPOINT`;
- if unavailable, checkpoint restart remains available;
- Recall is never spent automatically;
- successful restore resumes the same mission branch;
- checkpoint restart resets the whole operation and all three charges.

## Core and checkpoint policy

Core ownership is rewindable. A Recall to before theft can return the Core to its pedestal and deactivate extraction. The MVP does not create a post-Core checkpoint, so capture without a usable Recall restarts from mission start even during extraction.

## Validation

Tests cover bounded retention, exact event ordering, immutable segment data, actor/world restore, Object-reference rejection, charge persistence, branch isolation, Echo playback/cap cleanup, pause gating, capture integration, and repeated reset safety.

Known limitation: there is no disk persistence for Recall history or mission state.
