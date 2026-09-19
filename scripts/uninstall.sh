#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_LABEL="com.rawhad.my-webbridge"
SERVICE_UNIT="my-webbridge"
OS="$(uname -s)"
PURGE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    -h|--help) echo "Usage: $0 [--purge]"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$OS" == "Darwin" ]]; then
  PLIST="$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist"
  if [[ -f "$PLIST" ]]; then
    echo "==> removing launchd service"
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
  fi
elif [[ "$OS" == "Linux" ]]; then
  UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$SERVICE_UNIT.service"
  if [[ -f "$UNIT" ]]; then
    echo "==> removing systemd user service"
    systemctl --user disable --now "$SERVICE_UNIT" 2>/dev/null || true
    rm -f "$UNIT"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
fi

for dest in "$HOME/.claude/skills/my-webbridge" \
            "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills/my-webbridge"; do
  if [[ -d "$dest" ]]; then
    echo "==> removing skill $dest"
    rm -rf "$dest"
  fi
done

if [[ -f "$REPO_ROOT/logs/install.env" ]]; then
  # shellcheck disable=SC1090
  source "$REPO_ROOT/logs/install.env"
fi
if [[ -z "${EXTENSION_DIR:-}" ]]; then
  if [[ "$OS" == "Darwin" ]]; then
    EXTENSION_DIR="$HOME/Desktop/My Web Bridge Extension"
  else
    EXTENSION_DIR="$HOME/my-webbridge-extension"
  fi
fi
if [[ -d "$EXTENSION_DIR" ]]; then
  echo "==> removing extension copy $EXTENSION_DIR"
  rm -rf "$EXTENSION_DIR"
fi

if [[ "$PURGE" == "1" ]]; then
  echo "==> purging venv + logs"
  rm -rf "$REPO_ROOT/daemon/.venv" "$REPO_ROOT/logs"
fi

echo
echo "Done. Remove the 'My WebBridge' extension manually from chrome://extensions if desired."
