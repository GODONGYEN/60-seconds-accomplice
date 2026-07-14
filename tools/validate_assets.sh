#!/usr/bin/env bash

set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-python3}"
before_fingerprint="$(mktemp)"
after_fingerprint="$(mktemp)"
trap 'rm -f "$before_fingerprint" "$after_fingerprint"' EXIT

"$PYTHON_BIN" tools/asset_pipeline.py validate
"$PYTHON_BIN" tools/environment_art_pipeline.py validate
"$PYTHON_BIN" tools/asset_pipeline.py fingerprint > "$before_fingerprint"
"$PYTHON_BIN" tools/environment_art_pipeline.py fingerprint >> "$before_fingerprint"
"$PYTHON_BIN" tools/asset_pipeline.py process-all
"$PYTHON_BIN" tools/environment_art_pipeline.py process-all
"$PYTHON_BIN" tools/asset_pipeline.py fingerprint > "$after_fingerprint"
"$PYTHON_BIN" tools/environment_art_pipeline.py fingerprint >> "$after_fingerprint"

if ! diff -u "$before_fingerprint" "$after_fingerprint"; then
	echo "Generated art derivatives are stale. Run process-all and commit the results." >&2
	exit 1
fi

echo "[asset-pipeline] PASS: committed derivatives reproduce semantically"
