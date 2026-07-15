# Access Control

## Access tiers

`AccessControlManager` tracks the live Player's highest physical/derived access tier.

```text
PUBLIC (rank 0)
→ LEVEL 1 (rank 1)
→ LEVEL 2 (rank 2)
→ VAULT (rank 3)
```

It also stores the stable source IDs of collected credentials. Granting the same source twice is idempotent.

## Physical cards

| Card | Location | Grants | Circularity rule |
|---|---|---|---|
| `keycard_level_1_01` | Locker Room | Level 1 | room is Public |
| `keycard_level_2_01` | Security Office | Level 2 | room requires at most Level 1 |

Only the live Player may collect cards. Echoes cannot collect, carry, transfer, or grant credentials.

Cards use an elevated `L1`/`L2` beacon, tier color, and notched silhouette so a
pickup remains readable when the Player stands directly over it. The tactical
map highlights the current credential's room without drawing a solved route.

## Vault authorization

Vault access is derived from either:

- `terminal_server_override_01`; or
- `terminal_research_biometric_01`.

The completion logic is `ANY`. Both sources are reachable through the Level 2 sector and neither requires Vault access. A source used before its objective unlocks is retained as a pending fact, but it does **not** grant the Vault tier early. `VAULT` access is granted only when the authorization objective actually completes after the full prerequisite chain reconciles.

## Door authorization

An `AccessDoor` combines two checks:

1. `current_level >= required_access`;
2. all authored mission flags are satisfied.

Examples of additional flags:

- `laser_network_offline`;
- `vault_authorized`;
- `maintenance_passage_discovered`;
- `chronos_core_stolen`.

When a door opens, movement collision, Guard/camera LOS blocking, Player visibility blocking, and light occlusion are disabled together. Reset closes doors to their authored initial state.

A closed door remains a valid live-Player interaction target when access is
missing. Authorization is resolved by `interact()`, so a real `E` press emits one
typed, reason-bearing access-denied cue instead of being discarded during preflight
or duplicated through the access manager. Conditional door
prompts are evaluated live: after the laser network goes offline, the Vault prompt
advances to the remaining authorization requirement. The maintenance door keeps
its physical/LOS/light blocker but hides only its presentation and interaction
surface until map intel discovers it; checkpoint reset and Recall restore that
discovery state.

Echo door replay is deliberately narrower than live authorization. An Echo may
replay a permitted previously authorized interaction only when that door is also
discovered in the restored branch. It does not gain or transfer access and cannot
satisfy a missing current mission flag by itself.

## Recall and checkpoint

Access tier, credential dictionary, card world visibility, and door state are rewindable. A Recall to before card collection restores both inventory and the card's world state.

Consumed Recall charges are outside `AccessControlManager` and remain spent. Mission-start checkpoint clears all credentials and returns access to `PUBLIC`.

## Solvability rules

The validator rejects:

- an access card placed behind its own tier;
- unknown access labels on portals;
- Vault authorization sources requiring Vault;
- the laser shutdown terminal placed behind the active laser corridor;
- a Vault door missing the required authorization flag;
- inaccessible required object rooms.

These checks protect progression structure; they do not certify moment-to-moment patrol difficulty.
