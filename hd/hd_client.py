#!/usr/bin/env python3
"""hd_client.py — per-pane pass-through terminal client for the herdr fork.

Child process of a plain `foot` window; stdout/stdin is the window pty.
Speaks the fork's JSON control stream via the `herdr control` bridge and
attaches ONE pane:

    server bytes -> stdout  (foot renders them)
    foot bytes   -> bridge  (keystrokes; terminal replies forwarded as
                             terminal.input auto:true while we own the
                             query authority, swallowed while not)

Ground truth lives in docs/architecture-notes.md. Claim discipline follows
rootshell's own client (they fixed the tmux -CC stick-size bug class in
kitknox/rootshell#278): claims only on activation edges (attach on an unowned
tab, hydr focus of our window, explicit `hd take`), everything else
claim:false, claims consumed on send, takeover never automatic, and every
exit path detaches and closes the bridge.
"""
import argparse
import atexit
import base64
import fcntl
import json
import os
import re
import signal
import socket
import shutil
import struct
import subprocess
import sys
import termios
import tty
import threading
import time
import queue as q_mod

VERSION = "0.1.0"
CLIENT_ID = f"hd/{VERSION}"
HISTORY_LIMIT = 1_048_576
REQUEST_TIMEOUT = 15.0
PING_INTERVAL = 30.0
PING_TIMEOUT = 10.0
RECONNECT_CAP = 30.0
MAX_CARRY_BYTES = 256 * 1024
HERDR_ENV_VARS = ("HERDR_ENV", "TERM_PROGRAM")


class StreamError(Exception):
    pass


class StreamClosed(StreamError):
    pass


def herdr_bin():
    """Resolve the fork's herdr binary even when PATH is the minimal set the
    compositor hands out (bar-spawned and Hyprland-exec'd windows don't run
    bashrc, so PATH may miss ~/.local/opt/herdr-rootshell/bin)."""
    bin_path = os.environ.get("HERDR_BIN_PATH") or ""
    if not bin_path:
        try:
            r = subprocess.run(["bash", "-lc", "command -v herdr"],
                               capture_output=True, text=True)
            bin_path = r.stdout.strip()
        except Exception:
            bin_path = ""
    return bin_path or shutil.which("herdr") or "herdr"


def herdr_env(extra=None):
    env = {k: v for k, v in os.environ.items() if k not in HERDR_ENV_VARS}
    env.update(extra or {})
    return env


def call_herdr(*args):
    return subprocess.run(["env", "-u", "HERDR_ENV", "-u", "TERM_PROGRAM",
                           herdr_bin(), *args],
                          capture_output=True, text=True, env=herdr_env())


# --------------------------------------------------------------------------
# VT parsing helpers

MAX_CARRY = 256 * 1024
CRT_FINALS = frozenset(b"cnRtIyOu")   # automatic-reply CSI finals


def _osc_end(buf, i):
    j = i + 2
    n = len(buf)
    while j < n:
        if buf[j] == 0x07:
            return j + 1
        if buf[j] == 0x1B and j + 1 < n and buf[j + 1] == 0x5C:
            return j + 2
        j += 1
    return None


def _string_end(buf, i):     # DCS / APC / PM / SOS / P-series
    j = buf.find(b"\x1b\\", i)
    return (j + 2) if j != -1 else None


def _csi_end(buf, i):
    j = i + 2
    n = len(buf)
    while j < n:
        c = buf[j]
        if 0x40 <= c <= 0x7E:
            return j + 1
        j += 1
    return None


def unit_end(buf: bytes, i: int):
    """End index of the escape-sequence unit starting at i, or None."""
    if i + 1 >= len(buf):
        return None
    nxt = buf[i + 1]
    if nxt == 0x5B:
        return _csi_end(buf, i)
    if nxt == 0x5D:
        return _osc_end(buf, i)
    if 0x50 <= nxt <= 0x5E or nxt == 0x5C:
        return _string_end(buf, i)
    j = i + 1
    while j < len(buf) and 0x20 <= buf[j] <= 0x2F:
        j += 1
    if j >= len(buf):
        return None
    return j + 1


