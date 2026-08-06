#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname -- "$SCRIPT_DIR")"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"
ARTIFACT_DIR="$PROJECT_ROOT/.artifacts"
OUTPUT_PATH="${1:-$ARTIFACT_DIR/performance.json}"
PERF_WORKSPACE="$(mktemp -d -t pngtuberplus-performance.XXXXXX)"

cleanup() {
	if [[ -n "$PERF_WORKSPACE" && -d "$PERF_WORKSPACE" ]]; then
		rm -rf "$PERF_WORKSPACE"
	fi
}
trap cleanup EXIT

mkdir -p "$ARTIFACT_DIR"

ENGINE_VERSION="$($GODOT_EXECUTABLE --version)"
case "$ENGINE_VERSION" in
	4.6.*) ;;
	*)
		echo "Expected Godot 4.6.x, found: $ENGINE_VERSION" >&2
		exit 1
		;;
esac

cp "$PROJECT_ROOT/tests/test_project.godot" "$PERF_WORKSPACE/project.godot"
cp -R "$PROJECT_ROOT/tests" "$PERF_WORKSPACE/tests"
cp -R "$PROJECT_ROOT/effects" "$PERF_WORKSPACE/effects"
cp -R "$PROJECT_ROOT/autoload" "$PERF_WORKSPACE/autoload"
mkdir -p "$PERF_WORKSPACE/test"
cp "$PROJECT_ROOT/test/testBody.png" "$PERF_WORKSPACE/test/testBody.png"

"$GODOT_EXECUTABLE" --headless --path "$PERF_WORKSPACE" \
	--script res://tests/performance/performance_runner.gd -- --output="$OUTPUT_PATH"
