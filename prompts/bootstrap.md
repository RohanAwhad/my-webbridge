# Bootstrap prompt

Paste this into a fresh Claude Code / opencode session (from any directory):

---

Install the **My WebBridge** package on this machine.

1. Clone `https://github.com/rawhad/my-webbridge.git` into `~/1_Projects/my-webbridge`
   (or a temp dir if that exists as a non-repo) and `cd` into it.
2. Read `INSTALL.md` and follow it top to bottom.
3. Use `./scripts/install.sh --agents claude` (switch to `--agents both` if I use opencode too).
4. When you reach the Chrome extension step, stop and tell me exactly what to click; wait for my
   confirmation before continuing.
5. Then run `./scripts/behavior_test.py` and show me the pass/fail table. Only say it's installed
   if every check passes.

Give me the example prompt to use the skill at the end.

---

Shorter variant (if already cloned and inside the repo):

---

Follow `INSTALL.md` in this repo to install My WebBridge, including the Chrome step and the
behavior tests. Report the test table and tell me when I'm armed.
