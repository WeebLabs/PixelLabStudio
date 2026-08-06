#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname -- "$SCRIPT_DIR")"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "NDI teardown smoke skipped: the regression is macOS-specific."
	exit 0
fi

ENGINE_VERSION="$($GODOT_EXECUTABLE --version)"
case "$ENGINE_VERSION" in
	4.6.*) ;;
	*) echo "Expected Godot 4.6.x, found: $ENGINE_VERSION" >&2; exit 1 ;;
esac

RUNTIME_FOUND=false
if [[ -n "${NDILIB_REDIST_FOLDER:-}" && -f "$NDILIB_REDIST_FOLDER/libndi.dylib" ]]; then
	RUNTIME_FOUND=true
elif [[ -f /usr/local/lib/libndi.dylib ]]; then
	RUNTIME_FOUND=true
fi

if [[ "$RUNTIME_FOUND" != true && "${PNGTUBERPLUS_REQUIRE_NDI_TEARDOWN_SMOKE:-0}" != 1 ]]; then
	echo "NDI teardown smoke skipped: no macOS NDI runtime was found."
	exit 0
fi

TEST_WORKSPACE="$(mktemp -d -t pngtuberplus-ndi-teardown.XXXXXX)"
SMOKE_LOG="$(mktemp -t pngtuberplus-ndi-teardown.XXXXXX)"

cleanup() {
	rm -f "$SMOKE_LOG"
	if [[ -n "$TEST_WORKSPACE" && -d "$TEST_WORKSPACE" ]]; then
		rm -rf "$TEST_WORKSPACE"
	fi
}
trap cleanup EXIT

cp "$PROJECT_ROOT/tests/native/ndi_teardown/project.godot.fixture" "$TEST_WORKSPACE/project.godot"
cp "$PROJECT_ROOT/tests/native/ndi_teardown/main.tscn" "$TEST_WORKSPACE/main.tscn"
cp "$PROJECT_ROOT/tests/native/ndi_teardown/active_output.tscn" "$TEST_WORKSPACE/active_output.tscn"
mkdir -p "$TEST_WORKSPACE/addons"
cp -R "$PROJECT_ROOT/addons/godot-ndi" "$TEST_WORKSPACE/addons/godot-ndi"
mkdir -p "$TEST_WORKSPACE/.godot"
cp "$PROJECT_ROOT/tests/native/ndi_teardown/extension_list.cfg" "$TEST_WORKSPACE/.godot/extension_list.cfg"

set +e
"$GODOT_EXECUTABLE" --headless --path "$TEST_WORKSPACE" --quit-after 1 2>&1 | tee "$SMOKE_LOG"
SMOKE_STATUS=${PIPESTATUS[0]}
set -e

if [[ $SMOKE_STATUS -ne 0 ]] || grep -E "mutex lock failed|uncaught exception|SIGABRT|CRASH|(^|[[:space:]])ERROR:" "$SMOKE_LOG" >/dev/null; then
	echo "The idle macOS NDI extension did not tear down cleanly." >&2
	exit 1
fi

set +e
"$GODOT_EXECUTABLE" --audio-driver Dummy --path "$TEST_WORKSPACE" --quit-after 3 res://active_output.tscn 2>&1 | tee "$SMOKE_LOG"
SMOKE_STATUS=${PIPESTATUS[0]}
set -e

if [[ $SMOKE_STATUS -ne 0 ]] || grep -E "mutex lock failed|uncaught exception|SIGABRT|CRASH|(^|[[:space:]])ERROR:" "$SMOKE_LOG" >/dev/null; then
	echo "The active macOS NDI output did not tear down cleanly." >&2
	exit 1
fi

echo "NDI teardown smoke passed."
