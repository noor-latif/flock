# flock — tracked plan

Status markers: ☐ todo · ◐ in progress · ☑ done. Update them here, not in chat.
Anything marked OPEN needs a grilling round before implementation.
Size cap: ~150 lines. Finished or superseded items are deleted, not annotated.

**OPEN grills blocking work:** none. Web-milestone questions are deliberately
undecided (see Web milestone).

Goal: the popup does most of what Heeler's console does, on stock herdr, for a
tiling-WM user. No daemon in v1: QML talks to herdr's socket directly, `fl` is the
window adapter, the notifier is a herdr plugin hook. The web app gets its own
core later. Heeler (Apache-2.0, /home/noor/repos/Heeler) is the reference: port
logic with attribution and credit it in a NOTICE when code is ported.

Reviewer at milestones: `opencode run -m surplus/deepseek-v4.1-flash`, in a herdr
pane in workspace `flrev`, output teed to /tmp/flock-review/. Notes in
`/home/noor/repos/flock-research/` are UNTRUSTED AI output; verify against code.

## Done

- Phase 1: ghost-terminal hardening, panel auto-dismiss, friends-first README.
- Phase 2: public `noor-latif/flock`, v0.1.0.

## M0 Truth pass

- ☐ AGENTS.md STATE line, README "Dependencies" onward and the `fl take`/claim
  docs describe the fork client: fix or delete. Drop the "in-memory acks" line
  (the widget persists `acks.json`; M1 replaces that). `docs/architecture-notes.md`
  is deleted or marked historical in M2.
- Do not patch BarWidget.qml's ack save/load mismatch (:146 vs :168), the
  `indexOf("pane "+id)` matcher (:299), ack-before-success (:317-323) or the
  `--force` spawn (:310-315): M1 and M2 delete those paths.

## M1 Bar on events (the next code)

Spiked 2026-10-23 on a sandboxed stock 0.9.5 server: `Quickshell.Io.Socket` holds
`events.subscribe`; a relative `import "proj.mjs" as P` works in a standalone
Quickshell config (not yet in the real plugin loader). Re-run after herdr or
Quickshell updates: `python3 -I tests/events_probe.py`, `python3 -I tests/qs_socket/run.py`.

- ☐ 1. Delete the 2 s `bash -lc herdr agent list` poll. QML `Socket` streams:
  - lifecycle, unfiltered: `workspace.created/updated/renamed/closed`,
    `tab.created/closed`, `pane.created/updated/closed`, `pane.agent_detected`.
    Each event is an invalidation: re-read `agent.list` + `workspace.list`
    (serialized; refresh again if events arrived mid-read). Never replay event
    payloads onto a snapshot (herdr docs: no shared sequence boundary).
  - status: `pane.agent_status_changed` REQUIRES `pane_id`, and `pane.updated`
    does not fire on status changes. One subscription per pane, added/dropped
    from the lifecycle diff; one bad pane_id rejects the whole request, so
    rebuild from a fresh list.
  - `events_lost` or socket close: re-subscribe, then snapshot. No auto-reconnect
    in Quickshell: a 1 s retry timer toggles `connected`. Reconcile read every
    ~20 s as a safety net. herdr serves one request per connection: actions use
    `Process`, not the stream socket.
- ☐ 2. `proj.mjs` (plain JS, JSDoc types, no Quickshell imports): projection and
  acks, so the future web UI loads the same file. `ack[pane_id] = state_change_seq`
  (max wins, no pruning, persisted in `~/.local/state/flock/acks.json`); an agent
  re-alerts when its seq moves on.
- ☐ 3. Confirm the real plugin loader accepts the `.mjs` import (needs
  `omarchy-restart-shell`; say so first).
- Keep the badge design (AGENTS.md). Arrow-key/enter row cursor and fzf-style
  type-to-filter ride on this rewrite.

## M2 Fork-free cutover (decided 2026-10-22)

`fl` windows are `foot -a flock-<pane_id>` running `herdr terminal attach
<terminal_id>` (from `herdr pane list`; NOT `agent attach`, which fails for
shells). Delete `fl/fl_client.py` (~1140 lines), fl/fl's fifo helpers
(`fifo_for_pane`, `pane_is_attached`, `attached_hint`), `fl take` and the "●" in
`fl list`. A phone takeover evicts the attach and the window dies; re-attach is
a popup row or `fl <pane>`. Heeler does the same (`takeover: true`,
AgentAttachStore.swift:706) and it works for the user. Proven by
`python3 -I tests/pty_attach.py` (13 checks, sandboxed); re-run before this PR.

