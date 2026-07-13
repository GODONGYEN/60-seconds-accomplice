# Onboarding

## Goal

A first-time player should know the target, the broad security plan, and the escape point before movement starts. Guidance appears in context and does not reveal one mandatory solved route.

## 1. Main menu

`NEW OPERATION` and `OPERATION: BLACK MINUTE` lead to the formal mission. `PROTOTYPE LAB` and `FACILITY 01` are labeled regression/developer modes so players do not mistake them for campaign missions.

`HOW TO PLAY` summarizes planning, credentials, surveillance, lasers, map, and Recall. Settings explain pause/fullscreen/mute and non-color feedback.

## 2. Mission briefing

The briefing appears before control and shows:

- operation and facility names;
- Chronos Core as the primary target;
- approximate target and extraction regions;
- named facility rooms and major connectors;
- CCTV, Level 2 doors, laser corridor, and Vault authorization;
- preparation checklist;
- three Recall charges and ten-second duration;
- `START MISSION`.

The first formal mission path does not skip this screen automatically.

## 3. Spawn

Initial HUD:

```text
PRIMARY
STEAL THE CHRONOS CORE

CURRENT
Enter the reception checkpoint

OPEN THE TACTICAL MAP WITH M
```

The external yard gives enough safe space to read the HUD and open the map before entering Guard coverage.

## 4. Reception and Guard awareness

The first infiltration trigger introduces two rules:

- avoid visible Guard cones;
- very close proximity can be noticed in 360°, even behind a Guard.

The cone, suspicion icon, state text, and alert HUD reinforce the message without relying on color alone.

## 5. First locked door

Door prompts name the required access tier. The active objective directs the player to the locker-room Level 1 card. Optional staff intel reinforces that clue.

The map shows room names and access-door requirements but not the exact solved route.

## 6. CCTV

On first camera alert, the game explains that cameras can send nearby Guards to the last-seen location. The CCTV control room is visible on the map. Players may disable the network or learn its deterministic sweep.

## 7. Lasers

The laser corridor and door feedback state that the network must be disabled from electrical. Laser contact produces the same understandable capture decision as a Guard; it is not an unexplained instant game over.

## 8. Chrono Recall

The HUD always shows remaining charges. The first useful Recall context explains:

```text
Chrono Recall restores up to the last 10 seconds.
The abandoned route remains as an Echo.
Charges are limited and do not rewind.
```

Capture never spends a charge automatically. The decision panel describes Recall and keeps the checkpoint option visible.

## 9. Vault and extraction

Current objectives communicate:

- Level 2 acquisition;
- server OR biometric authorization;
- laser offline requirement;
- Core theft;
- return to extraction.

Core theft changes the Core HUD from `NOT ACQUIRED` to `SECURED`, raises lockdown, opens the extraction route, and displays a return instruction.

## Tactical map policy

`M` or `Tab` opens the map and pauses simulation. It may display:

- current Player position;
- room names and connectors;
- objective region and extraction;
- door tiers;
- CCTV/laser online state;
- discovered maintenance passage.

It does not show a perfect route or live Guard positions by default.

## Accessibility

- status uses text, shape, icons, meters, and brightness in addition to color;
- Player, Echo, and Guard silhouettes remain distinct;
- critical capture/Core/extraction information remains visible when muted;
- containers and anchors support 1280×720 and resized browser windows;
- flashing and screen shake are minimized.

## Current limits

Tutorial-message replay settings, controller prompts, localization beyond selected Korean labels, voiceover, and a persistent “skip briefing” preference are not implemented.