def partition_units(data: bytes, carry: bytearray):
    """Yield complete VT units; incomplete tail goes back into `carry`."""
    buf = bytes(carry) + data
    carry.clear()
    out, i, n = [], 0, len(buf)
    while i < n:
        if buf[i] == 0x1B:
            e = unit_end(buf, i)
            if e is None:
                if len(buf) - i > MAX_CARRY:
                    out.append(buf[i:])
                    i = n
                else:
                    carry.extend(buf[i:])
                break
            out.append(buf[i:e])
            i = e
        else:
            j = buf.find(b"\x1b", i)
            if j == -1:
                out.append(buf[i:])
                i = n
            else:
                out.append(buf[i:j])
                i = j
    return out


def classify_units(units):
    """rootshell's isAutomaticReply, simplified to complete units."""
    reply, typed = [], []
    for u in units:
        if len(u) < 2 or u[0] != 0x1B:
            typed.append(u)
            continue
        nxt = u[1]
        if nxt == 0x5D:                                  # OSC (any)
            reply.append(u)
            continue
        if nxt in (0x50, 0x58, 0x5C, 0x5D, 0x5E, 0x5F):  # DCS/APC/PM/SOS strings
            reply.append(u)
            continue
        if nxt == 0x5B:                                  # CSI
            final = u[-1]
            if final in CRT_FINALS:
                reply.append(u)
                continue
            # Rootshell's own probe class (CSI 18t etc.) — inquiries WE sent
            # are consumed, never forwarded.
            if re.fullmatch(rb"\x1b\[[0-9;]*[t n]", u):
                reply.append(u)
                continue
        typed.append(u)
    return reply, typed


def authority_marker(answers: bool) -> bytes:
    return b"\x1b[?15999$p" if answers else b"\x1b[?15998$p"


def is_authority_probe_reply(u: bytes):
    if u.startswith(b"\x1b[?15999"):
        return True
    if u.startswith(b"\x1b[?15998"):
        return False
    return None


# --------------------------------------------------------------------------
# geometry state (rootshell #278 discipline)

class GeometryState:
    def __init__(self, tab_id: str, shared: bool):
        self.tab_id = tab_id
        self.shared = shared
        self.owner = "unknown"          # unknown | none | mine | other
        self.owner_conn = None
        self.claim_pending = False
        self.last_sent = None

    def note_layout(self, layout, my_conn):
        ctrl = (layout or {}).get("geometry_controller") or {}
        kind, cid = ctrl.get("kind"), ctrl.get("connection_id")
        if not kind or cid is None:
            self.owner = "unknown"
            return
        if cid == my_conn:
            self.owner = "mine"
        else:
            self.owner = "other"
        self.owner_conn = cid

    def request_claim(self):
        self.claim_pending = True

    def build_params(self, rows, cols, cw, ch):
        """Claim only on: first push w/ unknown/none owner, or pending edge."""
        initial = (self.last_sent is None and self.owner in ("unknown", "none"))
        claim = bool(self.claim_pending or initial)
        self.claim_pending = False
        sizing = (rows, cols, cw, ch)
        dedupe = self.last_sent == sizing and not claim
        self.last_sent = sizing
        if dedupe:
            return None
        params = {"tab_id": self.tab_id, "rows": rows, "cols": cols,
                  "cell_width_px": cw, "cell_height_px": ch, "chrome": "none"}
        if self.shared:
            params["claim"] = claim
        return params


# --------------------------------------------------------------------------
# bridge

