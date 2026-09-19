#!/usr/bin/env python3
"""End-to-end behavior tests for My WebBridge.

Serves fixtures/testpage.html on a throwaway local port, then drives the real
browser through the daemon and asserts each link in the chain works:
daemon -> websocket -> extension -> CDP -> page.

Usage:
    ./scripts/behavior_test.py [--port 10087] [--wait-extension 60]
"""
from __future__ import annotations

import argparse
import functools
import http.server
import json
import socket
import sys
import threading
import time
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURES = REPO_ROOT / "fixtures"
SESSION = "webbridge-selftest"


def _post(port: int, action: str, args: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/command",
        data=json.dumps({"action": action, "args": args or {}, "session": SESSION}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=150) as resp:
        body = json.loads(resp.read())
    if not body.get("ok"):
        raise RuntimeError(f"{action}: {body.get('error')}")
    return body["data"]


def _get(port: int, path: str) -> dict:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=10) as resp:
        return json.loads(resp.read())


def _free_port() -> int:
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args) -> None:
        pass


def _start_fixture_server() -> tuple[http.server.ThreadingHTTPServer, int]:
    port = _free_port()
    handler = functools.partial(_QuietHandler, directory=str(FIXTURES))
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, port


def _wait_for_extension(port: int, timeout: int) -> bool:
    deadline = time.time() + timeout
    announced = False
    while time.time() < deadline:
        try:
            status = _get(port, "/status")
        except Exception:
            status = {}
        if status.get("extension_connected"):
            return True
        if not announced:
            print("... waiting for the browser extension to connect")
            print("    chrome://extensions -> Developer mode -> Load unpacked -> extension/")
            announced = True
        time.sleep(2)
    return False


def _assert(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def main() -> int:
    parser = argparse.ArgumentParser(description="My WebBridge behavior tests")
    parser.add_argument("--port", type=int, default=10087)
    parser.add_argument("--wait-extension", type=int, default=60)
    args = parser.parse_args()
    port = args.port

    try:
        status = _get(port, "/status")
    except Exception as exc:
        print(f"FAIL: daemon not reachable on port {port}: {exc}")
        print("Start it with: ./scripts/daemon-ctl.sh start")
        return 2
    if not status.get("running"):
        print("FAIL: daemon /status reports running=false")
        return 2

    if not _wait_for_extension(port, args.wait_extension):
        print("FAIL: no browser extension connected.")
        print("Load extension/ via chrome://extensions -> Developer mode -> Load unpacked.")
        return 2

    httpd, fixture_port = _start_fixture_server()
    base_url = f"http://127.0.0.1:{fixture_port}/testpage.html"
    state: dict = {"navigated": False}
    results: list[tuple[str, bool, str]] = []

    def check(name: str, fn) -> None:
        try:
            results.append((name, True, fn() or ""))
        except Exception as exc:
            results.append((name, False, str(exc)))

    def c_navigate() -> str:
        data = _post(port, "navigate", {"url": base_url, "newTab": True, "group_title": SESSION})
        _assert(data.get("success"), f"success=false: {data}")
        _assert(base_url in (data.get("url") or ""), f"unexpected url: {data.get('url')}")
        state["navigated"] = True
        return f"tabId={data.get('tabId')}"

    def c_snapshot() -> str:
        data = _post(port, "snapshot")
        rows = data.get("tree", {}).get("rows", [])
        _assert("Click me" in "\n".join(rows), "test button absent from a11y tree")
        return f"{len(rows)} nodes"

    def c_evaluate() -> str:
        value = _post(port, "evaluate", {"code": "document.title"}).get("value")
        _assert(value == "My WebBridge Test", f"title={value!r}")
        return "js ok"

    def c_fill() -> str:
        data = _post(port, "fill", {"selector": "#name", "value": "webbridge"})
        _assert(data.get("success"), f"fill failed: {data}")
        value = _post(port, "evaluate", {"code": "document.querySelector('#name').value"}).get("value")
        _assert(value == "webbridge", f"input value={value!r}")
        return "input set"

    def c_click() -> str:
        data = _post(port, "click", {"selector": "#go"})
        _assert(data.get("success"), f"click failed: {data}")
        value = _post(port, "evaluate", {"code": "document.querySelector('#result').textContent"}).get("value")
        _assert(value == "clicked:webbridge", f"result={value!r}")
        return "event round-trip"

    def c_screenshot() -> str:
        data = _post(port, "screenshot", {"format": "jpeg", "quality": 50})
        _assert(len(data.get("data") or "") > 0, "empty screenshot data")
        return f"{data.get('sizeBytes')} bytes"

    def c_list_tabs() -> str:
        tabs = _post(port, "list_tabs").get("tabs", [])
        _assert(any(base_url in (t.get("url") or "") for t in tabs), f"fixture tab missing: {tabs}")
        return f"{len(tabs)} tab(s)"

    def c_network() -> str:
        requests = _post(port, "network", {"action": "list", "filter": "testpage.html"}).get("requests", [])
        _assert(len(requests) >= 1, "no network entry for fixture")
        return f"{len(requests)} request(s)"

    def c_close_session() -> str:
        data = _post(port, "close_session")
        _assert(data.get("success"), f"close failed: {data}")
        _assert((data.get("closed") or 0) >= 1, "nothing closed")
        state["navigated"] = False
        return f"closed {data.get('closed')}"

    print(f"fixture: {base_url}")
    print(f"daemon:  http://127.0.0.1:{port}\n")

    try:
        check("navigate", c_navigate)
        check("snapshot", c_snapshot)
        check("evaluate", c_evaluate)
        check("fill", c_fill)
        check("click", c_click)
        check("screenshot", c_screenshot)
        check("list_tabs", c_list_tabs)
        check("network", c_network)
        check("close_session", c_close_session)
    finally:
        if state.get("navigated"):
            try:
                _post(port, "close_session")
            except Exception:
                pass
        httpd.shutdown()

    width = max(len(name) for name, _, _ in results)
    passed = sum(1 for _, ok, _ in results if ok)
    for name, ok, detail in results:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name.ljust(width)}  {detail}")
    print()
    if passed == len(results):
        print(f"ALL CHECKS PASSED ({passed}/{len(results)})")
        return 0
    print(f"FAILED: {len(results) - passed}/{len(results)} checks failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
