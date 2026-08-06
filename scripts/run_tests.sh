#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname -- "$SCRIPT_DIR")"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"

ENGINE_VERSION="$($GODOT_EXECUTABLE --version)"
case "$ENGINE_VERSION" in
	4.6.*) ;;
	*)
		echo "Expected Godot 4.6.x, found: $ENGINE_VERSION" >&2
		exit 1
		;;
esac

IMPORT_LOG="$(mktemp -t pngtuberplus-import.XXXXXX)"
TEST_LOG="$(mktemp -t pngtuberplus-test.XXXXXX)"
TEST_WORKSPACE="$(mktemp -d -t pngtuberplus-tests.XXXXXX)"

cleanup() {
	rm -f "$IMPORT_LOG" "$TEST_LOG"
	if [[ -n "$TEST_WORKSPACE" && -d "$TEST_WORKSPACE" ]]; then
		rm -rf "$TEST_WORKSPACE"
	fi
}
trap cleanup EXIT

"$GODOT_EXECUTABLE" --headless --recovery-mode --editor --path "$PROJECT_ROOT" --import --quit 2>&1 | tee "$IMPORT_LOG"
if grep -E "(^|[[:space:]])ERROR:|SCRIPT ERROR|Parse Error|Failed to load script" "$IMPORT_LOG" >/dev/null; then
	echo "Godot reported an error during the recovery-mode import." >&2
	exit 1
fi

cp "$PROJECT_ROOT/tests/test_project.godot" "$TEST_WORKSPACE/project.godot"
cp -R "$PROJECT_ROOT/tests" "$TEST_WORKSPACE/tests"
cp -R "$PROJECT_ROOT/effects" "$TEST_WORKSPACE/effects"
cp -R "$PROJECT_ROOT/autoload" "$TEST_WORKSPACE/autoload"
mkdir -p "$TEST_WORKSPACE/main_scenes"
cp -R "$PROJECT_ROOT/main_scenes/controllers" "$TEST_WORKSPACE/main_scenes/controllers"
mkdir -p "$TEST_WORKSPACE/ui_scenes/selectedSprite"
cp "$PROJECT_ROOT/ui_scenes/selectedSprite/sprite_collision_builder.gd" "$TEST_WORKSPACE/ui_scenes/selectedSprite/"
mkdir -p "$TEST_WORKSPACE/test"
cp "$PROJECT_ROOT/test/testBody.png" "$TEST_WORKSPACE/test/testBody.png"

"$GODOT_EXECUTABLE" --headless --path "$TEST_WORKSPACE" \
	--script res://tests/test_runner.gd -- --source-root="$PROJECT_ROOT" 2>&1 | tee "$TEST_LOG"
if grep -E "(^|[[:space:]])ERROR:|SCRIPT ERROR|Parse Error|Failed to load script" "$TEST_LOG" >/dev/null; then
	echo "Godot reported an error during the isolated test run." >&2
	exit 1
fi
