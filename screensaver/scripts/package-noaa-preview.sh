#!/bin/sh
# Assemble the reviewed Alcatraz candidate only. Never installs or uploads.
set -eu
SAVER_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCENE="$SAVER_ROOT/Scenes/alcatraz-noaa-preview.json"
BUNDLE="$SAVER_ROOT/build/OpenHelmChartSaver.saver"
"$SAVER_ROOT/scripts/build-bundle.sh" "$SCENE" "$SAVER_ROOT/Scenes/alcatraz-noaa-preview.plist"
swift "$SAVER_ROOT/scripts/verify-chart-symbol-colours.swift" "$SAVER_ROOT/Resources/alcatraz-noaa-preview@2x.png"
STAGE=$(mktemp -d "$SAVER_ROOT/build/alcatraz-package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
OUT="$STAGE/alcatraz-preview"
mkdir -p "$OUT"
cp "$SAVER_ROOT/Scenes/alcatraz-noaa-preview.md" "$BUNDLE/Contents/Resources/README.md"
cp "$SAVER_ROOT/../LICENSE" "$BUNDLE/Contents/Resources/LICENSE"
cp "$SAVER_ROOT/Provenance/noaa/ENC_Agreement.html" "$BUNDLE/Contents/Resources/NOAA-ENC-USER-AGREEMENT.html"
cp "$SAVER_ROOT/Provenance/noaa/source-manifest.json" "$BUNDLE/Contents/Resources/source-manifest.json"
cp "$SAVER_ROOT/Provenance/noaa/build-receipt.json" "$BUNDLE/Contents/Resources/build-receipt.json"
codesign --force --deep --sign - "$BUNDLE"
"$SAVER_ROOT/scripts/verify-bundle.sh" "$BUNDLE"
# Explicit whitelist: fail if any unrelated chart or resource entered assembly.
python3 - "$BUNDLE" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]) / 'Contents/Resources'
expected = {'scene.json', 'alcatraz-noaa-preview@2x.png',
            'alcatraz-noaa-preview-light-visibility@2x.png', 'README.md',
            'NOAA-ENC-USER-AGREEMENT.html', 'source-manifest.json', 'build-receipt.json', 'LICENSE'}
assert {p.name for p in root.iterdir()} == expected, 'unexpected bundle resource'
assert all(p.is_file() and not p.is_symlink() for p in root.iterdir())
PY
cp "$SAVER_ROOT/Scenes/alcatraz-noaa-preview.md" "$OUT/README.md"
cp "$SAVER_ROOT/../LICENSE" "$OUT/LICENSE"
cp "$SAVER_ROOT/Provenance/noaa/ENC_Agreement.html" "$OUT/NOAA-ENC-USER-AGREEMENT.html"
ditto "$BUNDLE" "$OUT/OpenHelm Alcatraz Preview.saver"
ditto -c -k --norsrc --noextattr --keepParent "$OUT" "$SAVER_ROOT/build/OpenHelm-Alcatraz-Preview-macOS-arm64.zip"
shasum -a 256 "$SAVER_ROOT/build/OpenHelm-Alcatraz-Preview-macOS-arm64.zip"
