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
TARGET=arm64-apple-macosx14.0

export SWIFTPM_MODULECACHE_OVERRIDE="$SAVER_ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$SAVER_ROOT/.build/clang-cache"
swift build --disable-sandbox --package-path "$SAVER_ROOT" -c release --triple "$TARGET" --product OpenHelmChartSaverCore
BIN_DIR=$(swift build --disable-sandbox --package-path "$SAVER_ROOT" -c release --triple "$TARGET" --show-bin-path)
CORE_LIBRARY="$BIN_DIR/libOpenHelmChartSaverCore.a"
test -f "$CORE_LIBRARY"
test -f "$ASSET_SOURCE"
test -f "$VISIBILITY_SOURCE"

mkdir -p "$BUILD_ROOT"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$INFO_SOURCE" "$STAGE/Contents/Info.plist"
xcrun swiftc \
  -module-cache-path "$SAVER_ROOT/.build/module-cache" \
  -target "$TARGET" -O -whole-module-optimization -parse-as-library \
  -module-name OpenHelmChartSaver \
  -I "$BIN_DIR/Modules" -L "$BIN_DIR" -lOpenHelmChartSaverCore \
  -framework AppKit -framework QuartzCore -framework ScreenSaver -framework ImageIO \
  -emit-library -Xlinker -bundle \
  -o "$STAGE/Contents/MacOS/OpenHelmChartSaver" \
  "$SAVER_ROOT/Sources/OpenHelmChartSaver/OpenHelmChartSaverView.swift"
chmod 755 "$STAGE/Contents/MacOS/OpenHelmChartSaver"
cp "$SCENE_SOURCE" "$STAGE/Contents/Resources/scene.json"
cp "$ASSET_SOURCE" "$STAGE/Contents/Resources/$ASSET"
cp "$VISIBILITY_SOURCE" "$STAGE/Contents/Resources/$VISIBILITY_ASSET"
codesign --force --deep --sign - "$STAGE"
"$SCRIPT_DIR/verify-bundle.sh" "$STAGE"

rm -rf "$BUNDLE"
mv "$STAGE" "$BUNDLE"
"$SCRIPT_DIR/verify-bundle.sh" "$BUNDLE"
