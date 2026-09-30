#!/bin/sh
# Stage a complete signed bundle so removed artwork cannot survive an upgrade.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DESTINATION="$HOME/Library/Screen Savers/1puni-Tynningo.saver"
mkdir -p "$(dirname "$DESTINATION")"
STAGE=$(mktemp -d "$(dirname "$DESTINATION")/.1puni-install.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM

ditto "$ROOT/build/1puni-Tynningo.saver" "$STAGE/new.saver"
codesign --verify --deep --strict "$STAGE/new.saver"
if [ -e "$DESTINATION" ]; then mv "$DESTINATION" "$STAGE/previous.saver"; fi
if ! mv "$STAGE/new.saver" "$DESTINATION"; then
  if [ -e "$STAGE/previous.saver" ]; then mv "$STAGE/previous.saver" "$DESTINATION"; fi
  exit 1
fi
codesign --verify --deep --strict "$DESTINATION"
echo "Installed $DESTINATION"
