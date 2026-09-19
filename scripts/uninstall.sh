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

if [[ "$PURGE" == "1" ]]; then
  echo "==> purging venv + logs"
  rm -rf "$REPO_ROOT/daemon/.venv" "$REPO_ROOT/logs"
fi

echo
echo "Done. Remove the 'My WebBridge' extension manually from chrome://extensions if desired."
