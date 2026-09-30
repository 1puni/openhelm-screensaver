#!/bin/sh
# Build one universal saver bundle carrying several scenes, chosen under System Settings → Options….
# Usage: build-collection.sh INFO_PLIST OUTPUT.saver SCENE.json [SCENE.json...]
# Each scene lands in Contents/Resources/Scenes/<id>/ with its plate, visibility mask and, when
# present, the adjacent <scene>.credits.txt as CREDITS.txt plus any files in <scene>.include/.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SAVER_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SAVER_ROOT/.." && pwd)
INFO_SOURCE=$1
BUNDLE=$2
shift 2
[ "$#" -gt 0 ] || { echo "no scenes given" >&2; exit 1; }
STAGE="$(dirname -- "$BUNDLE")/.collection-stage-$$.saver"
trap 'rm -rf "$STAGE"' EXIT INT TERM

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources/Scenes"
cp "$INFO_SOURCE" "$STAGE/Contents/Info.plist"
if SAVER_MODULE_NAME=$(plutil -extract OpenHelmModuleName raw -o - "$INFO_SOURCE" 2>/dev/null); then
  :
else
  SAVER_MODULE_NAME=OpenHelmChartSaver
fi
export SAVER_MODULE_NAME
"$SCRIPT_DIR/compile-saver.sh" "$STAGE/Contents/MacOS/OpenHelmChartSaver" arm64 x86_64
for SCENE_ARG in "$@"; do
  SCENE_SOURCE="$(CDPATH= cd -- "$(dirname -- "$SCENE_ARG")" && pwd)/$(basename -- "$SCENE_ARG")"
  (cd "$REPO_ROOT" && node --input-type=module -e 'import {readSaverScene} from "./tools/screensaver-scene.mjs"; await readSaverScene(process.argv[1]);' "$SCENE_SOURCE")
  ID=$(plutil -extract id raw -o - "$SCENE_SOURCE")
  OUT="$STAGE/Contents/Resources/Scenes/$ID"
  test ! -e "$OUT" || { echo "duplicate scene id: $ID" >&2; exit 1; }
  mkdir "$OUT"
  cp "$SCENE_SOURCE" "$OUT/scene.json"
  cp "$SAVER_ROOT/Resources/$(plutil -extract chart.asset raw -o - "$SCENE_SOURCE")" "$OUT/"
  cp "$SAVER_ROOT/Resources/$(plutil -extract chart.lightVisibilityAsset raw -o - "$SCENE_SOURCE")" "$OUT/"
  if [ -f "${SCENE_SOURCE%.json}.credits.txt" ]; then
    cp "${SCENE_SOURCE%.json}.credits.txt" "$OUT/CREDITS.txt"
  fi
  # Licence documents a source requires to travel with derived work (e.g. NOAA's ENC agreement).
  if [ -d "${SCENE_SOURCE%.json}.include" ]; then
    for EXTRA in "${SCENE_SOURCE%.json}.include"/*; do cp -L "$EXTRA" "$OUT/"; done
  fi
done
DEFAULT=$(plutil -extract OpenHelmDefaultScene raw -o - "$INFO_SOURCE" 2>/dev/null || true)
[ -z "$DEFAULT" ] || test -d "$STAGE/Contents/Resources/Scenes/$DEFAULT" || { echo "default scene not bundled: $DEFAULT" >&2; exit 1; }
codesign --force --deep --sign - "$STAGE"
"$SCRIPT_DIR/verify-bundle.sh" "$STAGE"
rm -rf "$BUNDLE"
mv "$STAGE" "$BUNDLE"
trap - EXIT INT TERM
"$SCRIPT_DIR/verify-bundle.sh" "$BUNDLE"
