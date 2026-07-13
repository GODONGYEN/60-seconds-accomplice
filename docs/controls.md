# Controls and Browser Input

## Default controls

All gameplay input is defined through Godot's Input Map. Scripts must query action names rather than physical key constants.

| Input | Input Map action | Result |
|---|---|---|
| <kbd>W</kbd> or <kbd>↑</kbd> | `move_up` | Move up |
| <kbd>S</kbd> or <kbd>↓</kbd> | `move_down` | Move down |
| <kbd>A</kbd> or <kbd>←</kbd> | `move_left` | Move left |
| <kbd>D</kbd> or <kbd>→</kbd> | `move_right` | Move right |
| Mouse movement | pointer position | Face the pointer |
| <kbd>E</kbd> | `interact` | Interact with a nearby valid object |
| <kbd>R</kbd> | `restart_loop` | Finalize the current recording and begin the next loop |
| <kbd>Esc</kbd> | `pause` | Pause or resume |
| <kbd>F11</kbd> | `toggle_fullscreen` | Enter or leave fullscreen |
| <kbd>M</kbd> | `toggle_mute` | Mute or restore game audio |

Diagonal movement is normalized so it is not faster than horizontal or vertical movement. The live player and Ghosts do not collide with one another.

## Stealth feedback

Stealth does not add another input. Watch the Guard's translucent vision cone and status display while moving:

- Cyan cone and `PATROLLING`: the Guard is following its authored route.
- Orange cone and `?`: suspicion is increasing while a target remains visible.
- Red cone and `!`: the Guard is chasing its last confirmed target.
- `SEARCHING`: the Guard lost sight and checks the last seen position before returning.

Walls and a closed security door block actual line of sight; an open door permits it. The cone is a readable range-and-angle guide and is not cut into exact wall silhouettes. The live player has detection priority if the Guard can see both the player and a Ghost, so use walls to keep the live facility route separated while the Ghost repeats the lower-operations distraction.

## Facility visibility

The 60-second facility mission starts in the lower-right courtyard. A dark ambient layer and one Player-centered light reveal nearby floor. Walls and the closed vault door cast light shadows and also suppress information that the rendered shadow alone cannot safely hide:

- a Guard, Ghost, gameplay object, Guard cone, and `?`/`!` indicator behind a wall have alpha gated to zero;
- the HUD reports `GUARD — OUT OF SIGHT` instead of leaking hidden suspicion or target state;
- an <kbd>E</kbd> prompt is shown only when the object is both in interaction range and visible to the Player probe;
- hidden Guard AI and Ghost playback continue to run.

Approaching a doorway reveals valid targets again. Opening the vault door simultaneously removes movement collision, Guard LOS blocking, Player visibility blocking, and its light occluder. The rendered shadow uses Godot's Compatibility renderer and still requires browser visual review; automated LOS tests alone do not certify shadow pixels.

## Interaction rules

The interaction prompt appears only when a valid object is in range. Pressing <kbd>E</kbd> records an event only after an interaction succeeds. The recording stores the target's stable object ID, never its scene-tree path.

Pressure plates are occupancy triggers rather than <kbd>E</kbd> interactions: the live player and Ghosts activate a plate while standing on it. Objective collection and level completion are restricted to the live player.

In `facility_level_01`, use <kbd>E</kbd> at `terminal_laser_01` to disable the right-room laser for the current loop. An active laser detects the current Player and saves/ends the loop; it does not block Guard sight or the Player light. The lower-left pressure plate holds the upper-left vault door open, so a previous Ghost is required to keep it active while the live Player crosses.

## Timeline controls

Pressing <kbd>R</kbd> is an intentional loop finish, not a full session reset. The completed run becomes another Ghost unless the recording limit has been reached. Guard capture or an active facility laser also finalizes the recording at that timestamp; it is time-loop progression, not permanent failure. The prototype loop is 20 seconds and the facility loop is 60 seconds. The timer, Guard AI, recording, playback, and visibility refresh stop with level simulation while paused. Victory freezes the timeline and prevents a simultaneous timeout or capture from starting another loop.

## Browser focus

Browsers require a user gesture before fullscreen or audio can be controlled. On first load:

1. Click inside the game.
2. Use the controls above.
3. If the tab or window loses focus, return and click the game again.

The game clears live movement when focus is lost so a released key cannot leave the player moving. Browser shortcuts may take precedence over game input on some systems; fullscreen can also be exited with the browser's standard shortcut.

## Accessibility and presentation defaults

- Important states use text, shape, and brightness in addition to color.
- The live player is bright and opaque; Ghosts are translucent and labeled.
- Guard suspicion and chase use a meter plus `?`/`!` shapes, not color alone.
- Closed/active door, plate, objective, and exit states remain visually distinct when muted.
- Countdown urgency is visible; audio is never the only timer cue.
- Flashing and screen shake are kept minimal.
- UI anchors and containers keep text inside the viewport as the browser resizes.

Keyboard and mouse are the primary supported devices for this MVP. Rebinding UI, controllers, and touch controls are not part of the current scope.