- ☐ Constraints:
  1. One attach path for agent and shell panes; no plain-foot-shell fallback.
  2. No window titles. Identity is the foot app-id, matched EXACTLY on the
     hyprctl client `class` (`flock-1` must not match `flock-10`). Drop `-T`, the
     OSC 2 write and the title matcher. TRAP: never `herdr terminal title set`
     (it retitles the user's interactive herdr client).
  3. A second attach without `--takeover` is refused (exit 1). No herdr API
     reports the owner, so pre-check hyprctl: if class `flock-<pane_id>` exists,
     focus it, print "window already open", do not spawn. Never take over silently.
  4. fl does not exec-replace itself; it catches SIGHUP/SIGTERM (tested: the
     pane survives, the attach slot frees). Detach (Ctrl+B q) exits 0. On window
     close re-check `herdr agent get <pane>`: ok -> leave the pane;
     `agent_not_found` -> shell, `herdr pane close`. Never on park/error exits.
     Keep `read_close_config` (config.toml `[close]`, FLOCK_CLOSE_SHELLS).
- ☐ Also: on attach failure print the reason and wait for Enter; the widget
  focuses by class, spawns without `--force` and acks only after success;
  install.sh accepts stock herdr (drop the probe at :51-67); README/AGENTS.md
  lose fork references; `fl` resolves herdr once, not via `bash -lc` per call.
  Do not split this PR.

## M3 Notifier

- ☐ herdr plugin `[[events]]` hook on `pane.agent_status_changed` (Heeler ADR 0008,
  `plugin/src/notify-hook.js`): Blocked and Done notify; Working/Idle never. Hold
  ~5 s and re-check status via `HERDR_BIN_PATH` (detection flaps), dedupe in
  `HERDR_PLUGIN_STATE_DIR`, skip when the agent's window is focused. `notify-send`;
  no relay or encryption. Transitions while the hook cannot run are lost (accepted).

## M4 Composer and Stop (popup)

- ☐ Text field per agent row: Send = one `agent.prompt` with the whole draft. If
  the agent is Blocked, insert into the PTY WITHOUT Enter (`pane.send_input`). Stop
  (Working, empty draft) = `agent.send_keys` Esc. Heeler says Esc does not stop
  Grok Build (Ctrl+C does); only partly verified, check first.

## Next (not committed)

- Launcher (`fl new` and popup form): `tab.create{cwd, focus:false}`, then
  `agent.start` with the `agent_pane_busy` retry and pane-close compensation;
  macOS refuses launch lines in canonical mode (Heeler Transport.swift:1239).
  Worktree toggle: `worktree.create`, `agent.start` in its root, `worktree.remove`
  on failure.
- Sidebar parity (spaces tree, branch + `↑N`, grouped agents, new tab, rename) and
  a Changes list/diff. Git data is NOT a herdr gap: run `git` locally, as Heeler's
  GitProbe does. Agentless-pane disclosure. `fl update`. Section ordering by
  recent `state_change_seq`. Per-agent context size needs a reporter (no herdr field).

## Web milestone (re-grill before starting; nothing decided)

Open: core language and whether to use Cordis (upstream `cordis` 4.0.0-rc.12 is
active; `@deepseek-ai/cordis` is an older vendored snapshot), host id, systemd
unit, auth, takeover UX. Fixed constraints:
- A browser cannot open herdr's unix socket: it needs a bridge (WebSocket
  passthrough + a PTY bridge spawning `herdr terminal attach`). Do not build on
  fork-only `terminal session control`.
- Any caller of `agent.prompt`/`pane.send_text` is remote code execution: unix
  socket only, reach it over SSH or a tailnet, never bind 0.0.0.0; token and
  `Origin` check on any HTTP/WS listener.
- Foot and web terminals evict each other: design the takeover prompt first.
- The web UI loads the same `proj.mjs`; parse wire shapes leniently and check
  `protocol` at connect (herdr went 0.9.3 -> 0.9.5 in two weeks).

## Later / deferred

- Remote hosts: SSH + stock herdr API + PTY attach. Spike whether
  `herdr machine add` / `--machine` fits; then per-host sections and QR pairing.
- Chat from transcripts (Heeler: ~37k lines): attach instead. Env targets
  (mise/devcontainer). macOS bar adapter. iPhone push via Heeler relay.
  Fork rebase: stay pinned.

## Verified facts (probed 2026-10-22/23; re-probe before relying on them)

- `herdr` on PATH is the FORK (`~/.local/opt/herdr-rootshell/bin/herdr`
  0.9.3-rootshell) in login and non-login shells; the PATH source was not found.
  `/usr/bin/herdr` -> `~/.local/opt/herdr-stock/bin/herdr` is stock 0.9.5
  (IgnorePkg'd). The RUNNING server is the fork: do not restart it before M2, or
  the phone's fork features go. Stock has no control stream.
- Protocol 22 (`herdr api schema --json`). `agent.list` rows carry
  `state_change_seq`, `agent_session`, `terminal_id`, `foreground_cwd`.
  `workspace list` has no branch/ahead. Event history: 512-entry ring shared
  across event types. No API reports the attach owner.
- Quickshell 0.3.2 `Socket`: `path`, `connected`, `write`, `flush`, `error`; no
  auto-reconnect, timeout or backpressure.
- `~/repos/rootshell-herdr-fork` is newer than the installed fork binary and stock.

## Environment facts

- Repo = plugin: manifest.json at root; deploy loop is in AGENTS.md.
- The live herdr session is the user's: never `herdr server stop`; config via
  `herdr server reload-config`. Test against a sandboxed server.
- Heeler plugin is installed on this laptop (`herdr plugin list`).
