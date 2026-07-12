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

## Interaction rules

The interaction prompt appears only when a valid object is in range. Pressing <kbd>E</kbd> records an event only after an interaction succeeds. The recording stores the target's stable object ID, never its scene-tree path.

Pressure plates are occupancy triggers rather than <kbd>E</kbd> interactions: the live player and Ghosts activate a plate while standing on it. Objective collection and level completion are restricted to the live player.

## Timeline controls

Pressing <kbd>R</kbd> is an intentional loop finish, not a full session reset. The completed run becomes another Ghost unless the recording limit has been reached. The timer and all playback clocks stop while paused. Victory freezes the timeline and prevents a simultaneous timeout from starting another loop.

## Browser focus

Browsers require a user gesture before fullscreen or audio can be controlled. On first load:

1. Click inside the game.
2. Use the controls above.
3. If the tab or window loses focus, return and click the game again.

The game clears live movement when focus is lost so a released key cannot leave the player moving. Browser shortcuts may take precedence over game input on some systems; fullscreen can also be exited with the browser's standard shortcut.

## Accessibility and presentation defaults

- Important states use text, shape, and brightness in addition to color.
- The live player is bright and opaque; Ghosts are translucent and labeled.
- Closed/active door, plate, objective, and exit states remain visually distinct when muted.
- Countdown urgency is visible; audio is never the only timer cue.
- Flashing and screen shake are kept minimal.
- UI anchors and containers keep text inside the viewport as the browser resizes.

Keyboard and mouse are the primary supported devices for this MVP. Rebinding UI, controllers, and touch controls are not part of the current scope.
