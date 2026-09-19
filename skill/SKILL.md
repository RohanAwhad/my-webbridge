---
name: my-webbridge
description: |
  My WebBridge lets an agent control a real browser (Chrome/Chromium) — navigate, click, fill, type, screenshot — via a local daemon at http://127.0.0.1:10087. Use when the user wants browser interaction, web automation, or page content reading.
---

# My WebBridge

Local browser bridge mirroring kimi-webbridge: agent → HTTP `/command` → daemon → WebSocket → extension → CDP.

## Commands

POST JSON to `http://127.0.0.1:10087/command`:

```json
{"action": "navigate", "args": {"url": "https://example.com", "newTab": true, "group_title": "My task"}, "session": "task-1"}
```

Every request carries a top-level `session`. One task = one session = one tab group.

The daemon wraps every response as `{"ok": true, "data": {...}}`, or `{"ok": false, "error": "..."}` on failure.

## Tools

| Tool | Args | Returns |
|------|------|---------|
| `navigate` | `url`, `newTab`(bool, default false = reuse current tab), `group_title` | `{success, url, tabId, groupTitle}` |
| `find_tab` | `url`, `active`(bool) | `{success, url, tabId, borrowed}` |
| `snapshot` | — | `{url, title, tree}` with `@e` refs (accessibility tree, text only) |
| `click` | `selector` (@e ref or CSS) | `{success, tag, text}` |
| `fill` | `selector`, `value` | `{success, mode}` (works on input/textarea/contenteditable) |
| `evaluate` | `code` (async allowed) | `{type, value}` |
| `cdp` | `method`, `params` | raw CDP response |
| `screenshot` | `format`(png\|jpeg), `quality` | `{format, data(base64), sizeBytes}` |
| `mouse` | `type`(move\|press\|release\|click\|wheel), `x`, `y`, `button`, `deltaX`, `deltaY` | `{success}` |
| `type` | `text` | `{success, text}` |
| `list_tabs` | — | `{success, groupId, tabs:[{tabId,url,title,active}]}` |
| `close_tab` | — | `{success, closed}` |
| `close_session` | — | `{success, closed}` — closes the whole tab group |
| `network` | `action`(list\|get_response\|clear, default list), `filter`(url substring), `limit`(default 50), `requestId` | `list`: `{requests:[{requestId,url,method,resourceType,status,mimeType,finished}]}`; `get_response`: `{requestId,body,base64Encoded}` |
| `upload` | `selector` (@e ref or CSS, must be `<input type=file>`), `files`(array of absolute local paths) | `{success, selector, files}` |
| `save_as_pdf` | `landscape`, `printBackground`, `scale`, `paperWidth`, `paperHeight`, margins | `{format:"pdf", data(base64), sizeBytes}` |

Single-tab tools act on the session's current tab (the most recently opened/selected one).

## Daemon

`GET /status` → `{running, version, port, extension_connected, uptime_seconds}`. The extension auto-connects/retries on its own.

If the daemon is not running, see the repo `README.md` / `scripts/daemon-ctl.sh`.

## Extension

Load unpacked via `chrome://extensions` → Developer mode → Load unpacked → the repo's `extension/` dir.

## Response Caching

Pipe every daemon response to a JSON file. Keep large snapshots, screenshots, and evaluate results out of main agent context:

```bash
curl -s -X POST http://127.0.0.1:10087/command \
  -H "Content-Type: application/json" \
  -d '{"action":"snapshot","session":"my-task"}' \
  > /tmp/webbridge/my-task/1-snapshot.json
```

Use `/tmp/webbridge/{session}/{step}-{action}.json` to order steps. The main agent only references file paths; a sub-agent reads and reasons about the actual content.

## Sub-Agent Delegation

When a daemon response is large (snapshot, screenshot, big evaluate), **delegate reasoning to a sub-agent** so the a11y tree or base64 doesn't pollute the main agent's context window.

### Pattern

1. Main agent sends a command, caches the response to a JSON file
2. Main agent spawns a `general` sub-agent with:
   - The file path to read
   - A **focused question** (one thing to answer)
3. Sub-agent reads the file, reasons, returns a **single conclusion**
4. Main agent uses that conclusion for the next action

### Example

**Task:** "Find and click the reply button on a Slack thread message about WebBridge."

```
Step 1: Main agent takes a snapshot, caches it
  → curl ... snapshot > /tmp/webbridge/demo/1-snapshot.json

Step 2: Main agent spawns sub-agent:
  Prompt: "Read /tmp/webbridge/demo/1-snapshot.json. The Slack page is open to
           #wg-remote-factory. Find the message where Rohan said 'Took a jab at
           Claude in Chrome'. Return the @e ref of the 'X replies' button near
           that message, or CSS selector of the reply button element."

  Sub-agent reads snapshot, finds the message in the a11y tree, returns:
  → "The '4 replies' button is inside a .c-virtual_list__item near message
     @e56. Use selector .c-message__reply_count or evaluate to find
     document.getElementById('primary-C0BDS49SM99-1786306365.662359-message_text')
     .closest('.c-virtual_list__item').querySelector('.c-message__reply_count')"

Step 3: Main agent uses the returned selector to click:
  → curl ... mouse x=398 y=797 > /tmp/webbridge/demo/2-mouse.json
```

### When to delegate vs go direct

| Situation | Approach |
|-----------|----------|
| Need to understand page layout (snapshot) | **Delegate** — a11y trees are huge |
| Need to search DOM for a specific element (evaluate returning large results) | **Delegate** |
| Already have coordinates/selector, just need to click/fill/type | **Direct** |
| Simple evaluate with small return value | **Direct** |
| Screenshot for visual verification | **Delegate** (base64 is massive) |

### Sub-agent prompt template

```
Read {cached_json_path}. The page is {describe_page_state}. {focused_question}.
Return only the conclusion — coordinates, selector, or observation. Do not
return the full a11y tree or raw response.
```

## Reference

Platform-specific automation guides:

- **[Google Sheets](reference/google-sheets.md)** — Reading/writing data, formula bar patterns, Trusted Types constraints, CDP key events, autocomplete avoidance
