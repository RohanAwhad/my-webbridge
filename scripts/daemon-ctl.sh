#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_DIR="$REPO_ROOT/daemon"
VENV="$DAEMON_DIR/.venv"
PYTHON_BIN="$VENV/bin/python"
LOG_DIR="$REPO_ROOT/logs"
PIDFILE="$LOG_DIR/daemon.pid"
SERVICE_LABEL="com.rawhad.my-webbridge"
SERVICE_UNIT="my-webbridge"

PORT="${PORT:-10087}"
OS="$(uname -s)"
ACTION="${1:-status}"

usage() {
  cat <<EOF
Usage: PORT=10087 $0 {start|stop|restart|status|logs}

Prefers the installed user service (launchd/systemd); falls back to a
background process with a pidfile when no service is installed.
EOF
}

service_installed() {
  if [[ "$OS" == "Darwin" ]]; then
    [[ -f "$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist" ]]
  elif [[ "$OS" == "Linux" ]]; then
    [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$SERVICE_UNIT.service" ]]
  else
    return 1
  fi
}

do_start() {
  if service_installed; then
    if [[ "$OS" == "Darwin" ]]; then
      launchctl load "$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist" 2>/dev/null || true
    else
      systemctl --user start "$SERVICE_UNIT"
    fi
    echo "started via service"
    return
  fi
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "already running (pid $(cat "$PIDFILE"))"
    return
  fi
  mkdir -p "$LOG_DIR"
  nohup "$PYTHON_BIN" "$DAEMON_DIR/daemon.py" --port "$PORT" \
    >> "$LOG_DIR/daemon.out.log" 2>> "$LOG_DIR/daemon.err.log" &
  echo $! > "$PIDFILE"
  echo "started (pid $(cat "$PIDFILE"))"
}

do_stop() {
  if service_installed; then
    if [[ "$OS" == "Darwin" ]]; then
      launchctl unload "$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist" 2>/dev/null || true
    else
      systemctl --user stop "$SERVICE_UNIT"
    fi
    echo "stopped via service"
    return
  fi
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "stopped"
  else
    echo "not running"
  fi
}

do_status() {
  if curl -fsS "http://127.0.0.1:$PORT/status" 2>/dev/null; then
    echo
  else
    echo "daemon not reachable on port $PORT"
  fi
  if service_installed; then
    if [[ "$OS" == "Darwin" ]]; then
      launchctl list | grep -F "$SERVICE_LABEL" || true
    else
      systemctl --user status "$SERVICE_UNIT" --no-pager 2>/dev/null | head -5 || true
    fi
  fi
}

do_logs() {
  mkdir -p "$LOG_DIR"
  tail -n 50 "$LOG_DIR/daemon.out.log" "$LOG_DIR/daemon.err.log" 2>/dev/null || true
}

case "$ACTION" in
  start) do_start ;;
  stop) do_stop ;;
  restart) do_stop; do_start ;;
  status) do_status ;;
  logs) do_logs ;;
  -h|--help) usage ;;
  *) usage >&2; exit 1 ;;
esac
