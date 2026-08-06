#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname -- "$SCRIPT_DIR")"
GODOT_EXECUTABLE="${GODOT_BIN:-godot}"
ARTIFACT_DIR="$PROJECT_ROOT/.artifacts/export-smoke"

case "${1:-}" in
	"Windows Desktop"|"Linux/X11"|"macOS") PRESET="$1" ;;
	"")
		case "$(uname -s)" in
			Darwin) PRESET="macOS" ;;
			Linux) PRESET="Linux/X11" ;;
			MINGW*|MSYS*|CYGWIN*) PRESET="Windows Desktop" ;;
			*) echo "Cannot determine the host export preset; pass it explicitly." >&2; exit 1 ;;
		esac
		;;
	*) echo "Unknown export preset: $1" >&2; exit 1 ;;
esac

ENGINE_VERSION="$($GODOT_EXECUTABLE --version)"
case "$ENGINE_VERSION" in
	4.6.*) ;;
	*) echo "Expected Godot 4.6.x, found: $ENGINE_VERSION" >&2; exit 1 ;;
esac

case "$PRESET" in
	"Windows Desktop") SLUG="windows" ;;
	"Linux/X11") SLUG="linux" ;;
	"macOS") SLUG="macos" ;;
esac

mkdir -p "$ARTIFACT_DIR"
PACK_PATH="$ARTIFACT_DIR/$SLUG.pck"
EXPORT_LOG="$ARTIFACT_DIR/$SLUG-export.log"
RUNTIME_LOG="$ARTIFACT_DIR/$SLUG-runtime.log"

set +e
"$GODOT_EXECUTABLE" --headless --recovery-mode --path "$PROJECT_ROOT" \
	--export-pack "$PRESET" "$PACK_PATH" 2>&1 | tee "$EXPORT_LOG"
EXPORT_STATUS=${PIPESTATUS[0]}
set -e
if [[ $EXPORT_STATUS -ne 0 ]] || grep -E "(^|[[:space:]])ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Cannot get class" "$EXPORT_LOG" >/dev/null; then
	echo "The $PRESET resource-pack export reported an error." >&2
	exit 1
fi
if [[ ! -s "$PACK_PATH" ]]; then
	echo "The $PRESET resource-pack export did not create a pack." >&2
	exit 1
fi

set +e
(
	cd "$ARTIFACT_DIR"
	"$GODOT_EXECUTABLE" --headless --audio-driver Dummy --main-pack "$PACK_PATH" \
		--quit-after 3 -- --release-smoke
) 2>&1 | tee "$RUNTIME_LOG"
RUNTIME_STATUS=${PIPESTATUS[0]}
set -e
if [[ $RUNTIME_STATUS -ne 0 ]] || grep -E "(^|[[:space:]])ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Cannot get class" "$RUNTIME_LOG" >/dev/null; then
	echo "The $PRESET exported-pack launch reported an error." >&2
	exit 1
fi

echo "Export smoke passed for $PRESET: $PACK_PATH"
