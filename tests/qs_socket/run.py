#!/usr/bin/env python3
"""Probe: Quickshell.Io.Socket holds events.subscribe, reconnects after a server
restart, and imports a relative .mjs (ROADMAP M1). Sandboxed herdr, plus a
windowless Quickshell instance (no panel is created).

    python3 -I tests/qs_socket/run.py        # needs a Wayland session; exit 0 = pass
"""
import os, signal, subprocess, sys, time

os.environ.setdefault("HERDR_BIN", "/usr/bin/herdr")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from pty_attach import Sandbox


def main():
    sb = Sandbox()
    qs = subprocess.Popen(["quickshell", "-n", "-p", HERE], env={**os.environ, "SPIKE_SOCK": sb.api},
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        time.sleep(3)
        sb.cli("workspace", "create", "--label", "alpha", "--no-focus")
        time.sleep(1)
        sb.cli("server", "stop")
        sb.server.wait(timeout=8)
        time.sleep(2.5)
        sb.server = subprocess.Popen([sb.server.args[0], "server"], env=sb.env, start_new_session=True,
                                     stdout=open(f"{sb.root}/server.log", "a"), stderr=subprocess.STDOUT)
        for _ in range(60):
            if os.path.exists(sb.api):
                break
            time.sleep(0.1)
        time.sleep(1.5)
        sb.cli("workspace", "create", "--label", "gamma", "--no-focus")
        time.sleep(2.5)
    finally:
        qs.send_signal(signal.SIGTERM)
        try:
            out = qs.communicate(timeout=6)[0]
        except subprocess.TimeoutExpired:
            os.killpg(qs.pid, signal.SIGKILL)
            out = qs.communicate()[0]
        sb.close()
    lines = [l for l in out.splitlines() if "SPIKE" in l]
    text = "\n".join(lines)
    checks = {
        ".mjs import works": 'mjs-ok:x {"w1:p1":5}' in text,
        "subscription acked": '"subscription_started"' in text,
        "workspace event delivered": "workspace_created" in text and '"label":"alpha"' in text,
        "disconnect seen": "connected=false" in text,
        "reconnected and re-subscribed after restart": text.count('"subscription_started"') >= 2
                                                         and '"label":"gamma"' in text,
    }
    for name, ok in checks.items():
        print(("PASS " if ok else "FAIL ") + name)
    if not all(checks.values()):
        print(text)
    sys.exit(0 if all(checks.values()) else 1)


if __name__ == "__main__":
    main()
