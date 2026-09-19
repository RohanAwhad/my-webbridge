#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$REPO_ROOT/logs/install.env"
OS="$(uname -s)"

if [[ "$OS" == "Darwin" ]]; then
  EXTENSION_DIR="$HOME/Desktop/My Web Bridge Extension"
else
  EXTENSION_DIR="$HOME/my-webbridge-extension"
fi

if [[ -f "$STATE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE"
fi

if [[ ! -d "$EXTENSION_DIR" ]]; then
  echo "extension dir not found: $EXTENSION_DIR" >&2
  echo "run scripts/install.sh first" >&2
  exit 1
fi

echo "extension dir: $EXTENSION_DIR"

if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$EXTENSION_DIR" | pbcopy
  echo "path copied to clipboard (in Chrome's dialog: Cmd+Shift+G, Cmd+V, Enter)"
elif command -v wl-copy >/dev/null 2>&1; then
  printf '%s' "$EXTENSION_DIR" | wl-copy
  echo "path copied to clipboard"
elif command -v xclip >/dev/null 2>&1; then
  printf '%s' "$EXTENSION_DIR" | xclip -selection clipboard
  echo "path copied to clipboard"
fi

if [[ "$OS" == "Darwin" ]]; then
  open -R "$EXTENSION_DIR" 2>/dev/null || true
  open -a "Google Chrome" "chrome://extensions" 2>/dev/null || true
else
  xdg-open "$EXTENSION_DIR" >/dev/null 2>&1 || true
  google-chrome "chrome://extensions" >/dev/null 2>&1 \
    || chromium "chrome://extensions" >/dev/null 2>&1 \
    || true
fi

echo
echo "In Chrome: Developer mode ON -> Load unpacked -> select the folder:"
echo "  $EXTENSION_DIR"
