# Sixty-Second Accomplice

**60초의 공범** is a 2D top-down time-loop puzzle game: record one 20-second run, then cooperate with the Ghost that replays it.

> **한국어 안내:** 20초 동안의 행동이 다음 회차의 Ghost로 재생됩니다. 과거의 나가 압력판을 누르는 동안 문을 통과하고, 시간 코어를 획득해 탈출하세요.

## Play in your browser

[Play the current MVP on GitHub Pages](https://godongyen.github.io/60-seconds-accomplice/). The deployment is built from `main` by the repository's Pages workflow.

<!-- Replace this block with a compressed gameplay GIF or screenshot after capture. -->
> Gameplay screenshot/GIF placeholder: Ghost on the pressure plate while the live player crosses the open door.

## The core mechanic

1. Move onto the pressure plate during the first timeline.
2. Let the 20-second loop end, or press <kbd>R</kbd> when your setup is ready.
3. Your previous run returns as a translucent Ghost.
4. Cross the door while the Ghost holds the plate.
5. Collect the time core and reach the active exit before the loop expires.

Movement and facing are recorded as 20 Hz snapshots. Successful interactions are recorded as timestamped events using stable object IDs. Ghosts interpolate the snapshots against the timeline clock instead of re-simulating player physics.

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

The local import, test, and export results documented for this revision were produced with `4.7.stable.official.5b4e0cb0f`.

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

The wrapper rejects parser/load failures and requires the harness PASS marker because some Godot CLI script-load failures can still return exit code zero. Set `GODOT_BIN=godot4` when needed. Test failures must not be converted to skips to make CI pass.

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

This repository targets a focused MVP: one 30×16-tile tutorial room, one pressure plate and linked door, one objective, one exit, a 20-second deterministic loop, and up to eight in-memory Ghost recordings. The acceptance path requires at least two timelines. The live player and Ghost share a directional animated sprite set; a non-colliding deterministic guard patrol demonstrates the processed guard art without adding detection or combat scope.

Known limitations:

- One tutorial level; the guard is presentation-only, with no detection, navigation, combat, campaign, progression, or procedural generation.
- Recordings live only for the current level session and are not saved to disk.
- Keyboard and mouse are the primary input devices; mobile touch controls are out of scope.
- Desktop artifacts are unsigned development builds.
- Character interaction/alert cycles and the seamless facility base still use documented prototype fallbacks; the original AI concept sheets are not production-ready tiles or complete animation sets.

See [docs/roadmap.md](docs/roadmap.md) for the deliberately narrow next steps.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Bug reports should include the browser or OS, commit, reproduction steps, logs, and visual evidence when possible. Large features should begin with an issue so they do not compromise replay determinism or MVP scope.

## License and third-party notices

Project-authored code and content are available under the [MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the Godot Engine notice, build-only dependencies, AI-source disclosure, and the current no-external-authored-assets statement.
