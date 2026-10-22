#!/usr/bin/env python3
"""pty harness: verifies the herdr attach behaviour the cutover (ROADMAP M0.1) relies on.

Runs against a THROWAWAY herdr server (own HOME, XDG dirs and sockets under a
temp dir). It never touches the live session. Stdlib only.

    HERDR_BIN=herdr python3 -I tests/pty_attach.py            # client == server binary
    HERDR_BIN=/usr/bin/herdr HERDR_SERVER_BIN=~/.local/opt/herdr-rootshell/bin/herdr \
        python3 -I tests/pty_attach.py                         # stock client, fork server

Exit code 0 = every check passed.
"""
import fcntl, json, os, select, shutil, signal, struct, subprocess, sys, tempfile, termios, time

CLIENT = os.path.expanduser(os.environ.get("HERDR_BIN") or shutil.which("herdr") or "herdr")
SERVER = os.path.expanduser(os.environ.get("HERDR_SERVER_BIN") or CLIENT)


class Sandbox:
    """Isolated server. Every env var herdr reads for paths points into self.root."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="flock-pty-")
        r = self.root
        self.api = f"{r}/api.sock"
        self.env = {
            "PATH": os.environ["PATH"], "TERM": "xterm-256color", "SHELL": "/usr/bin/bash",
            "HOME": f"{r}/home", "XDG_CONFIG_HOME": f"{r}/cfg", "XDG_STATE_HOME": f"{r}/state",
            "XDG_DATA_HOME": f"{r}/data", "XDG_RUNTIME_DIR": f"{r}/run",
            "HERDR_SOCKET_PATH": self.api, "HERDR_CLIENT_SOCKET_PATH": f"{r}/client.sock",
        }
        for d in ("home", "cfg", "state", "data", "run"):
            os.makedirs(f"{r}/{d}")
        self.server = subprocess.Popen([SERVER, "server"], env=self.env, start_new_session=True,
                                       stdout=open(f"{r}/server.log", "w"), stderr=subprocess.STDOUT)
        for _ in range(50):
            if os.path.exists(self.api):
                break
            time.sleep(0.1)
        status = self.cli("status").stdout
        assert self.api in status, f"refusing to run: status does not show the sandbox socket\n{status}"

    def cli(self, *args):
        return subprocess.run([CLIENT, *args], env=self.env, capture_output=True, text=True, timeout=15)

    def json(self, *args):
        return json.loads(self.cli(*args).stdout)["result"]

    def close(self):
        self.cli("server", "stop")
        try:
            self.server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(self.server.pid, signal.SIGKILL)
        shutil.rmtree(self.root, ignore_errors=True)


class Attach:
    """A herdr client running on a real pty (40x120), like a foot window would give it."""

    def __init__(self, sb, *args):
        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        self.master, self.out = master, b""
        self.proc = subprocess.Popen(
            [CLIENT, *args], env=sb.env, stdin=slave, stdout=slave, stderr=slave, start_new_session=True,
            preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0))
        os.close(slave)

    def pump(self, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if select.select([self.master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(self.master, 65536)
                except OSError:
                    return
                if not chunk:
                    return
                self.out += chunk

    def expect(self, needle, timeout=8):
        end = time.time() + timeout
        while time.time() < end and needle.encode() not in self.out:
            self.pump(0.2)
        return needle.encode() in self.out

    def send(self, data):
        os.write(self.master, data if isinstance(data, bytes) else data.encode())

    def wait(self, timeout=8):
        end = time.time() + timeout
        while time.time() < end and self.proc.poll() is None:
            self.pump(0.2)
        return self.proc.poll()

    def text(self):
        return self.out.decode(errors="replace")

    def kill(self):
        if self.proc.poll() is None:
            os.killpg(self.proc.pid, signal.SIGKILL)
        os.close(self.master)


results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"\n      {detail}" if detail and not ok else ""))


def typed_echo(a, tag):
    """Type a command whose OUTPUT differs from its echo, so only real shell output matches."""
    a.send(f"echo {tag}$((40+2))\n")
    return a.expect(f"{tag}42")


def main():
    print(f"client={CLIENT}\nserver={SERVER}")
    sb = Sandbox()
    live = []
    try:
        pane = sb.json("workspace", "create", "--cwd", sb.root, "--label", "harness")["root_pane"]
        pid, tid = pane["pane_id"], pane["terminal_id"]
        time.sleep(1)  # let the shell start

        r = sb.cli("agent", "get", pid)
        check("agent get on a shell pane -> agent_not_found, exit 1",
              r.returncode == 1 and "agent_not_found" in r.stderr + r.stdout, r.stderr)
        r = sb.cli("agent", "attach", pid)
        check("agent attach on a shell pane -> agent_not_found, exit 1",
              r.returncode == 1 and "agent_not_found" in r.stderr + r.stdout, r.stderr)

        a = Attach(sb, "terminal", "attach", tid); live.append(a)
        check("terminal attach reaches a SHELL pane and passes input through", typed_echo(a, "flkA"), a.text()[-300:])

        b = Attach(sb, "terminal", "attach", tid); live.append(b)
        rc = b.wait()
        check("second attach without --takeover exits 1 with 'already has an attached client'",
              rc == 1 and "already has an attached client" in b.text(), f"rc={rc} {b.text()[-300:]}")
        check("the first attach survives the refused second one", typed_echo(a, "flkA2"))

        c = Attach(sb, "terminal", "attach", tid, "--takeover"); live.append(c)
        rc = a.wait()
        check("--takeover evicts the first attach: it exits 1 with 'taken over'",
              rc == 1 and "taken over" in a.text(), f"rc={rc} {a.text()[-300:]}")
        check("the taking-over attach works", typed_echo(c, "flkC"), c.text()[-300:])

        c.send(b"\x02"); time.sleep(0.3); c.send(b"q")
        rc = c.wait()
        check("Ctrl+B q detaches with exit 0", rc == 0, f"rc={rc} {c.text()[-300:]}")
        check("detach leaves the pane running server-side", any(p["pane_id"] == pid for p in sb.json("pane", "list")["panes"]))

        d = Attach(sb, "terminal", "attach", tid); live.append(d)
        check("re-attach after detach works", typed_echo(d, "flkD"), d.text()[-300:])
        os.killpg(d.proc.pid, signal.SIGHUP)  # what closing a foot window does to the client
        rc = d.wait()
        check("SIGHUP ends the attach client", rc is not None, "still running")
        time.sleep(0.5)
        check("pane survives a client SIGHUP", any(p["pane_id"] == pid for p in sb.json("pane", "list")["panes"]))
        e = Attach(sb, "terminal", "attach", tid); live.append(e)
        check("attach slot is free again after SIGHUP (no takeover needed)", typed_echo(e, "flkE"), e.text()[-300:])
    finally:
        for a in live:
            a.kill()
        sb.close()
    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
