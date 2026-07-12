# Third-Party Notices

## Game assets

The MVP currently uses no externally sourced commercial art, audio, font, or shader assets. Project-authored primitive visuals and source files are covered by the repository's MIT License.

If an external asset is added later, its source URL, author, version, license, redistribution terms, and required attribution must be recorded here in the same change.

## Godot Engine

This project is built with **Godot Engine 4.7 stable**. Exported Web and desktop packages include or are linked with Godot Engine runtime components.

- Project: [Godot Engine](https://godotengine.org/)
- Source: [godotengine/godot](https://github.com/godotengine/godot)
- Copyright: Godot Engine contributors
- License: [MIT License](https://github.com/godotengine/godot/blob/master/LICENSE.txt)

Godot Engine is free and open source software provided under the MIT License. Its copyright and permission notice must remain available with redistributed builds. Godot may include third-party components under compatible licenses; the authoritative notices are maintained in the engine's [copyright file](https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt).

## Build-only dependencies

GitHub Actions workflows download the official Godot 4.7 stable editor and export templates from `godotengine/godot-builds` and verify the published SHA-512 digests. GitHub's official Actions used by the workflows are pinned to immutable commit SHAs. These build tools are not authored by this project and are not game content.
