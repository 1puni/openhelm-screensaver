#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SAVER_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SAVER_ROOT/.." && pwd)
BUNDLE=${1:-"$SAVER_ROOT/build/OpenHelmChartSaver.saver"}
INFO="$BUNDLE/Contents/Info.plist"
EXECUTABLE="$BUNDLE/Contents/MacOS/OpenHelmChartSaver"
RESOURCES="$BUNDLE/Contents/Resources"

test -d "$BUNDLE" || { echo "missing saver bundle: $BUNDLE" >&2; exit 1; }
plutil -lint "$INFO" >/dev/null
test "$(plutil -extract CFBundleExecutable raw -o - "$INFO")" = "OpenHelmChartSaver"
PRINCIPAL=$(plutil -extract NSPrincipalClass raw -o - "$INFO")
case "$PRINCIPAL" in OpenHelmChartSaverView|OnePuniTynningoSaverView) ;; *) exit 1 ;; esac
test -x "$EXECUTABLE"
file "$EXECUTABLE" | grep -q 'Mach-O 64-bit bundle arm64'
nm -gU "$EXECUTABLE" | grep -Fq "_OBJC_CLASS_\$_$PRINCIPAL"
codesign --verify --deep --strict "$BUNDLE"
verify_scene() {
  SCENE_DIR=$1
  SCENE="$SCENE_DIR/scene.json"
  plutil -convert json -o - "$SCENE" >/dev/null
  (cd "$REPO_ROOT" && node --input-type=module -e 'import {readSaverScene} from "./tools/screensaver-scene.mjs"; await readSaverScene(process.argv[1]);' "$SCENE")
  ASSET=$(plutil -extract chart.asset raw -o - "$SCENE")
  PNG="$SCENE_DIR/$ASSET"
  VISIBILITY_ASSET=$(plutil -extract chart.lightVisibilityAsset raw -o - "$SCENE")
  VISIBILITY_PNG="$SCENE_DIR/$VISIBILITY_ASSET"
  test -f "$PNG"
  file "$PNG" | grep -q 'PNG image data'
  test -f "$VISIBILITY_PNG"
  file "$VISIBILITY_PNG" | grep -q 'PNG image data.*RGBA'
  WIDTH=$(sips -g pixelWidth "$PNG" | awk '/pixelWidth:/ {print $2}')
  HEIGHT=$(sips -g pixelHeight "$PNG" | awk '/pixelHeight:/ {print $2}')
  LOGICAL_WIDTH=$(plutil -extract chart.logicalWidth raw -o - "$SCENE")
  LOGICAL_HEIGHT=$(plutil -extract chart.logicalHeight raw -o - "$SCENE")
  SCALE=$(plutil -extract chart.deviceScaleFactor raw -o - "$SCENE")
  EXPECTED_WIDTH=$((LOGICAL_WIDTH * SCALE))
  EXPECTED_HEIGHT=$((LOGICAL_HEIGHT * SCALE))
  test "$WIDTH" = "$EXPECTED_WIDTH" || { echo "wrong PNG width: $WIDTH (expected $EXPECTED_WIDTH)" >&2; exit 1; }
  test "$HEIGHT" = "$EXPECTED_HEIGHT" || { echo "wrong PNG height: $HEIGHT (expected $EXPECTED_HEIGHT)" >&2; exit 1; }
  VISIBILITY_WIDTH=$(sips -g pixelWidth "$VISIBILITY_PNG" | awk '/pixelWidth:/ {print $2}')
  VISIBILITY_HEIGHT=$(sips -g pixelHeight "$VISIBILITY_PNG" | awk '/pixelHeight:/ {print $2}')
  test "$VISIBILITY_WIDTH" = "$EXPECTED_WIDTH" || { echo "wrong visibility mask width: $VISIBILITY_WIDTH (expected $EXPECTED_WIDTH)" >&2; exit 1; }
  test "$VISIBILITY_HEIGHT" = "$EXPECTED_HEIGHT" || { echo "wrong visibility mask height: $VISIBILITY_HEIGHT (expected $EXPECTED_HEIGHT)" >&2; exit 1; }
}

# Single-scene bundles keep scene.json at the top of Resources; lighthouse collections carry one
# directory per scene under Resources/Scenes/<id>/ (the id must match the directory name).
if [ -d "$RESOURCES/Scenes" ]; then
  COUNT=0
  for SCENE_DIR in "$RESOURCES"/Scenes/*/; do
    SCENE_DIR=${SCENE_DIR%/}
    verify_scene "$SCENE_DIR"
    test "$(plutil -extract id raw -o - "$SCENE_DIR/scene.json")" = "${SCENE_DIR##*/}" || { echo "scene id does not match directory: $SCENE_DIR" >&2; exit 1; }
    COUNT=$((COUNT + 1))
  done
  test "$COUNT" -gt 0 || { echo "empty scene collection: $RESOURCES/Scenes" >&2; exit 1; }
else
  verify_scene "$RESOURCES"
fi
echo "verified $BUNDLE"
