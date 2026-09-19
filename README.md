# My WebBridge

A minimal, self-contained local browser bridge: an LLM agent (or any HTTP client) drives a real
Chrome/Chromium browser through a local daemon and a Chrome extension over CDP.

```
agent ──HTTP /command──► daemon (127.0.0.1:10087) ◄──WebSocket── extension (in Chrome)
                            │ requestId correlation            │ chrome.debugger / CDP
                            └────────── tool_result ◄──────────┘
```

Everything lives in this repo — daemon, extension, agent skill, install scripts, and tests.

## Layout

```
my-webbridge/
├── daemon/            FastAPI daemon (POST /command, GET /status, WS /ws)
│   ├── daemon.py
│   ├── requirements.txt
│   └── service/       launchd (macOS) + systemd (Linux) unit templates
├── extension/         Chrome MV3 extension (manifest.json + worker.js)
├── skill/             canonical agent skill (SKILL.md + reference/)
├── fixtures/          deterministic test page used by behavior_test.py
├── scripts/           install / uninstall / daemon-ctl / reveal-extension / behavior_test
├── prompts/           ready-to-paste bootstrap prompt for a fresh agent session
└── INSTALL.md         step-by-step install runbook (agent-facing)
```

## Install

Point a fresh Claude Code (or opencode) session at this repo and paste the prompt from
[`prompts/bootstrap.md`](prompts/bootstrap.md). The agent follows [`INSTALL.md`](INSTALL.md):
installs the daemon venv, copies the skill into your agent skills dir, sets up an autostart
service, walks you through loading the unpacked extension, then runs `scripts/behavior_test.py`
to prove the whole path works.

Manual install:

```bash
./scripts/install.sh                # --agents claude|opencode|both, --no-service, --port N
./scripts/daemon-ctl.sh start       # if installed with --no-service
./scripts/reveal-extension.sh       # reveals the extension folder + opens chrome://extensions
./scripts/behavior_test.py          # after loading the extension in Chrome
```

`install.sh` copies `extension/` to a **visible** dir so it's easy to find in Chrome's file
picker — macOS: `~/Desktop/My Web Bridge Extension`, Linux: `~/my-webbridge-extension`
(override with `--extension-dir`). Chrome points there, not into the repo.

## Usage

```bash
curl -s -X POST http://127.0.0.1:10087/command \
  -H 'Content-Type: application/json' \
  -d '{"action":"navigate","args":{"url":"https://example.com","newTab":true,"group_title":"demo"},"session":"demo"}'
```

Then ask your agent: *"use the my-webbridge skill to open example.com and read the heading."*

## Tools

`navigate` · `find_tab` · `list_tabs` · `close_tab` · `close_session` · `snapshot` · `click` ·
`fill` · `evaluate` · `cdp` · `screenshot` · `mouse` · `type` · `network` · `upload` · `save_as_pdf`

See [`skill/SKILL.md`](skill/SKILL.md) for the full contract.

## Notes

- Port `10087` (10086 is often taken by the real Kimi daemon).
- Loopback only; the WS endpoint is not origin-checked (see roadmap).
- Owned by the daemon: `logs/` (gitignored), `daemon/.venv/` (gitignored).

## Roadmap

- [ ] Fix MV3 service-worker idle-kill mid-command (keepalive alone didn't solve it)
- [ ] WS origin check on `/ws` (reject non-extension origins, kimi-style)
- [x] Tools: `network`, `upload`, `save_as_pdf`
- [x] Standalone repo + agent-driven install + behavior tests
