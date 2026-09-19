# INSTALL.md — agent runbook

You are installing **My WebBridge** on the user's machine. Follow these steps in order. Do not
skip the human confirmation step, and do not claim success unless `scripts/behavior_test.py`
reports all checks green.

**End state:** the daemon is running and autostarts on login, the Chrome extension is loaded and
connected, the `my-webbridge` skill is installed in the requested agent skills dir(s), and the
behavior tests pass. The user can then ask their agent to drive the browser.

---

## How to narrate progress (required)

The user may be non-technical and easily frustrated. Announce each step as a running checklist,
one action at a time, and never dump the whole runbook at once:

```
[1/6] Installing dependencies...        ✓
[2/6] Installing skill + extension...   ✓
[3/6] Starting background service...    ✓
[4/6] Your turn — loading the extension in Chrome:
      <one instruction, then wait>
[5/6] Verifying browser connection...   ✓
[6/6] Running behavior tests...         ✓ (9/9)
You're armed. Try: "use the my-webbridge skill to open example.com"
```

Rules: confirm each mechanical step with `✓`; at the human step, wait for the user after **every
instruction**; if the user is confused, re-explain differently (offer the fallback), don't repeat
verbatim; never claim success until the tests pass.

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
| `--extension-dir PATH` | visible dir (below) | Where to copy `extension/` for Chrome |

What it does:

1. Creates `daemon/.venv` and installs `daemon/requirements.txt`.
2. Copies `skill/` into the requested agent skills dir(s):
   - `~/.claude/skills/my-webbridge/`
   - `${XDG_CONFIG_HOME:-~/.config}/opencode/skills/my-webbridge/`
3. Copies `extension/` to a **visible, one-click** directory so the human can find it in Chrome's
   file picker (never `~/Library`, which is hidden):
   - macOS: `~/Desktop/My Web Bridge Extension`
   - Linux: `~/my-webbridge-extension`
   - Override with `--extension-dir PATH`. The path is remembered in `logs/install.env`.
4. Renders `daemon/service/launchd.plist.template` (macOS) or
   `daemon/service/systemd.service.template` (Linux) with the resolved repo path + venv python,
   installs it as a user service, and starts it.
5. Waits for `GET /status` and prints the result.

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

The unpacked extension **cannot** be installed programmatically; a human must click through
Chrome. Assume the user is **non-technical and easily frustrated** — do the navigating for them
and give **one instruction at a time**.

Run the helper first; it reveals the folder in Finder/File Manager, copies the path to the
clipboard, and opens `chrome://extensions`:

```bash
./scripts/reveal-extension.sh
# prints: extension dir: /Users/<you>/Desktop/My Web Bridge Extension
```

The extension was installed to a **visible** directory at Step 1 (macOS:
`~/Desktop/My Web Bridge Extension`; Linux: `~/my-webbridge-extension`). Never ask the user to
navigate `~/Library` — it is hidden and will not appear in the picker.

Then give the user, **one line at a time, waiting after each**:

1. "In Chrome, top-right: turn on **Developer mode**." *(wait for "ok")*
2. "Click **Load unpacked**." *(wait)*
3. "In the left sidebar click **Desktop**, then double-click **My Web Bridge Extension**,
   then click **Open**." *(macOS; adjust for Linux)* *(wait)*
4. "You should see **My Web Bridge** in the list — tell me when it's there."

Fallback if they can't find the folder: *"In the file dialog press **Cmd+Shift+G**, then
**Cmd+V**, then **Enter** — I already copied the path for you."* (Linux: `Ctrl+L`, paste, Enter.)

If they seem stuck or confused, **re-explain differently** rather than repeating verbatim, and
offer the fallback. Then **stop and wait for confirmation** before continuing.

Note: if the extension shows as loaded but never connects, ask them to click **Reload** on the
extension card, and confirm the daemon is running.

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
| User can't find the extension folder | Run `./scripts/reveal-extension.sh`; fallback Cmd+Shift+G → paste → Enter (Ctrl+L on Linux) |
| `behavior_test.py` timeout on navigate | Chrome window may be blocked; bring it to front and retry |
| Chrome shows "Developer mode extensions" warning | Normal for unpacked extensions; it can be dismissed |

---

## Uninstall

```bash
./scripts/uninstall.sh            # stops+removes service, removes skill + extension copies
./scripts/uninstall.sh --purge    # also removes daemon/.venv
```

Then remove the extension from `chrome://extensions`.
