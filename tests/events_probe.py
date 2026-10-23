#!/usr/bin/env python3
"""Probe: herdr event-subscription facts the bar (ROADMAP M1) relies on.

Runs against a THROWAWAY server (tests/pty_attach.py Sandbox). Stdlib only.

    python3 -I tests/events_probe.py            # stock /usr/bin/herdr
    HERDR_BIN=herdr python3 -I tests/events_probe.py

Observed on stock 0.9.5: pane.agent_status_changed needs a pane_id, and
pane.updated does not fire for blocked/idle transitions. Exit 0 = all hold.
"""
import json, os, socket, sys, time

os.environ.setdefault("HERDR_BIN", "/usr/bin/herdr")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pty_attach import Sandbox


def subscribe(api, subs, wait=1.5):
    s = socket.socket(socket.AF_UNIX)
    s.connect(api)
    s.sendall((json.dumps({"id": "p", "method": "events.subscribe",
                           "params": {"subscriptions": subs}}) + "\n").encode())
    return s, s.makefile()


def drain(s, f, wait=1.5):
    s.settimeout(wait)
    out = []
    try:
        for line in f:
            out.append(json.loads(line))
    except (socket.timeout, TimeoutError):
        pass
    return out


def main():
    sb = Sandbox()
    fails = 0

    def check(name, ok, detail=""):
        nonlocal fails
        fails += 0 if ok else 1
        print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail and not ok else ""))

    try:
        sb.cli("workspace", "create", "--label", "a", "--no-focus")
        pane = sb.json("pane", "list")["panes"][0]["pane_id"]

        s, f = subscribe(sb.api, [{"type": "pane.agent_status_changed"}])
        reply = json.loads(f.readline())
        check("status subscription without pane_id is rejected",
              reply.get("error", {}).get("code") == "invalid_request", reply)
        s.close()

        s1, f1 = subscribe(sb.api, [{"type": "pane.agent_status_changed", "pane_id": pane}])
        s2, f2 = subscribe(sb.api, [{"type": "pane.updated"}])
        check("acks come first", json.loads(f1.readline())["result"]["type"] == "subscription_started"
              and json.loads(f2.readline())["result"]["type"] == "subscription_started")
        for state in ("working", "blocked", "idle"):
            sb.cli("pane", "report-agent", "--source", "probe", "--agent", "claude", "--state", state, pane)
            time.sleep(0.6)
        seen = [e["data"]["agent_status"] for e in drain(s1, f1)]
        check("per-pane stream delivers every transition", seen == ["working", "blocked", "idle"], seen)
        upd = [(e["data"].get("pane") or {}).get("agent_status") for e in drain(s2, f2)]
        check("pane.updated does not carry blocked/idle", "blocked" not in upd and "idle" not in upd, upd)
    finally:
        sb.close()
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