class Bridge:
    """newline-JSON bridge process over `herdr control`."""

    def __init__(self, client):
        self.client = client
        self.proc = None
        self.opened = None
        self.opened_ready = threading.Event()
        self._wlock = threading.Lock()
        self._idlock = threading.Lock()
        self._rid = 0
        self.pending = {}
        self._watched = {}
        self.quitting = False

    def start(self, session=None):
        env = herdr_env({"HERDR_CONTROL_CLIENT": CLIENT_ID,
                         "HERDR_CONTROL_PROTOCOL": "3"})
        cmd = [herdr_bin(), "control"]
        if session:
            cmd += ["--session", session]
        try:
            self.proc = subprocess.Popen(cmd, env=env, stdin=subprocess.PIPE,
                                         stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, bufsize=0)
        except Exception as e:
            self.client.on_error(f"cannot spawn `herdr control`: {e}")
            return
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        try:
            first = True
            for raw in self.proc.stdout:
                line = raw.decode("utf-8", "replace").rstrip("\n")
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    self.client.on_error("bridge gave a non-JSON line: " + line[:160])
                    continue
                if first:
                    first = False
                    if obj.get("type") == "control.error":
                        self.client.on_error(
                            f"bridge refused: {obj.get('code')}: "
                            f"{obj.get('message','')[:160]}")
                        return
                    if "error" in obj and "result" not in obj:
                        err = obj["error"]
                        self.client.on_error(f"bridge error: {err.get('code')}: "
                                             f"{err.get('message','')[:160]}")
                        return
                    if obj.get("id") == "control" and \
                       obj.get("result", {}).get("type") == "control_opened":
                        self.opened = obj["result"]
                        self.opened_ready.set()
                        # The connect sequence (subscribe/snapshot/attach) issues
                        # requests — never run it on the pump thread, or the
                        # only reader would block on its own replies.
                        threading.Thread(target=self._run_on_opened,
                                         args=(obj["result"],), daemon=True).start()
                        continue
                    self.client.on_error("unexpected first line: " + line[:160])
                    return
                rid, typ, ev = obj.get("id"), obj.get("type"), obj.get("event")
                if rid is not None and typ is None and ev is None:
                    q = self.pending.get(rid)
                    if q:
                        q.put(obj)
                    elif rid in self._watched:
                        method = self._watched.pop(rid)
                        if "error" in obj:
                            err = obj["error"]
                            self.client.log(
                                f"{method} rejected: {err.get('code')}: "
                                f"{err.get('message','')[:160]}")
                    continue
                try:
                    self.client.on_record(rid, typ, ev, obj)
                except Exception as e:
                    self.client.on_error(f"record handler: {type(e).__name__}: {e}")
        finally:
            if not self.quitting:
                self.client.on_error("bridge stream closed")
            for q in list(self.pending.values()):
                q.put({"error": {"code": "stream_closed", "message": "closed"}})

    def _run_on_opened(self, opened):
        try:
            self.client.on_opened(opened)
        except StreamError as e:
            self.client.on_error(str(e))
        except Exception as e:
            self.client.on_error(f"connect: {type(e).__name__}: {e}")

    def send(self, obj):
        with self._wlock:
            self.proc.stdin.write((json.dumps(obj) + "\n").encode())
            self.proc.stdin.flush()

    def request(self, method, params, timeout=REQUEST_TIMEOUT, out_id=None):
        with self._idlock:
            self._rid += 1
            rid = out_id or f"r{self._rid}"
        q = q_mod.Queue()
        self.pending[rid] = q
        self.send({"id": rid, "method": method, "params": params})
        try:
            resp = q.get(timeout=timeout)
        except q_mod.Empty:
            self.pending.pop(rid, None)
            raise StreamError(f"{method} timed out")
        self.pending.pop(rid, None)
        if "error" in resp:
            err = resp["error"]
            raise StreamError(f"{method}: {err.get('code')}: "
                              f"{err.get('message','')[:180]}")
        return resp.get("result", {})

    def fire(self, method, params, prefix="i"):
        with self._idlock:
            self._rid += 1
            rid = f"{prefix}{self._rid}"
        self._watched[rid] = method
        try:
            self.send({"id": rid, "method": method, "params": params})
        except Exception:
            pass

    def close(self):
        self.quitting = True
        try:
            self.send({"id": "control:close", "method": "control.close",
                       "params": {}})
        except Exception:
            pass
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(1.5)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass


# --------------------------------------------------------------------------
# the client

