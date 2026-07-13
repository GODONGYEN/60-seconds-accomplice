# Controls and Browser Input

All gameplay input uses Godot Input Map actions. Gameplay scripts do not inspect physical key constants directly.

## Operation: Black Minute

| Input | Action | Result |
|---|---|---|
| <kbd>W</kbd> or <kbd>↑</kbd> | `move_up` | Move north |
| <kbd>S</kbd> or <kbd>↓</kbd> | `move_down` | Move south |
| <kbd>A</kbd> or <kbd>←</kbd> | `move_left` | Move west |
| <kbd>D</kbd> or <kbd>→</kbd> | `move_right` | Move east |
| Mouse movement | pointer position | Face the pointer |
| <kbd>E</kbd> | `interact` | Use a nearby visible valid card, door, terminal, or Core |
| <kbd>Q</kbd> | `chrono_recall` | Spend a charge and restore up to ten seconds when available |
| <kbd>M</kbd> or <kbd>Tab</kbd> | `open_map` | Open/close the tactical map with simulation paused |
| <kbd>Esc</kbd> | `pause` | Close map or pause/resume the operation |
| <kbd>F11</kbd> | `toggle_fullscreen` | Toggle fullscreen through the application controller |
| <kbd>V</kbd> | `toggle_mute` | Mute/unmute the Master bus globally |

`R` full-loop restart is intentionally disabled in the formal mission. Use the pause menu to restart the mission, or choose checkpoint after capture.

`AppController` owns fullscreen and mute while the application launcher is present, so the same shortcuts work in the menu, briefing, formal operation, and both regression sessions. A legacy `GameManager` launched as a standalone scene retains its local handlers; when embedded it delegates to the application owner, preventing one key press from toggling twice.

## Regression modes

| Input | Action | Result |
|---|---|---|
| movement / mouse / <kbd>E</kbd> | same actions | Move, face, interact |
| <kbd>R</kbd> | `restart_loop` | Finalize current recording and begin the next full loop |
| <kbd>Esc</kbd> | `pause` | Pause/resume |
| <kbd>F11</kbd> | `toggle_fullscreen` | Toggle fullscreen |
| <kbd>V</kbd> | `toggle_mute` | Mute/unmute Master bus |

The 20-second prototype and 60-second facility use the same action names but keep their own full-loop lifecycle.

## Movement

Diagonal input is normalized. Character movement is independent from sprite animation. The live Player uses a lower-body collision shape; Player and Echo do not collide with each other.

When gameplay input is disabled for pause, map, capture decision, Recall restore, reset, or victory, movement velocity is cleared so a released key cannot remain stuck.

## Interaction

The prompt appears only when a stable interactable is in range and visible. A successful interaction is recorded with stable target ID and minimal payload; a failed or denied interaction is not treated as completed.

- cards and Chronos Core: live Player only;
- doors: access and mission-condition check;
- terminals: hold/interaction completion, with explicit Echo replay policy;
- pressure plates: actor occupancy, no `E` input;
- extraction: live Player with Core only.

## Chrono Recall

Recall is available only when:

- operation is active and simulation is running;
- at least one charge remains;
- recent history and a valid world snapshot exist;
- map/pause/restore is not blocking input.

Immediately after mission start or a prior Recall, the available history can be shorter than ten seconds. The ability restores as far as valid current-branch history allows. Used charges do not return.

On capture, `Q` can select Recall when the decision panel offers it; the HUD button provides the same action. Recall is never automatic.

## Tactical map

Opening the map pauses Player, Guards, cameras, alert decay, and Recall history. It shows planning information without showing a solved path or real-time Guard locations. Closing it resumes unless a separate pause/capture/victory state is active.

## Stealth feedback

- neutral/cyan cone and `PATROL`: authored route;
- orange `?`: suspicion/investigation;
- red `!`: confirmed chase/alert;
- search/return labels: target lost and route recovery;
- Security HUD: CCTV, lasers, facility alert;
- Access HUD: current tier;
- Recall HUD: remaining/maximum charges;
- Core HUD: acquired state.

Actual detection uses physics LOS and close proximity in addition to the readable cone.

## Browser focus

Browsers require a user gesture before keyboard focus and some platform features work.

1. Click inside the game.
2. Use the controls above.
3. If the tab loses focus, return and click the canvas again.

During Operation: Black Minute, focus loss also opens the safe pause state: Player, Guards, CCTV, Recall history, alert decay, and in-progress hacks stop until the player explicitly resumes. Capture and victory modals retain ownership instead of being replaced. Browser shortcuts can take precedence over game actions. Always validate a Web build through a local HTTP server, not `file://`.

## Accessibility

- important state uses text/icon/shape in addition to color;
- Player, Echo, Guard, objective, and extraction use distinct silhouettes/brightness;
- muted play retains capture, objective, alert, and extraction feedback;
- flashing and screen shake are minimized;
- responsive containers are intended for the 1280×720 reference and resized windows.

Keyboard and mouse are the primary supported devices. Controller rebinding and touch controls are not implemented.
