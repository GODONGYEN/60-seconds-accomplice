#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

godot_bin="${GODOT_BIN:-godot}"
test_log="$(mktemp -t sixty-second-accomplice-tests.XXXXXX)"
trap 'rm -f "$test_log"' EXIT

"$godot_bin" --headless --path . --script tests/run_tests.gd 2>&1 | tee "$test_log"

if grep -Eq 'SCRIPT ERROR:|Failed to load script' "$test_log"; then
	echo "Test harness did not load successfully." >&2
	exit 1
fi

if ! grep -Eq '^\[TEST\] PASS: [0-9]+ assertions$' "$test_log"; then
	echo "Test harness did not print its required PASS marker." >&2
	exit 1
fi

