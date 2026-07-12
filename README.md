# Sixty-Second Accomplice

**60초의 공범** is a 2D top-down time-loop puzzle game: record one 20-second run, then cooperate with the Ghost that replays it.

> **한국어 안내:** 20초 동안의 행동이 다음 회차의 Ghost로 재생됩니다. 과거의 나가 압력판을 누르는 동안 문을 통과하고, 시간 코어를 획득해 탈출하세요.

## Play in your browser

The public GitHub Pages deployment has not been confirmed yet. After the repository is published and Pages is enabled, the URL will be:

```text
https://<github-owner>.github.io/<repository-name>/
```

The link must be replaced with the verified deployment URL; this README intentionally does not guess it.

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
- Python 3, only for the local Web smoke server

The project uses the Compatibility renderer, a 1280×720 reference viewport, responsive 16:9 stretching, and a single-threaded Web export. No account, server, secret, analytics SDK, or network access is required to play.

## Run locally

Clone the repository, then open the project in the editor:

```bash
git clone <repository-url>
cd <repository-directory>
godot --editor --path .
```

If the executable is named `godot4`, substitute that name in every command. On macOS, the executable inside a downloaded app bundle can also be used directly.

For a headless boot:

```bash
godot --headless --path . --import
godot --headless --path . --quit
```

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
```

Unsigned macOS builds can trigger Gatekeeper. No signing or notarization is claimed without a configured Apple signing identity.

## Publish with GitHub Pages

The repository includes `.github/workflows/deploy-pages.yml`, which exports `build/web/index.html`, uploads the directory as a Pages artifact, and deploys it with GitHub's official actions.

1. Push the repository to GitHub with `main` as the default branch.
2. Open **Settings → Pages**.
3. Under **Build and deployment**, choose **GitHub Actions** as the source.
4. Run **Deploy GitHub Pages** from the Actions tab, or push to `main`.
5. Replace the placeholder play URL above only after the deployment reports its verified URL.

See [docs/release.md](docs/release.md) for CI, release, artifact, and troubleshooting details.

## Current status

This repository targets a focused MVP: one tutorial room, one pressure plate and linked door, one objective, one exit, a 20-second deterministic loop, and up to eight in-memory Ghost recordings. The acceptance path requires at least two timelines.

Known limitations:

- One tutorial level; no campaign, enemies, combat, progression, or procedural generation.
- Recordings live only for the current level session and are not saved to disk.
- Keyboard and mouse are the primary input devices; mobile touch controls are out of scope.
- Desktop artifacts are unsigned development builds.
- Placeholder visuals prioritize gameplay readability over final art.

See [docs/roadmap.md](docs/roadmap.md) for the deliberately narrow next steps.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Bug reports should include the browser or OS, commit, reproduction steps, logs, and visual evidence when possible. Large features should begin with an issue so they do not compromise replay determinism or MVP scope.

## License and third-party notices

Project-authored code and content are available under the [MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the Godot Engine notice and the current no-external-assets statement.
