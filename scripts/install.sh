#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_DIR="$REPO_ROOT/daemon"
VENV="$DAEMON_DIR/.venv"
PYTHON_BIN="$VENV/bin/python"
LOG_DIR="$REPO_ROOT/logs"
SERVICE_LABEL="com.rawhad.my-webbridge"
SERVICE_UNIT="my-webbridge"

PORT="10087"
AGENTS="claude"
INSTALL_SERVICE=1
EXTENSION_DIR=""

usage() {
  cat <<EOF
Usage: $0 [--agents claude|opencode|both] [--no-service] [--port N] [--extension-dir PATH]

  --agents MODE          where to install the skill (default: claude)
  --no-service           do not install/start the autostart service
  --port N               daemon port (default: 10087)
  --extension-dir PATH   where to copy extension/ for Chrome's Load unpacked
                         (default: ~/Desktop/My Web Bridge Extension on macOS,
                          ~/my-webbridge-extension elsewhere)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents) AGENTS="${2:?missing value for --agents}"; shift 2 ;;
    --no-service) INSTALL_SERVICE=0; shift ;;
    --port) PORT="${2:?missing value for --port}"; shift 2 ;;
    --extension-dir) EXTENSION_DIR="${2:?missing value for --extension-dir}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

case "$AGENTS" in
  claude|opencode|both) ;;
  *) echo "bad --agents value: $AGENTS (expected claude|opencode|both)" >&2; exit 1 ;;
esac

OS="$(uname -s)"

if [[ -z "$EXTENSION_DIR" ]]; then
  if [[ "$OS" == "Darwin" ]]; then
    EXTENSION_DIR="$HOME/Desktop/My Web Bridge Extension"
  else
    EXTENSION_DIR="$HOME/my-webbridge-extension"
  fi
fi

echo "==> repo:   $REPO_ROOT"
echo "==> python: $PYTHON_BIN"
echo "==> agents: $AGENTS"
echo "==> ext:    $EXTENSION_DIR"
echo "==> port:   $PORT"

mkdir -p "$LOG_DIR"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "==> creating venv"
  python3 -m venv "$VENV"
fi

echo "==> installing daemon requirements"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r "$DAEMON_DIR/requirements.txt"

install_skill() {
  local dest="$1"
  echo "==> installing skill -> $dest"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$REPO_ROOT/skill/." "$dest/"
}

if [[ "$AGENTS" == "claude" || "$AGENTS" == "both" ]]; then
  install_skill "$HOME/.claude/skills/my-webbridge"
fi
if [[ "$AGENTS" == "opencode" || "$AGENTS" == "both" ]]; then
  install_skill "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills/my-webbridge"
fi

echo "==> installing extension -> $EXTENSION_DIR"
rm -rf "$EXTENSION_DIR"
mkdir -p "$EXTENSION_DIR"
cp -R "$REPO_ROOT/extension/." "$EXTENSION_DIR/"
printf 'EXTENSION_DIR=%q\n' "$EXTENSION_DIR" > "$LOG_DIR/install.env"

render() {
  sed -e "s|{{PYTHON}}|$PYTHON_BIN|g" \
      -e "s|{{DAEMON_PY}}|$DAEMON_DIR/daemon.py|g" \
      -e "s|{{REPO_ROOT}}|$REPO_ROOT|g" \
      -e "s|{{PORT}}|$PORT|g" \
      "$1"
}

if [[ "$INSTALL_SERVICE" == "1" ]]; then
  if [[ "$OS" == "Darwin" ]]; then
    PLIST="$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    render "$DAEMON_DIR/service/launchd.plist.template" > "$PLIST"
    echo "==> loading launchd service $SERVICE_LABEL"
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
  elif [[ "$OS" == "Linux" ]]; then
    UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    UNIT="$UNIT_DIR/$SERVICE_UNIT.service"
    mkdir -p "$UNIT_DIR"
    render "$DAEMON_DIR/service/systemd.service.template" > "$UNIT"
    echo "==> enabling systemd user service $SERVICE_UNIT"
    systemctl --user daemon-reload
    systemctl --user enable --now "$SERVICE_UNIT"
  else
    echo "!! unsupported OS ($OS); skipping autostart service" >&2
  fi
else
  echo "==> skipping autostart service (--no-service)"
fi

echo "==> waiting for daemon on port $PORT"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then
    echo "daemon is up at http://127.0.0.1:$PORT"
    curl -s "http://127.0.0.1:$PORT/status"; echo
    echo
    echo "NEXT: load the unpacked extension from:"
    echo "      $EXTENSION_DIR"
    echo "      chrome://extensions -> Developer mode -> Load unpacked"
    echo "      (helper: $REPO_ROOT/scripts/reveal-extension.sh)"
    echo "Then run: $REPO_ROOT/scripts/behavior_test.py --port $PORT"
    exit 0
  fi
  sleep 1
done

echo "!! daemon did not come up; check logs in $LOG_DIR" >&2
exit 1
