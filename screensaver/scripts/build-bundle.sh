#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SAVER_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SAVER_ROOT/.." && pwd)
SCENE_SOURCE=${1:-"$SAVER_ROOT/Scenes/alcatraz-noaa-preview.json"}
INFO_SOURCE=${2:-"$SAVER_ROOT/Info.plist"}
(cd "$REPO_ROOT" && node --input-type=module -e 'import {readSaverScene} from "./tools/screensaver-scene.mjs"; await readSaverScene(process.argv[1]);' "$SCENE_SOURCE")
ASSET=$(plutil -extract chart.asset raw -o - "$SCENE_SOURCE")
ASSET_SOURCE="$SAVER_ROOT/Resources/$ASSET"
VISIBILITY_ASSET=$(plutil -extract chart.lightVisibilityAsset raw -o - "$SCENE_SOURCE")
VISIBILITY_SOURCE="$SAVER_ROOT/Resources/$VISIBILITY_ASSET"
BUILD_ROOT="$SAVER_ROOT/build"
BUNDLE="$BUILD_ROOT/OpenHelmChartSaver.saver"
STAGE="$BUILD_ROOT/.OpenHelmChartSaver-stage-$$.saver"
test -f "$ASSET_SOURCE"
test -f "$VISIBILITY_SOURCE"

mkdir -p "$BUILD_ROOT"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$INFO_SOURCE" "$STAGE/Contents/Info.plist"
"$SCRIPT_DIR/compile-saver.sh" "$STAGE/Contents/MacOS/OpenHelmChartSaver"
cp "$SCENE_SOURCE" "$STAGE/Contents/Resources/scene.json"
cp "$ASSET_SOURCE" "$STAGE/Contents/Resources/$ASSET"
cp "$VISIBILITY_SOURCE" "$STAGE/Contents/Resources/$VISIBILITY_ASSET"
# Optional per-scene data credits (Scenes/<scene>.credits.txt) back the saver's Options sheet.
CREDITS_SOURCE="${SCENE_SOURCE%.json}.credits.txt"
if [ -f "$CREDITS_SOURCE" ]; then
  cp "$CREDITS_SOURCE" "$STAGE/Contents/Resources/CREDITS.txt"
fi
codesign --force --deep --sign - "$STAGE"
"$SCRIPT_DIR/verify-bundle.sh" "$STAGE"

rm -rf "$BUNDLE"
mv "$STAGE" "$BUNDLE"
"$SCRIPT_DIR/verify-bundle.sh" "$BUNDLE"
