# AGENTS.md — My WebBridge

This repo is a self-contained local browser bridge (FastAPI daemon + Chrome MV3 extension +
agent skill). It is designed to be installed **by an agent** from a fresh session.

## If you were asked to install My WebBridge

Read and execute [`INSTALL.md`](INSTALL.md) top to bottom. Do not improvise the flow — the
runbook encodes the exact order, the human-in-the-loop Chrome step, and the pass criteria.

Summary of the contract:

1. Run `./scripts/install.sh` (creates the venv, copies the skill, copies `extension/` to a
   visible dir, installs the autostart service).
2. Confirm `GET http://127.0.0.1:10087/status` returns `running: true`.
3. Run `./scripts/reveal-extension.sh`, then walk the **human** through `chrome://extensions` →
   Developer mode → **Load unpacked** → the copied extension dir (default
   `~/Desktop/My Web Bridge Extension` on macOS, `~/my-webbridge-extension` on Linux). This step
   cannot be automated; give one instruction at a time and wait for the human to confirm.
4. Poll `/status` until `extension_connected: true`.
5. Run `./scripts/behavior_test.py` and report the pass/fail table. Only claim success if all
   checks pass.

## If you were asked to develop or debug My WebBridge

- Daemon: `daemon/daemon.py` (FastAPI, `POST /command`, `GET /status`, `WS /ws`, 120s timeout).
- Extension: `extension/worker.js` (WS client, tool dispatch, CDP). `manifest.json` declares the
  `debugger`, `tabs`, `tabGroups` permissions and loopback host permissions.
- Skill: `skill/SKILL.md` is the canonical agent-facing contract. Keep the tool table in sync with
  `executeTool()` in `worker.js`.
- Never hardcode an absolute path into a committed file — service units live in
  `daemon/service/*.template` and are rendered by `scripts/install.sh`.
- `logs/`, `daemon/.venv/`, and `__pycache__/` are gitignored. Do not commit them.
