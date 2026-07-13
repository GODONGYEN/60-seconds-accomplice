# Build and Release Guide

## Supported toolchain

- Engine: Godot Engine **4.7 stable**, standard GDScript build
- Export templates: Godot **4.7 stable**, matching the editor exactly
- Renderer: Compatibility
- Primary target: single-threaded Web
- Desktop development targets: Windows x86_64, Linux x86_64, macOS universal

The most recent local validation used `4.7.stable.official.5b4e0cb0f`.

The automated workflows download editor and templates from the official `godotengine/godot-builds` 4.7-stable release and verify their published SHA-512 digests. GitHub actions are pinned to immutable commit SHAs.

No gameplay secret or environment variable is required. Desktop signing and notarization are intentionally not configured.

## Find the local Godot executable

Try the command names available on the machine:

```bash
godot --version
godot4 --version
```

On macOS, a downloaded application bundle contains its executable under `Godot.app/Contents/MacOS/`. Use whichever candidate reports `4.7.stable`; substitute that executable for `godot` below. Do not commit a machine-specific absolute path.

## Clean validation sequence

Run from the repository root:

```bash
python3 -m venv .tools/venv
.tools/venv/bin/python -m pip install --requirement requirements-tools.txt
PYTHON_BIN=.tools/venv/bin/python bash tools/validate_assets.sh
godot --headless --path . --import
godot --headless --path . --quit
godot --headless --path . --script tools/validate_operation_black_minute.gd
GODOT_BIN=godot tools/run_tests.sh
```

The mission validator must report `PASS` before the test harness starts. It checks the committed Operation: Black Minute blueprint contract, including map dimensions, required rooms and systems, reachability, Guard/CCTV/laser counts, and minimum safe timing windows. A failing mission contract blocks CI, Pages, and desktop releases even when lower-level tests still pass.

The test command must also return zero. Then perform the Operation: Black Minute acceptance path in the editor and confirm that its infiltration, Chrono Recall/Echo, objective, and extraction sequence remains completable. Check that dynamic security states agree across movement collision, Guard/CCTV line of sight, and player-visible feedback. The preserved prototype and facility scenes remain separate regression modes; verify their documented two-loop plate→Ghost→door paths after changes to shared systems.

## Web release export

The `Web` preset must remain single-threaded and must not require cross-origin isolation headers. Export to a top-level `index.html`:

```bash
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
bash tools/copy_notices.sh build/web/licenses
test -f build/web/index.html
find build/web -maxdepth 1 -name '*.wasm' -print
find build/web -maxdepth 1 -name '*.pck' -print
find build/web -maxdepth 1 -name '*.js' -print
```

Serve the directory over HTTP:

```bash
python3 -m http.server --directory build/web 8000
```

Open `http://localhost:8000/`, click the game, complete a two-loop run, resize the window, pause, mute, toggle fullscreen, and check the browser console. Do not use `file://` for validation.

Expected artifact root:

```text
build/web/
├── index.html
├── index.js
├── index.wasm
├── index.pck
└── licenses/
```

Godot can add icons or worker-related support files; the validation requires at least the HTML, JavaScript, WebAssembly, and PCK files. A single-threaded preset must not rely on custom `Cross-Origin-Opener-Policy` or `Cross-Origin-Embedder-Policy` headers.

## GitHub Actions CI

`.github/workflows/ci.yml` runs on pull requests, pushes to `main`, and manual dispatch. It performs:

1. pinned Python setup, asset validation, regeneration, and semantic fingerprint comparison;
2. official Godot editor/template download with checksum verification;
3. project import;
4. headless boot and GDScript parse validation;
5. the Operation: Black Minute mission contract validator;
6. the Godot test harness;
7. a Web release smoke export with redistributable notices;
8. required artifact-file checks;
9. upload of the Web smoke build for diagnostics.

CI has `contents: read` permission only. Do not add a success badge until a run has actually passed in the public repository.

## GitHub Pages deployment

`.github/workflows/deploy-pages.yml` runs on pushes to `main` and manual dispatch. It uses separate `build` and `deploy` jobs. The deploy job depends on the build, targets the `github-pages` environment, and exposes the official deployment URL.

Repository setup:

