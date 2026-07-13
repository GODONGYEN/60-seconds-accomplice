# Sixty-Second Accomplice

**60초의 공범** is a 2D top-down time-loop puzzle game: record an infiltration, then cooperate with the Ghost that replays it. The compact regression prototype uses 20 seconds; the facility mission uses a 60-second loop.

> **한국어 안내:** 60초 facility mission에서 과거의 내가 경비를 유인하고 압력판을 유지하는 동안, 현재의 나는 벽에 몸을 숨겨 laser를 해제하고 시간 코어를 훔쳐 탈출합니다. 20초 prototype은 회귀 검증용으로 함께 보존됩니다.

## Play in your browser

[Play the current `main` deployment on GitHub Pages](https://godongyen.github.io/60-seconds-accomplice/). GitHub Actions builds and deploys this URL; check the repository's Actions page for the revision and deployment result rather than assuming a local change is already live.

<!-- Replace this block with a compressed gameplay GIF or screenshot after capture. -->
> Gameplay screenshot/GIF placeholder: a Ghost drawing the center Guard into lower operations while the live player approaches the laser room through wall-shadowed corridors.

## The core mechanic

The facility mission reconstructs an AI-generated map reference as an authored `26×25` TileMap at `32 px` per cell. It contains one Guard, a lower-left pressure plate linked to the upper-left vault door, a right-room terminal linked to a laser trigger, the time core, and a courtyard exit.

1. Start safely in the lower-right courtyard.
2. Record a first timeline that draws the center Guard west and ends on the vault pressure plate. Being caught still saves the run.
3. Your previous run returns as a translucent Ghost and repeats the distraction and plate occupancy.
4. While walls hide the live Player's route, activate the laser terminal on the right.
5. Cross the disabled laser and the door held open by the Ghost.
6. Collect the time core and return to the active courtyard exit before 60 seconds expire.

Movement and facing are recorded as 20 Hz snapshots. Successful interactions are recorded as timestamped events using stable object IDs. Ghosts interpolate the snapshots against the timeline clock instead of re-simulating player physics.

The Guard follows a deterministic authored patrol, checks distance, view angle, and wall or closed-door occlusion, and raises suspicion before giving chase. Both the live player and active Ghost recordings are visible to it, with the live player taking priority when both are exposed. Capture finalizes the current recording, so a failed approach can become the next timeline's distraction.

Facility darkness combines `CanvasModulate`, one Player-centered shadow light, TileSet wall occluders, and a dynamic door occluder. A separate physics probe hides wall-blocked Guards, Ghosts, stateful objects, indicators, prompts, and Guard HUD data without stopping their simulation. The original `824×807` reference is source-only and is never used as a giant gameplay background. See [the visibility system](docs/visibility_system.md) and [facility layout](docs/maps/facility_level_01_layout.md).

## Controls

| Input | Action |
|---|---|
| <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> or arrow keys | Move |
| Mouse | Face the pointer |
| <kbd>E</kbd> | Interact |
| <kbd>R</kbd> | Finish the current loop and restart |
| <kbd>Esc</kbd> | Pause or resume |
| <kbd>F11</kbd> | Toggle fullscreen |
| <kbd>M</kbd> | Mute or unmute |

In a browser, click the game once before using the keyboard. If the tab loses focus, return to it and click the game again. See [docs/controls.md](docs/controls.md) for details.

## Requirements

- [Godot Engine 4.7 stable](https://godotengine.org/download/archive/4.7-stable/) (standard GDScript build, not Mono)
- Git, for source control
- Python 3, for the reproducible art pipeline and local Web smoke server

The project uses the Compatibility renderer, a 1280×720 reference viewport, responsive 16:9 stretching, and a single-threaded Web export. No account, server, secret, analytics SDK, or network access is required to play.

The project and workflows pin Godot `4.7.stable.official.5b4e0cb0f`. A local executable should report that version before validation; this requirement does not imply that the current unpushed working tree or its browser rendering has passed CI.

## Run locally

Clone the repository, then open the project in the editor:

```bash
git clone https://github.com/GODONGYEN/60-seconds-accomplice.git
cd 60-seconds-accomplice
godot --editor --path .
```

If the executable is named `godot4`, substitute that name in every command. On macOS, the executable inside a downloaded app bundle can also be used directly.

For a headless boot:

```bash
godot --headless --path . --import
godot --headless --path . --quit
```

## Art asset pipeline

The committed player, Ghost, guard, and facility art is derived from project-supplied AI-generated concept sheets. Gameplay never loads a concept sheet or preview directly: Godot resources reference only the normalized atlases under `assets/sprites/`.

Create an isolated tools environment and reproduce every derivative:

```bash
python3 -m venv .tools/venv
.tools/venv/bin/python -m pip install --requirement requirements-tools.txt
.tools/venv/bin/python tools/asset_pipeline.py inspect
.tools/venv/bin/python tools/asset_pipeline.py process-all
```

Validate committed derivatives without rewriting them:

```bash
.tools/venv/bin/python tools/asset_pipeline.py validate
```

The tool verifies immutable source hashes, real RGBA transparency, 48×64 character frames with a `(24, 62)` bottom-center pivot, frame metadata, SpriteFrames/TileSet agreement, and the runtime-only asset boundary. Individual commands are also available: `process-player`, `process-guard`, and `process-tileset`.

CI additionally compares `fingerprint` output before and after `process-all`, so stale generated assets fail without relying on PNG compression bytes being identical across operating systems.

See [docs/art_pipeline.md](docs/art_pipeline.md) for setup, extraction, replacement, and validation details; [docs/asset_manifest.md](docs/asset_manifest.md) for exact frame counts and fallbacks; and [docs/art_direction.md](docs/art_direction.md) for the scale and palette contract.

## Run tests

The test harness uses Godot itself and does not require a third-party test add-on:

```bash
GODOT_BIN=godot tools/run_tests.sh
```

The wrapper rejects parser/load failures and requires the harness PASS marker because some Godot CLI script-load failures can still return exit code zero. Set `GODOT_BIN=godot4` when needed. Test failures must not be converted to skips to make CI pass. A complete local logic/resource pass is:

```bash
godot --headless --path . --import
.tools/venv/bin/python tools/asset_pipeline.py validate
GODOT_BIN=godot tools/run_tests.sh
godot --headless --path . --quit
```

These commands can validate facility topology, collision/occlusion resources, LOS decisions, resets, and the preserved 20-second prototype. They cannot certify `PointLight2D` shadow pixels. After Web export, serve it over HTTP and inspect closed/open doors, corners, hidden Guard/Ghost indicators, responsive viewports, and the browser console as described in [docs/visibility_system.md](docs/visibility_system.md).

## Export for Web

Install the matching Godot 4.7 stable export templates, then run:

```bash
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
bash tools/copy_notices.sh build/web/licenses
test -f build/web/index.html
python3 -m http.server --directory build/web 8000
```

Open [http://localhost:8000/](http://localhost:8000/) rather than loading `index.html` through `file://`. The generated `build/` directory is intentionally ignored by Git.

## Export desktop development builds

The desktop presets are unsigned development builds:

```bash
mkdir -p build/windows build/linux build/macos
godot --headless --path . --export-release "Windows Desktop" build/windows/Sixty-Second-Accomplice.exe
godot --headless --path . --export-release "Linux" build/linux/Sixty-Second-Accomplice.x86_64
godot --headless --path . --export-release "macOS" build/macos/Sixty-Second-Accomplice.zip
bash tools/copy_notices.sh build/windows/licenses
bash tools/copy_notices.sh build/linux/licenses
```

Unsigned macOS builds can trigger Gatekeeper. No signing or notarization is claimed without a configured Apple signing identity.

## Publish with GitHub Pages

The repository includes `.github/workflows/deploy-pages.yml`, which exports `build/web/index.html`, uploads the directory as a Pages artifact, and deploys it with GitHub's official actions.

1. Push the repository to GitHub with `main` as the default branch.
2. Open **Settings → Pages**.
3. Under **Build and deployment**, choose **GitHub Actions** as the source.
4. Run **Deploy GitHub Pages** from the Actions tab, or push to `main`.
5. Confirm the deployed game at the play link above.

See [docs/release.md](docs/release.md) for CI, release, artifact, and troubleshooting details.

## Current status

This repository contains two level scopes on the same deterministic timeline architecture:

- the preserved `30×16`, 20-second prototype for fast recording/Ghost/Guard/puzzle regression;
- `facility_level_01`, an authored `26×25`, 60-second mission with one four-point center Guard, a plate-controlled vault door, terminal-controlled laser, objective, courtyard exit, bounded camera, and wall-based rendered/information visibility.

The live player and Ghost share a directional animated sprite set; the Guard has patrol, suspicion, chase, search, return, line-of-sight, capture, and deterministic reset behavior without combat or health systems. Facility geometry comes from TileMap layers and independent stateful scenes, never from the full source reference image.

Known limitations:

- One facility mission plus one regression prototype; there are no additional enemy types, hearing simulation, combat, campaign, progression, or procedural generation.
- Facility runtime uses one Guard on a four-point center route. A second route is documented but intentionally disabled pending multi-Guard acceptance.
- Guard movement uses deterministic collision-aware steering for compact authored straight segments rather than a general navigation mesh, and the readable vision cone is not geometrically clipped against wall silhouettes.
- Player light is radial rather than persistent fog-of-war. Actor reveal uses one sample point at a 20 Hz refresh, and Compatibility-renderer shadow output still requires browser screenshot review; headless tests cannot prove that rendered shadows are leak-free.
- Recordings live only for the current level session and are not saved to disk.
- Keyboard and mouse are the primary input devices; mobile touch controls are out of scope.
- Desktop artifacts are unsigned development builds.
- Character interaction/alert cycles and the seamless facility base still use documented prototype fallbacks; the original AI concept sheets and map reference are not production-ready tiles or a runtime background.

See [docs/roadmap.md](docs/roadmap.md) for the deliberately narrow next steps.

Guard state, perception, target priority, capture, reset, patrol authoring, and debug behavior are documented in [docs/guard_ai.md](docs/guard_ai.md).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Bug reports should include the browser or OS, commit, reproduction steps, logs, and visual evidence when possible. Large features should begin with an issue so they do not compromise replay determinism or MVP scope.

## License and third-party notices

Project-authored code and content are available under the [MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the Godot Engine notice, build-only dependencies, AI-source disclosure, and the current no-external-authored-assets statement.
