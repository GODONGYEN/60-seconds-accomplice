# Sixty-Second Accomplice

**60초의 공범** is a Godot 4 top-down stealth heist about planning an infiltration, dismantling layered security, and using a limited ten-second time recall when the plan breaks.

> **한국어 안내:** 정식 임무 **작전명: 검은 1분**에서 헬릭스 시간 연구시설에 침투해 출입 카드, CCTV, 레이저, 금고 인증을 해결하고 크로노스 코어를 훔쳐 탈출합니다. 시간 회귀는 강제 반복이 아니라 최대 3회 사용할 수 있는 선택 능력입니다. 기존 20초/60초 전체 시간선 모드는 기술 회귀 검증용으로 보존됩니다.

## Play in your browser

[Play the current `main` deployment on GitHub Pages](https://godongyen.github.io/60-seconds-accomplice/).

GitHub Actions builds that URL from `main`. Check the repository Actions page for the deployed revision; a local working tree is not assumed to be live.

> Screenshot/GIF placeholder: the live infiltrator crossing a security zone while an Echo draws a Guard and CCTV camera away.

## Current game modes

The application uses an explicit `GameMode` enum instead of inferring a mode from scene names.

| Mode | Purpose | Entry |
|---|---|---|
| `OPERATION_BLACK_MINUTE` | Primary stealth-heist mission | Main menu → briefing → start mission |
| `PROTOTYPE_LOOP` | Preserved 20-second loop/Ghost/puzzle regression | Mission select or `-- --prototype` |
| `FACILITY_REGRESSION` | Preserved 60-second facility/visibility regression | Mission select or `-- --facility-regression` |

The primary mission does not force a full-level reset every 20 or 60 seconds. It uses **Chrono Recall**: three mission-persistent charges, up to ten seconds of rewindable recent history, and a maximum of three Echoes.

## Operation: Black Minute

Infiltrate the **Helix Temporal Research Facility**, steal the **Chronos Core**, and return to the external extraction yard.

The authored blueprint is a `64×42` grid of `32 px` cells (`2048×1344 px`) with:

- 15 named rooms and operational spaces;
- 10 deterministic Guards divided across 7 bounded response zones;
- 8 sweeping CCTV cameras;
- 3 laser barriers;
- Level 1, Level 2, and Vault access progression;
- server override or research biometric authorization paths;
- 15 declared choke points with safe windows of at least three seconds.

The normal security progression is:

```text
Briefing and tactical map
→ infiltrate reception
→ acquire Level 1 in the locker room
→ disable or avoid CCTV
→ disable laser power in electrical
→ acquire Level 2 in security
→ obtain server OR biometric vault authorization
→ enter the Chronos Vault
→ steal the Core
→ extract through the external yard
```

A perfect no-Recall route is part of the mission contract. Recall is an optional recovery and improvisation tool: rewinding leaves the abandoned movement and permitted interactions behind as an Echo that Guards and cameras can see.

## Controls

| Input | Operation: Black Minute | Loop regression modes |
|---|---|---|
| <kbd>WASD</kbd> or arrows | Move | Move |
| Mouse | Face pointer | Face pointer |
| <kbd>E</kbd> | Interact, collect, hack, or use a door | Interact |
| <kbd>Q</kbd> | Chrono Recall | — |
| <kbd>M</kbd> or <kbd>Tab</kbd> | Open tactical map; mission pauses | — |
| <kbd>R</kbd> | — | Finalize and restart the current loop |
| <kbd>Esc</kbd> | Pause/resume or close map | Pause/resume |
| <kbd>F11</kbd> | Toggle fullscreen | Toggle fullscreen |
| <kbd>V</kbd> | Mute/unmute | Mute/unmute |

In a browser, click the game once before using the keyboard. If the tab loses focus, return and click again. See [Controls and Browser Input](docs/controls.md).

## Heist architecture

`AppController` owns menu and mode transitions. The formal mission is orchestrated by focused managers:

- `MissionDirector` and `ObjectiveGraph`: mission state and acyclic objectives;
- `AccessControlManager`: credentials and door authorization;
- `SecuritySystemManager`: CCTV, lasers, zone alerts, and facility alert level;
- `GuardZoneManager`: zone assignment, bounded response, and alert recipients;
- `PatrolScheduler`: deterministic patrol phases, tile/choke reservation, and overlap prevention;
- `ChronoRecallManager`: bounded history, world snapshots, persistent charge spending, restore, and Echo creation;
- `OperationBlackMinuteMap`: blueprint-driven TileMap layers and facility layout.

The preserved loop modes continue to use `GameManager` + `TimelineManager`; the formal heist does not turn `TimelineManager` into a cross-mode god object. See [Technical Architecture](docs/architecture.md).

## Requirements

- [Godot Engine 4.7 stable](https://godotengine.org/download/archive/4.7-stable/) — standard GDScript build, not Mono
- Git
- Python 3 for the reproducible art pipeline and local Web server

The project pins `Godot 4.7.stable.official.5b4e0cb0f`, uses the Compatibility renderer, a responsive 1280×720 reference viewport, and a single-threaded Web export. There are no accounts, servers, analytics SDKs, secrets, or required environment variables at runtime.

## Run locally

```bash
git clone https://github.com/GODONGYEN/60-seconds-accomplice.git
cd 60-seconds-accomplice
godot --editor --path .
```

Headless import and default menu boot:

```bash
godot --headless --path . --import
godot --headless --path . --quit-after 3
```

Launch a preserved regression mode directly:

```bash
godot --path . -- --prototype
godot --path . -- --facility-regression
```

If the executable is named `godot4`, substitute it in every command.

## Validate and test

The operation blueprint has a standalone static solvability validator:

```bash
godot --headless --path . --script tools/validate_operation_black_minute.gd
```

It rejects invalid dimensions/counts, duplicate stable IDs, out-of-bounds or non-walkable required objects, disconnected room graphs, circular access/objective progression, missing vault-auth alternatives, missing no-Recall/Recall declarations, and choke safe windows shorter than three seconds.

Run the complete Godot harness without a third-party test add-on:

```bash
GODOT_BIN=godot tools/run_tests.sh
```

The wrapper requires an explicit PASS marker in addition to the process exit code. The suite covers the preserved timeline mechanics, mission blueprint, objective/access/security logic, Chrono Recall snapshots and Echoes, Guard zones, and a deterministic virtual patrol simulation. Test failures are not converted to skips.

## Art asset pipeline

Gameplay references only normalized runtime atlases under `assets/sprites/`; AI-generated source sheets and previews are not loaded by scenes.

```bash
python3 -m venv .tools/venv
.tools/venv/bin/python -m pip install --requirement requirements-tools.txt
.tools/venv/bin/python tools/asset_pipeline.py process-all
.tools/venv/bin/python tools/asset_pipeline.py validate
```

See [Art Pipeline](docs/art_pipeline.md), [Asset Manifest](docs/asset_manifest.md), and [Art Direction](docs/art_direction.md).

## Export for Web

Install matching Godot 4.7 export templates, then run:

```bash
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
bash tools/copy_notices.sh build/web/licenses
test -f build/web/index.html
python3 -m http.server --directory build/web 8000
```

Open [http://localhost:8000/](http://localhost:8000/), never `file://`. A successful headless export does not by itself prove browser rendering, input, or console cleanliness; inspect those separately.

## Export desktop development builds

```bash
mkdir -p build/windows build/linux build/macos
godot --headless --path . --export-release "Windows Desktop" build/windows/Sixty-Second-Accomplice.exe
godot --headless --path . --export-release "Linux" build/linux/Sixty-Second-Accomplice.x86_64
godot --headless --path . --export-release "macOS" build/macos/Sixty-Second-Accomplice.zip
```

Desktop artifacts are unsigned development builds. macOS Gatekeeper may warn; signing and notarization are not claimed without configured credentials.

## Publish with GitHub Pages

`.github/workflows/deploy-pages.yml` exports the Web build and deploys the official Pages artifact.

1. Keep `main` as the deployment branch.
2. In **Settings → Pages**, select **GitHub Actions** as the source.
3. Push to `main` or run **Deploy GitHub Pages** manually.
4. Confirm the workflow revision and then open the play link above.

See [Release Guide](docs/release.md).

## Documentation

- [Story](docs/story.md)
- [Operation: Black Minute](docs/missions/operation_black_minute.md)
- [Facility layout](docs/maps/operation_black_minute_layout.md)
- [Objective system](docs/objective_system.md)
- [Security systems](docs/security_systems.md)
- [Access control](docs/access_control.md)
- [Chrono Recall](docs/chrono_recall.md)
- [Guard zones and patrol scheduling](docs/guard_zones.md)
- [Onboarding](docs/onboarding.md)
- [Roadmap](docs/roadmap.md)

## Known limitations

- There is one formal heist mission. Campaign progression, persistent saves, mission scoring, and `CONTINUE` are not implemented.
- The only checkpoint is mission start. Capturing after Core theft does not create an extraction-phase checkpoint.
- Chrono Recall keeps only the current bounded branch; it cannot cross a previous Recall branch. At the three-Echo cap, the oldest Echo is removed.
- Guard movement uses deterministic authored routes, bounded zones, collision-aware steering, and reservations rather than a general navigation mesh.
- Vision cones are readable approximations; actual detection additionally uses physics line of sight and close-proximity awareness.
- CCTV and facility alerts coordinate nearby zones, but there are no reinforcements, combat, health, hearing simulation, or multiple enemy archetypes.
- Mission data and recordings are session-only and are not written to disk.
- Keyboard and mouse are the primary supported devices; controller rebinding and touch controls are out of scope.
- Current headless validation cannot certify actual Compatibility-renderer shadow pixels or browser UX. Do not infer a manual browser pass from automated tests.

## Contributing and license

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Large changes should begin with an issue so they preserve deterministic replay, mission solvability, and the regression modes.

Project-authored code and content are available under the [MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for Godot, build dependencies, and AI-source disclosure.