class Client:
    def __init__(self, pane_id, terminal_id, ws_label, tab_label, session):
        self.pane_id = pane_id
        self.terminal_id = terminal_id
        self.ws_label = ws_label or ""
        self.tab_label = tab_label or ""
        self.session = session
        self.bridge = Bridge(self)
        self.stop = threading.Event()
        self.attach_id = None
        self.grid = None                # (rows, cols, cw, ch)
        self.answers = True
        self.cap_features = set()
        self.my_conn = None
        self.boot_id = None
        self.geometry = None
        self.geometry_lock = threading.Lock()
        self.has_claimed_initial = False
        self.sigwinch = threading.Event()
        self.input_carry = bytearray()
        self.output_carry = bytearray()
        self.agent_status = ""
        self.agent_kind = ""
        self.base_title = ""
        self.snap_in_flight = False
        self.snap_requested_at = 0.0
        self.reconnect_attempt = 0
        self.ping_thread = None
        self.raw_mode_state = None
        self.exit_code = 0
        self.idle_death = None
        self.fifo_path = self._fifo_path()
        self.recon_lock = threading.Lock()

    # ---- paths ------------------------------------------------------------

    def _fifo_path(self):
        rtd = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        d = os.path.join(rtd, "hd")
        try:
            os.makedirs(d, exist_ok=True)
        except OSError:
            return None
        return os.path.join(d, f"{self.pane_id}.ctl")

    # ---- stdout sink ------------------------------------------------------

    def raw(self, data: bytes):
        try:
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
        except Exception as e:
            self.log(f"raw write failed: {type(e).__name__}: {e} (magic via park)")
            self.park("stdout closed — window is gone")

    # ---- title ------------------------------------------------------------

    def title_extra(self):
        parts = []
        if self.agent_kind:
            parts.append(self.agent_kind)
        if self.agent_status:
            parts.append(self.agent_status)
        return " · ".join(parts)

    def set_title(self):
        label = self.ws_label or "default"
        bits = [f"hd:{label}"]
        if self.tab_label:
            bits.append(self.tab_label)
        extra = self.title_extra()
        if extra:
            bits.append(extra)
        if self.geometry and self.geometry.owner == "other":
            bits.append("viewing (geometry owned elsewhere)")
        if self.pane_id:
            # the bar widget focuses our window by this suffix, so it has to
            # be unique and plain (ids are alnum + ':', regex-safe)
            bits.append(f"pane {self.pane_id}")
        self.base_title = " — ".join([b for b in bits if b])
        self.raw(f"\x1b]2;{self.base_title}\x07".encode())

    # ---- lifecycle --------------------------------------------------------

    def run(self):
        if self.fifo_path:
            self._open_fifo_loop()
        atexit.register(self.cleanup)
        self.raw(b"\x1b[?25l")
        self._fresh_stream()
        # main thread = input pump
        try:
            self.raw_mode_state = termios.tcgetattr(0)
            tty.setraw(0)
        except Exception:
            self.raw_mode_state = None
        try:
            while not self.stop.is_set():
                chunk = os.read(0, 4096)
                if not chunk:
                    self.log("stdin EOF (window closed)")
                    break
                self.handle_input(chunk)
            if self.idle_death:
                self.log(self.idle_death)
        except OSError as e:
            self.log(f"stdin read failed: {e}")
        finally:
            self.cleanup()

    def _fresh_stream(self):
        if self.stop.is_set():
            return
        if self.bridge.opened_ready.is_set():
            self.bridge.close()
            self.bridge = Bridge(self)
            self.attach_id = None
            self.snap_in_flight = False
            self.input_carry.clear()
            self.output_carry.clear()
        self.bridge.start(self.session)
        try:
            if not self.bridge.opened_ready.wait(REQUEST_TIMEOUT):
                self.on_error("bridge handshake timeout")
                return
        except Exception:
            pass

    def schedule_reconnect(self):
        with self.recon_lock:
            if self.stop.is_set():
                return
            attempt = self.reconnect_attempt
            self.reconnect_attempt += 1
        delay = min(RECONNECT_CAP, 2.0 ** min(attempt, 5))

        def go():
            time.sleep(delay)
            if not self.stop.is_set():
                self._fresh_stream()

        threading.Thread(target=go, daemon=True).start()

    # ---- bridge callbacks -------------------------------------------------

    def on_opened(self, opened):
        self.boot_id = opened["boot_id"]
        self.my_conn = opened.get("connection_id")
        caps = opened.get("capabilities") or {}
        stream = int(caps.get("terminal_control_stream") or 0)
        self.cap_features = set(caps.get("control_features") or [])
        if stream < 1:
            raise StreamError(f"herdr {opened.get('version')} has no "
                              "terminal control stream support")
        shared = ("shared_attach" in self.cap_features
                  and "geometry_ownership" in self.cap_features
                  and "geometry_controller" in self.cap_features)
        tab_id = self.resolve_tab_id()
        with self.geometry_lock:
            if not self.geometry or self.geometry.tab_id != tab_id:
                fresh = GeometryState(tab_id, shared)
                if self.geometry:
                    fresh.last_sent, fresh.owner = (self.geometry.last_sent,
                                                    self.geometry.owner)
                self.geometry = fresh
        core = ([f"workspace.{n}" for n in ("created", "updated", "closed",
                                            "renamed", "moved", "reordered", "focused")]
                + [f"tab.{n}" for n in ("created", "closed", "renamed", "moved", "focused")]
                + [f"pane.{n}" for n in ("created", "updated", "closed", "focused",
                                         "moved", "exited")]
                + ["layout.updated"])
        subs = [{"type": t} for t in core]
        if self.pane_id:
            subs.append({"type": "pane.agent_status_changed", "pane_id": self.pane_id})
        try:
            self.bridge.request("events.subscribe",
                                {"subscriptions": subs}, out_id="sub")
        except StreamError as e:
            self.log(f"initial subscription refused, retrying core set: {e}")
            self.bridge.request("events.subscribe",
                                {"subscriptions":
                                 [{"type": t} for t in core if "agent_status" not in t]},
                                out_id="sub2")
        snap = self.bridge.request("session.snapshot", {}, out_id="snap")
        self.apply_topology(snap.get("snapshot", {}), want_attach=True)
        self._arm_ping()

    def on_error(self, msg):
        self.log("bridge: " + msg)
        if "timed out" in msg or "stream closed" in msg or "refused" in msg:
            self.schedule_reconnect()

    def on_record(self, rid, typ, ev, obj):
        if ev:
            self.handle_event(ev, obj.get("data") or {})
            return
        typ = typ or obj.get("type")
        if typ == "terminal.snapshot":
            self.handle_snapshot(obj)
        elif typ == "terminal.output":
            self.handle_output(obj)
        elif typ == "terminal.gap":
            self.handle_gap(obj)
        elif typ == "terminal.authority":
            if obj.get("attach_id") == self.attach_id or "attach_id" not in obj:
                self.answers = bool(obj.get("answers_queries", True))
        elif typ == "terminal.detached":
            self.handle_detached(obj)
        elif typ == "tab.layout":
            with self.geometry_lock:
                g = self.geometry
                if g:
                    was = g.owner
                    g.note_layout(obj.get("layout") or {}, self.my_conn)
                    if was != g.owner:
                        # ownership changed; the server already applied the new
                        # owner's stored size (rootshell: never re-send on it)
                        self.set_title()

    # requests must NEVER be issued from the pump thread (it would block the
    # only reader on its own reply). Route request-issuing work to workers.
    def defer(self, fn):
        threading.Thread(target=fn, daemon=True).start()

    def handle_event(self, ev, data):
        if ev in ("pane.agent_status_changed", "pane_agent_status_changed"):
            if data.get("pane_id") == self.pane_id:
                self.agent_status = data.get("agent_status") or ""
                self.agent_kind = data.get("agent") or ""
                self.set_title()
        elif ev in ("layout.updated", "layout_updated"):
            self.push_geometry()
        elif ev == "events.gap":
            self.defer(self.refresh_topology)
        elif ev in ("tab.renamed", "tab_renamed"):
            lbl = data.get("label")
            if data.get("tab_id") == (self.geometry.tab_id if self.geometry else None):
                self.tab_label = lbl or self.tab_label
                self.set_title()
        elif ev in ("workspace.renamed", "workspace_renamed"):
            self.ws_label = data.get("label") or self.ws_label
            self.set_title()

    # ---- records ----------------------------------------------------------

    def handle_snapshot(self, obj):
        if obj.get("attach_id") != self.attach_id:
            return
        snap = obj.get("snapshot") or {}
        st = snap.get("state", {})
        rows, cols = st.get("rows"), st.get("cols")
        cur = snap.get("cursor") or {}
        self.output_carry.clear()
        self.input_carry.clear()

        out = bytearray()
        out += b"\x18"                                     # CAN
        out += authority_marker(self.answers)
        out += b"\x1b[?2026h\x1b[?1049l\x1b[0m\x1b[?25l"
        out += b"\x1b[r\x1b[?69l\x1b[?6l\x1b[?7h\x1b[4l\x1b(B\x0f"
        out += b"\x1b[3J\x1b[2J\x1b[H"
        primary = (snap.get("primary") or "").encode("utf-8", "surrogateescape")
        alternate = (snap.get("alternate") or "").encode("utf-8", "surrogateescape")
        out += primary
        if snap.get("active_screen") == "alternate":
            out += b"\x1b[?1049h\x1b[2J\x1b[H" + alternate
        out += (snap.get("state_ansi") or "").encode("utf-8", "surrogateescape")
        if cur.get("y") is not None and cur.get("x") is not None:
            # DECOM-aware CUP is normalized by the pre-reset above
            # (?6l applied inside state_ansi handling server-side
            # ordering: rootshell relies on the invariant that state_ansi
            # includes explicit DECOM/DECSLRM; our CUP is absolute afterwards).
            out += f"\x1b[{cur.get('y')};{cur.get('x')}H".encode()
            if cur.get("pending_wrap") and cur.get("pending_wrap_cell"):
                cell = cur["pending_wrap_cell"].encode("utf-8", "surrogateescape")
                pen = (snap.get("pen_ansi") or "").encode("utf-8", "surrogateescape")
                out += b"\x1b[0m" + cell + b"\x1b[0m" + pen
        out += b"\x1b[?2026l"
        self.raw(bytes(out))
        self.snap_in_flight = False
        st_grid = (st.get("cols"), st.get("rows"))
        if self.grid and (self.grid[1], self.grid[0]) != st_grid:
            # our window size differs from the server's stored grid for this
            # pane; push our size (claim decided by geometry state)
            self.push_geometry()

    def handle_output(self, obj):
        if obj.get("attach_id") != self.attach_id:
            return
        data = base64.b64decode(obj.get("bytes", "") or "")
        for u in partition_units(data, self.output_carry):
            self.raw(u)

    def handle_gap(self, obj):
        if obj.get("attach_id") != self.attach_id:
            return
        self.output_carry.clear()
        self.input_carry.clear()
        self.defer(self.request_snapshot)

    def request_snapshot(self):
        if self.snap_in_flight or not self.attach_id:
            return
        self.snap_in_flight = True
        self.snap_requested_at = time.time()
        try:
            self.bridge.request("terminal.snapshot",
                                {"attach_id": self.attach_id}, out_id="sr")
        except StreamError as e:
            self.snap_in_flight = False
            if "timed out" in str(e):
                self.on_error("snapshot request timed out")

    def handle_detached(self, obj):
        reason = obj.get("reason") or "closed"
        if reason == "takeover":
            self.park("pane taken over by another client (likely rootshell on "
                      "your phone). This window is parked; 'hd take' in a "
                      "fresh window would reclaim it.")
        else:
            self.schedule_reconnect()

    # ---- topology ---------------------------------------------------------

    def apply_topology(self, snapshot, want_attach=False):
        pane = next((p for p in snapshot.get("panes", [])
                     if p["pane_id"] == self.pane_id), None)
        if pane is None:
            if self.terminal_id and want_attach:
                self.attach_now()
                return
            self.park(f"pane {self.pane_id} not found (it may have been closed)")
            return
        self.terminal_id = pane.get("terminal_id") or self.terminal_id
        self.agent_status = pane.get("agent_status") or ""
        self.agent_kind = pane.get("agent") or ""
        self.set_title()
        if want_attach:
            self.attach_now()

    def refresh_topology(self):
        try:
            snap = self.bridge.request("session.snapshot", {}, out_id="rt")
            self.apply_topology(snap.get("snapshot", {}))
        except StreamError as e:
            self.on_error(f"topology refresh: {e}")

    def resolve_tab_id(self):
        r = call_herdr("pane", "list")
        try:
            panes = json.loads(r.stdout)["result"]["panes"]
        except Exception:
            return ""
        p = next((p for p in panes if p["pane_id"] == self.pane_id), None)
        return p["tab_id"] if p else ""

    # ---- attach -----------------------------------------------------------

    def attach_now(self):
        if not self.terminal_id:
            self.log("no terminal id known; cannot attach")
            return
        try:
            res = self.bridge.request("terminal.attach",
                                      {"target": self.terminal_id,
                                       "answer_queries": "client",
                                       "history_limit_bytes": HISTORY_LIMIT,
                                       "takeover": False}, out_id="att")
            self.attach_id = res.get("attach_id")
            self.log(f"attached as {self.attach_id}")
            self.push_geometry(claim_edge=True)
        except StreamError as e:
            msg = str(e)
            if "terminal_attached" in msg or "already" in msg:
                self.park("another client owns this pane right now "
                          "(rootshell on your phone, or another hd window). "
                          "'hd take' in a fresh window would claim it.")
            else:
                self.log(f"attach: {msg}")
                self.schedule_reconnect()

    # ---- ping -------------------------------------------------------------

    def _arm_ping(self):
        if self.ping_thread and self.ping_thread.is_alive():
            return

        def beat():
            while not self.stop.is_set():
                time.sleep(PING_INTERVAL)
                if self.stop.is_set():
                    return
                try:
                    self.bridge.request("ping", {}, timeout=PING_TIMEOUT,
                                        out_id="ping")
                except StreamError:
                    self.on_error("ping failed")
                    return

        self.ping_thread = threading.Thread(target=beat, daemon=True)
        self.ping_thread.start()

    # ---- geometry ---------------------------------------------------------

    def rsize(self):
        try:
            rows, cols, cw, ch = read_window_size(1)
        except Exception:
            return False
        if not rows or not cols:
            return False
        new = (rows, cols, cw, ch)
        changed = new != self.grid
        self.grid = new
        return changed or self.attach_id is None

    def push_geometry(self, claim_edge=False):
        if self.bridge.opened is None or not self.geometry:
            return
        if not self.rsize():
            return
        with self.geometry_lock:
            g = self.geometry
            if claim_edge:
                g.request_claim()
            else:
                if g.owner == "other":
                    # stored-only routine resize (no claim)
                    pass
            params = g.build_params(*self.grid)
        if params is None:
            return
        self.bridge.fire("tab.set_geometry", params, prefix="g")

    def on_sigwinch(self, signum, frame):
        self.sigwinch.set()

    def geometry_loop(self):
        while not self.stop.is_set():
            if self.sigwinch.wait(0.30):
                self.sigwinch.clear()
                self.push_geometry()
            elif self.snap_in_flight and \
                    time.time() - self.snap_requested_at > REQUEST_TIMEOUT:
                # a repair that never lands cannot be waited out (rootshell
                # tears the stream down rather than trusting a stale record)
                self.on_error("snapshot repair stalled")

    # ---- hydr focus watcher (activation edge) ----------------------------

    def watch_hypr_focus(self):
        runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if not sig:
            return
        path = os.path.join(runtime, "hypr", sig, ".socket2.sock")
        if not os.path.exists(path):
            return
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(path)
        except OSError:
            return
        prefix = f"hd:{self.ws_label}"
        buf = b""
        while not self.stop.is_set():
            try:
                data = sock.recv(4096)
            except OSError:
                break
            if not data:
                break
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                txt = line.decode("utf-8", "replace")
                if txt.startswith("activewindow>>"):
                    # activewindow>>class,title
                    parts = txt.find("active") >= 0 and txt.split(">>", 1)
                    if parts and len(parts) == 2:
                        title = parts[1].split(",", 1)[-1]
                        if title.startswith(prefix):
                            self.push_geometry(claim_edge=True)
        sock.close()

    # ---- control fifo ------------------------------------------------------

    def _open_fifo_loop(self):
        if not os.path.exists(self.fifo_path):
            try:
                os.mkfifo(self.fifo_path, 0o600)
            except OSError as e:
                self.log(f"fifo unavailable: {e}")
                self.fifo_path = None
                return

        def loop():
            buf = b""
            fd = None
            while not self.stop.is_set():
                try:
                    if fd is None:
                        fd = os.open(self.fifo_path, os.O_RDONLY)
                    chunk = os.read(fd, 256)
                    if not chunk:
                        os.close(fd)
                        fd = None
                        continue
                    buf += chunk
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        cmd = line.decode().strip()
                        if cmd == "claim":
                            self.push_geometry(claim_edge=True)
                        elif cmd == "quit-writers":
                            pass
                except Exception:
                    if fd is not None:
                        try:
                            os.close(fd)
                        except OSError:
                            pass
                        fd = None
                    time.sleep(0.4)

        threading.Thread(target=loop, daemon=True).start()

    # ---- input --------------------------------------------------------------

    def handle_input(self, chunk: bytes):
        if not self.attach_id:
            return
        units = partition_units(chunk, self.input_carry)
        if not units:
            return
        replies, typed = classify_units(units)
        # consume authority-probe replies locally; flip authority state.
        if self.cap_features and "query_authority" in self.cap_features:
            for u in list(replies):
                a = is_authority_probe_reply(u)
                if a is not None:
                    replies.remove(u)
                    self.answers = a
            # When not the authority, our local emulator still answers pane
            # queries; those replies must NOT be forwarded.
            if not self.answers:
                replies = []
        if replies:
            self.bridge.fire("terminal.input",
                             {"attach_id": self.attach_id,
                              "bytes": base64.b64encode(
                                  b"".join(replies)).decode(),
                              "auto": True})
        if typed:
            self.bridge.fire(
                "terminal.input",
                {"attach_id": self.attach_id,
                 "bytes": base64.b64encode(b"".join(typed)).decode()},
                prefix="k")

    # ---- parking / logging -------------------------------------------------

    def park(self, msg):
        self.log(f"parked: {msg}")
        self.raw(b"\x1b[?25h")
        self.raw(f"\r\n hd parked: {msg}\r\n".encode())
        self.idle_death = None
        self.stop.set()
        if self.raw_mode_state:
            try:
                termios.tcsetattr(0, termios.TCSADRAIN, self.raw_mode_state)
            except Exception:
                pass

    def log(self, msg):
        sys.stderr.write(f"[hd {time.strftime('%H:%M:%S')}] {msg}\n")
        sys.stderr.flush()

    def cleanup(self):
        if getattr(self, "_cleaned", False):
            return
        self._cleaned = True
        if self.raw_mode_state:
            try:
                termios.tcsetattr(0, termios.TCSADRAIN, self.raw_mode_state)
            except Exception:
                pass
        self.stop.set()
        try:
            if self.attach_id:
                self.bridge.fire("terminal.detach", {"attach_id": self.attach_id})
        except Exception:
            pass
        try:
            self.bridge.close()
        except Exception:
            pass
        if self.fifo_path and os.path.exists(self.fifo_path):
            try:
                os.unlink(self.fifo_path)
            except OSError:
                pass


