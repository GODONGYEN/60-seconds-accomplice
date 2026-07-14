# Mission Performance and Debrief

## Purpose

`Operation: Black Minute` ends with a readable operation report instead of a generic victory message. The report rewards the choices already supported by the mission without adding a leaderboard, persistent grind, random reward, or meta-progression layer.

Elapsed mission time is displayed as a run statistic. It does **not** change score: the current patrol windows have not been playtested broadly enough to make speed a fair mastery requirement.

## Score contract

Every completed extraction starts at `5,000` points. Bonuses are positive-only and the maximum is `10,000`.

| Directive | Condition | Points |
|---|---|---:|
| `SHADOW` | The live Player never reaches a Guard or CCTV detection threshold | +2,000 |
| `TEMPORAL DISCIPLINE` | Complete the operation without Chrono Recall | +1,500 |
| `PARADOX DECOY` | Use Recall and have an Echo actually detected by a Guard or CCTV | +1,500 |
| `UNTOUCHABLE` | No capture decision is triggered during the attempt | +1,000 |
| `BLACKOUT` | The CCTV network is offline at extraction | +500 |

`TEMPORAL DISCIPLINE` and `PARADOX DECOY` are mutually exclusive. This gives the intended no-Recall and useful-Echo play styles the same scoring ceiling. Spending Recall without an observed Echo remains a valid recovery, but it does not earn the Echo mastery directive.

Grades are deterministic:

| Grade | Score |
|---|---:|
| S | 9,500–10,000 |
| A | 8,000–9,499 |
| B | 6,500–7,999 |
| C | 5,000–6,499 |

## Authoritative data

`MissionPerformanceTracker` is a focused value ledger owned by `OperationBlackMinuteLevel`.

- `ChronoRecallManager.get_world_time()` supplies monotonic, pause-safe elapsed time.
- Guard `alert_raised` and CCTV `threshold_reached` signals supply stable actor IDs.
- `player_live` is the live infiltrator; `echo_*` IDs are temporal decoys.
- accepted capture requests increment capture count once, after re-entry guards pass;
- final CCTV/laser state and the actual server/biometric authorization route are sampled at extraction;
- Recall usage is derived from persistent charges spent.

Core-theft `LOCKDOWN` is scripted mission escalation, not a stealth detection, so it never removes `SHADOW` by itself.

## Recall and reset semantics

The performance ledger is intentionally **not** registered as `recall_rewindable`. Detection, capture, and spent Recall consequences survive a Recall along with the monotonic mission clock. This prevents abandoned branches from farming or erasing directives.

Mission-start checkpoint reset and `REPLAY OPERATION` call `begin_mission()` and clear the complete ledger. Finalization is idempotent and returns a recursive deep copy, so duplicate extraction callbacks or UI mutation cannot change the cached result.

## Presentation

The HUD displays:

- a pause-safe `MM:SS` operation clock;
- typed objective, access, security, Recall, Core, and danger cue cards;
- low-alpha one-shot screen washes with no camera shake or repeated flash;
- procedural tones that remain optional under browser autoplay and mute restrictions;
- a final grade, score, elapsed time, Recall use, live/Echo detections, captures, authorization route, and every directive result.

Text, symbols, shape, and brightness accompany color. All critical information remains available with audio muted.