1. Open **Settings → Pages** on GitHub.
2. Set **Source** to **GitHub Actions**.
3. Ensure Actions are allowed to run official GitHub actions.
4. Push to `main` or manually run **Deploy GitHub Pages**.
5. Confirm the build artifact root contains `index.html`.
6. Open the deployment URL shown by the `deploy` job and perform the browser smoke test.
7. Update the README play link with that verified URL.

The build job uses `contents: read` and `pages: read`. Only the deploy job receives:

```yaml
pages: write
id-token: write
```

It does not commit generated exports to a source branch. Deployment concurrency prevents overlapping Pages releases.

## Desktop development exports

With matching templates installed:

```bash
mkdir -p build/windows build/linux build/macos
godot --headless --path . --export-release "Windows Desktop" build/windows/Sixty-Second-Accomplice.exe
godot --headless --path . --export-release "Linux" build/linux/Sixty-Second-Accomplice.x86_64
godot --headless --path . --export-release "macOS" build/macos/Sixty-Second-Accomplice.zip
bash tools/copy_notices.sh build/windows/licenses
bash tools/copy_notices.sh build/linux/licenses
```

The release workflow packages:

- `Sixty-Second-Accomplice-windows-x86_64.zip`
- `Sixty-Second-Accomplice-linux-x86_64.zip`
- `Sixty-Second-Accomplice-macos-universal.zip`
- `SHA256SUMS.txt`

These are unsigned development builds. In particular, the macOS artifact is not code-signed or notarized and may trigger Gatekeeper. Never claim otherwise unless signing identities, hardened runtime, notarization credentials, and verification steps are deliberately added.

## Create a tagged release

1. Confirm CI and the Pages smoke test pass for the intended commit.
2. Confirm the working tree contains no build output, secrets, signing files, or local paths.
3. Create and push a version tag:

   ```bash
   git tag -a v0.1.0 -m "MVP v0.1.0"
   git push origin v0.1.0
   ```

4. `.github/workflows/release.yml` exports all desktop targets, embeds redistributable notices, generates SHA-256 checksums, and creates the matching immutable GitHub Release.
5. Download every asset from the release and verify its checksum on a clean machine.

The workflow can also be dispatched manually with a required `v*` tag value. An existing release is never overwritten. If the tag already exists, it must resolve to the exact commit that was built; otherwise publishing fails.

## Pre-release checklist

- `project.godot` uses Godot 4.7 features and declares the intended main scene.
- `export_presets.cfg` contains `Web`, `Windows Desktop`, `Linux`, and `macOS` presets.
- Web export is single-threaded and its artifact root contains `index.html`.
- Automated tests pass without skips added to hide failures.
- The Operation: Black Minute mission validator passes before automated tests.
- Asset derivatives validate and reproduce to the same semantic fingerprint.
- Operation: Black Minute passes its infiltration, Chrono Recall/Echo, objective, and extraction acceptance path.
- The facility two-loop path passes with wall visibility, terminal-controlled laser, Guard/Ghost distraction, Ghost-held vault door, objective, and courtyard exit.
- The preserved 20-second prototype two-loop regression passes after timeout and manual restart.
- Pause stops timeline, recording, and playback clocks.
- Victory wins the race against timeout and blocks further gameplay input.
- The browser console has no unexplained errors.
- README commands match the actual preset and test names.
- `THIRD_PARTY_NOTICES.md` covers every redistributed dependency or asset.
- Web and desktop packages contain project, third-party, and Godot license notices.
- No `.godot/`, `build/`, local cache, secret, signing identity, or machine path is tracked.
- macOS artifacts are labeled unsigned.

## Troubleshooting

### Export templates are missing

Install the exact 4.7 stable templates through **Editor → Manage Export Templates**, or place the extracted official templates in Godot's versioned export-template directory. An editor/templates version mismatch is unsupported.

### Web export fails on threads or headers

Verify the `Web` preset has thread support disabled. GitHub Pages does not provide project-controlled cross-origin isolation headers, so the MVP must use the single-threaded Web runtime.

### The Web build works locally but not on Pages

Confirm `index.html` is at the uploaded artifact root, file names match case exactly, and resources use relative project paths. Inspect both the workflow log and browser console.

### macOS refuses to open a release artifact

The automated macOS package is unsigned. This is a documented limitation, not evidence of successful signing. For public production distribution, add a separate reviewed signing/notarization process with protected secrets.