# --------------------------------------------------------------------------

def read_window_size(fd=1):
    buf = fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\x00" * 8)
    rows, cols, xpix, ypix = struct.unpack("HHHH", buf)
    cell_w = (xpix // cols) if (xpix and cols) else 0
    cell_h = (ypix // rows) if (ypix and rows) else 0
    return rows, cols, cell_w, cell_h


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--pane", default="")
    ap.add_argument("--terminal", default="")
    ap.add_argument("--workspace-label", default="")
    ap.add_argument("--tab-label", default="")
    ap.add_argument("--session", default=None)
    ns = ap.parse_args()
    if not ns.pane and not ns.terminal:
        print("hd_client: need --pane or --terminal", file=sys.stderr)
        sys.exit(2)
    c = Client(ns.pane, ns.terminal, ns.workspace_label, ns.tab_label, ns.session)
    signal.signal(signal.SIGWINCH, c.on_sigwinch)
    signal.signal(signal.SIGINT, lambda s, f: (c.log(f"SIG{s} received"), c.cleanup()))
    signal.signal(signal.SIGTERM, lambda s, f: (c.log(f"SIG{s} received"), c.cleanup()))
    signal.signal(signal.SIGHUP, lambda s, f: (c.log(f"SIGHUP received"), c.cleanup()))
    threading.Thread(target=c.geometry_loop, daemon=True).start()
    threading.Thread(target=c.watch_hypr_focus, daemon=True).start()
    c.run()


if __name__ == "__main__":
    main()
