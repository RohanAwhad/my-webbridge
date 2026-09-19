# INSTALL.md — agent runbook

You are installing **My WebBridge** on the user's machine. Follow these steps in order. Do not
skip the human confirmation step, and do not claim success unless `scripts/behavior_test.py`
reports all checks green.

**End state:** the daemon is running and autostarts on login, the Chrome extension is loaded and
connected, the `my-webbridge` skill is installed in the requested agent skills dir(s), and the
behavior tests pass. The user can then ask their agent to drive the browser.

---

## Prerequisites

Verify these exist before starting:

```bash
python3 --version        # >= 3.9
git --version
# Chrome or Chromium must be installed (for the extension)
```

On macOS: `/Applications/Google Chrome.app` (or Chromium).
On Linux: `google-chrome`, `chromium`, or `chromium-browser` on `PATH`.

If `python3` is missing, stop and ask the user to install it.

---

## Step 0 — Get the repo

If you are already inside the repo, skip. Otherwise:

```bash
git clone https://github.com/RohanAwhad/my-webbridge.git
cd my-webbridge
```

---

## Step 1 — Run the installer

```bash
./scripts/install.sh
```

Flags (defaults chosen by the user at kickoff):

| Flag | Default | Meaning |
|------|---------|---------|
| `--agents claude\|opencode\|both` | `claude` | Where to copy `skill/` |
| `--no-service` | off | Skip the autostart service; run the daemon manually |
| `--port N` | `10087` | Daemon port |

What it does:

1. Creates `daemon/.venv` and installs `daemon/requirements.txt`.
2. Copies `skill/` into the requested agent skills dir(s):
   - `~/.claude/skills/my-webbridge/`
   - `${XDG_CONFIG_HOME:-~/.config}/opencode/skills/my-webbridge/`
3. Renders `daemon/service/launchd.plist.template` (macOS) or
   `daemon/service/systemd.service.template` (Linux) with the resolved repo path + venv python,
   installs it as a user service, and starts it.
4. Waits for `GET /status` and prints the result.

If the user asked for `--no-service`, start the daemon yourself instead:

```bash
./scripts/daemon-ctl.sh start      # start / stop / restart / status / logs
```

**Expected:** installer prints `daemon is up at http://127.0.0.1:10087` with
`extension_connected: false`. That is correct at this stage.

---

## Step 2 — Verify the daemon

```bash
curl -s http://127.0.0.1:10087/status
```

Expect:

```json
{"running": true, "version": "0.1.0", "port": 10087, "extension_connected": false, "uptime_seconds": ...}
```

If `running` is not true, see Troubleshooting before continuing.

---

## Step 3 — Load the extension (human-in-the-loop)

The unpacked extension **cannot** be installed programmatically; a human must click. Tell the
user, concisely:

1. Open `chrome://extensions` in Chrome.
2. Toggle **Developer mode** (top-right) ON.
3. Click **Load unpacked**.
4. Select this repo's `extension/` directory — print the absolute path for them:

```bash
echo "$(pwd)/extension"
```

You may open the page for them:

```bash
# macOS
open -a "Google Chrome" "chrome://extensions"
# Linux
google-chrome "chrome://extensions" || chromium "chrome://extensions"
```

Then **stop and wait for the user to confirm** the extension is loaded. Do not poll forever; if
they say it's loaded, proceed to Step 4.

Note: if the extension shows as loaded but never connects, the user may need to enable
**Allow access to file URLs** / ensure the daemon is running, and reload the extension.

---

## Step 4 — Wait for the extension to connect

The extension retries on its own with backoff. Poll (up to ~60s):

```bash
for i in $(seq 1 30); do
  curl -s http://127.0.0.1:10087/status | grep -q '"extension_connected":true' && echo CONNECTED && break
  sleep 2
done
```

Or just run the behavior test, which polls for you:

```bash
./scripts/behavior_test.py --wait-extension 60
```

If it never connects, see Troubleshooting.

---

## Step 5 — Run the behavior tests

```bash
./scripts/behavior_test.py
```

This spins up a throwaway local HTTP server serving `fixtures/testpage.html`, then drives the
browser through the daemon and asserts each step. Expected checks:

| Check | What it proves |
|-------|----------------|
| `GET /status` | daemon reachable, `running: true` |
| `extension_connected` | extension ↔ daemon WS is live |
| `navigate` | extension can create/attach a tab + tab group |
| `snapshot` | CDP accessibility tree works and contains the test button |
| `evaluate` | JS execution returns the expected page title |
| `fill` | form input setters + events fire |
| `click` → `evaluate` | real DOM event handling round-trips |
| `screenshot` | `Page.captureScreenshot` returns non-empty data |
| `list_tabs` | session tab group is tracked |
| `close_session` | cleanup closes the tab group |

Expected final line: `ALL CHECKS PASSED (n/n)`.

If any check fails, report the failing check and its error verbatim. Do not claim installation
succeeded.

---

## Step 6 — Confirm the skill is installed

```bash
ls -l ~/.claude/skills/my-webbridge/SKILL.md
# if --agents opencode/both:
ls -l "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills/my-webbridge/SKILL.md"
```

Then tell the user they are armed. Example prompt to give them:

> Use the my-webbridge skill to open https://example.com, take a snapshot, and read the heading.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `install.sh` fails at pip | Check `python3 --version` >= 3.9 and network access; retry `./scripts/install.sh` |
| `/status` unreachable | `./scripts/daemon-ctl.sh status` and `./scripts/daemon-ctl.sh logs` |
| `extension_connected: false` | Daemon down, or extension not loaded, or extension needs reload after daemon start |
| Port already in use | Reinstall with `--port 10088` (and pass the same `--port` to `daemon-ctl.sh` and `behavior_test.py`) |
| macOS: service won't start | `launchctl unload ~/Library/LaunchAgents/com.rawhad.my-webbridge.plist` then re-run `install.sh` |
| Linux: service won't start | `systemctl --user status my-webbridge` and `journalctl --user -u my-webbridge` |
| `behavior_test.py` timeout on navigate | Chrome window may be blocked; bring it to front and retry |
| Chrome shows "Developer mode extensions" warning | Normal for unpacked extensions; it can be dismissed |

---

## Uninstall

```bash
./scripts/uninstall.sh            # stops+removes service, removes skill copies, keeps venv
./scripts/uninstall.sh --purge    # also removes daemon/.venv
```

Then remove the extension from `chrome://extensions`.
