#!/bin/bash
# Keyspace one-line installer.
#   curl -fsSL https://raw.githubusercontent.com/lakshya-rohila/keyspace/main/get.sh | bash
# Downloads the latest release, installs it to /Applications and launches it.
set -euo pipefail

REPO="${KEYSPACE_REPO:-lakshya-rohila/keyspace}"
URL="${KEYSPACE_URL:-https://github.com/$REPO/releases/latest/download/Keyspace-macOS.zip}"
APP="/Applications/Keyspace.app"

if [ "$(uname)" != "Darwin" ]; then
  echo "Keyspace only runs on macOS." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Downloading Keyspace…"
curl -fL --progress-bar "$URL" -o "$TMP/Keyspace.zip"

echo "→ Installing to /Applications…"
ditto -x -k "$TMP/Keyspace.zip" "$TMP"
pkill -x Keyspace 2>/dev/null || true      # quitting Keyspace un-hides every app
rm -rf "$APP"
cp -R "$TMP/Keyspace.app" "$APP"
# The app isn't notarized; clear the download quarantine so it opens without the Gatekeeper prompt.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "✓ Keyspace installed. Look for the grid icon in your menu bar."
echo "  ⌥⇧ + number puts the front app on a key, ⌥ + number switches."
