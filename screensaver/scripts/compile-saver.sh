#!/bin/sh
# Compile the saver plug-in executable. Usage: compile-saver.sh OUTPUT [ARCH...] (default arm64).
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SAVER_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT=$1
shift
[ "$#" -gt 0 ] || set -- arm64

export SWIFTPM_MODULECACHE_OVERRIDE="$SAVER_ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$SAVER_ROOT/.build/clang-cache"
SLICES=
for ARCH in "$@"; do
  TARGET="$ARCH-apple-macosx14.0"
  swift build --disable-sandbox --package-path "$SAVER_ROOT" -c release --triple "$TARGET" --product OpenHelmChartSaverCore
  BIN_DIR=$(swift build --disable-sandbox --package-path "$SAVER_ROOT" -c release --triple "$TARGET" --show-bin-path)
  test -f "$BIN_DIR/libOpenHelmChartSaverCore.a"
  SLICE="$OUTPUT.$ARCH"
  xcrun swiftc \
    -module-cache-path "$SAVER_ROOT/.build/module-cache" \
    -target "$TARGET" -O -whole-module-optimization -parse-as-library \
    -module-name OpenHelmChartSaver \
    -I "$BIN_DIR/Modules" -L "$BIN_DIR" -lOpenHelmChartSaverCore \
    -framework AppKit -framework QuartzCore -framework ScreenSaver -framework ImageIO \
    -emit-library -Xlinker -bundle \
    -o "$SLICE" \
    "$SAVER_ROOT/Sources/OpenHelmChartSaver/OpenHelmChartSaverView.swift"
  SLICES="$SLICES $SLICE"
done
# shellcheck disable=SC2086
xcrun lipo -create $SLICES -output "$OUTPUT"
# shellcheck disable=SC2086
rm -f $SLICES
chmod 755 "$OUTPUT"
