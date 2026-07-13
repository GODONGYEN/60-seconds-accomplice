#!/usr/bin/env bash

set -euo pipefail

destination="${1:?Usage: bash tools/copy_notices.sh DESTINATION_DIRECTORY}"
mkdir -p "$destination"
cp LICENSE "$destination/PROJECT_LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$destination/THIRD_PARTY_NOTICES.md"
cp licenses/GODOT_ENGINE_LICENSE.txt "$destination/GODOT_ENGINE_LICENSE.txt"

echo "Copied redistributable notices to $destination"
