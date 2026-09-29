#!/bin/sh
# Build, verify and zip the OpenHelm Lighthouses release (Tynningö + Alcatraz). Never installs
# or uploads. Output: build/lighthouses-release/ (zip, preview clips, SHA256SUMS, receipt).
set -eu
SAVER_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$SAVER_ROOT"
NAME="OpenHelm Lighthouses"
OUT="$SAVER_ROOT/build/lighthouses-release"
SCENES="Scenes/tynningo-open-preview.json Scenes/alcatraz-noaa-preview.json"
rm -rf "$OUT"
mkdir -p "$OUT"

# shellcheck disable=SC2086
scripts/build-collection.sh Scenes/lighthouses.plist "$SAVER_ROOT/build/$NAME.saver" $SCENES
for SCENE in $SCENES; do
  swift scripts/verify-chart-symbol-colours.swift "Resources/$(plutil -extract chart.asset raw -o - "$SCENE")"
done
swift scripts/verify-bundle-load.swift "$SAVER_ROOT/build/$NAME.saver" "$OUT/snapshots" | tee "$OUT/dynamic-load.log"

# Preview clips rendered by the native renderer from the same scene files: two light periods each.
swift build --disable-sandbox --package-path . --product OpenHelmChartSaverPreview >/dev/null
PREVIEW="$(swift build --disable-sandbox --package-path . --show-bin-path)/OpenHelmChartSaverPreview"
for SCENE in $SCENES; do
  ID=$(plutil -extract id raw -o - "$SCENE")
  PERIOD=$(plutil -extract light.periodSeconds raw -o - "$SCENE")
  FRAMES=$(python3 -c "print(round(2 * $PERIOD * 30))")
  FRAME_DIR=$(mktemp -d)
  "$PREVIEW" --scene "$SAVER_ROOT/$SCENE" --resources "$SAVER_ROOT/Resources" \
    --width 1728 --height 1117 --scale 1 --frames "$FRAMES" --fps 30 --snapshot "$FRAME_DIR/frame.png"
  ffmpeg -loglevel error -y -framerate 30 -i "$FRAME_DIR/frame-%04d.png" \
    -vf "crop=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart "$OUT/$ID.mp4"
  rm -rf "$FRAME_DIR"
done

STAGE="$OUT/$NAME"
mkdir -p "$STAGE"
ditto "$SAVER_ROOT/build/$NAME.saver" "$STAGE/$NAME.saver"
cp Scenes/lighthouses.README.md "$STAGE/README.md"
cp ../LICENSE "$STAGE/LICENSE"
cp Scenes/tynningo-open-preview.credits.txt "$STAGE/CREDITS-Tynningo.txt"
cp Scenes/alcatraz-noaa-preview.credits.txt "$STAGE/CREDITS-Alcatraz.txt"
cp -L Scenes/alcatraz-noaa-preview.include/NOAA-ENC-USER-AGREEMENT.html "$STAGE/"
codesign --verify --deep --strict "$STAGE/$NAME.saver"
ZIP="$OUT/OpenHelm-Lighthouses-macOS.zip"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE" "$ZIP"
rm -rf "$STAGE"

# Re-verify what a user actually gets: unzip into a scratch dir and check the bundle there.
CHECK=$(mktemp -d)
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/$NAME/$NAME.saver"
scripts/verify-bundle.sh "$CHECK/$NAME/$NAME.saver"
rm -rf "$CHECK"

(cd "$OUT" && shasum -a 256 OpenHelm-Lighthouses-macOS.zip ./*.mp4 > SHA256SUMS)
python3 - "$OUT" "$SAVER_ROOT/build/$NAME.saver" <<'PY'
import json, plistlib, subprocess, sys
from pathlib import Path
out, bundle = Path(sys.argv[1]), Path(sys.argv[2])
info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
receipt = dict(
    name=info['CFBundleDisplayName'], identifier=info['CFBundleIdentifier'],
    version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
    sourceCommit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    sourceDirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip()),
    architectures=subprocess.check_output(['lipo', '-archs', str(bundle / 'Contents/MacOS/OpenHelmChartSaver')], text=True).split(),
    scenes=sorted(p.name for p in (bundle / 'Contents/Resources/Scenes').iterdir()),
    signing='Ad-hoc. Not Developer ID signed, not notarised.',
    artifacts=dict(line.split()[::-1] for line in (out / 'SHA256SUMS').read_text().splitlines()),
)
(out / 'RELEASE-RECEIPT.json').write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
print(json.dumps(receipt, indent=2, ensure_ascii=False))
PY
