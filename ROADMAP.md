# flock — tracked plan

Status markers: ☐ todo · ◐ in progress · ☑ done. Update them here, not in chat.
Anything marked OPEN needs a grilling round before implementation.
Size cap: this file stays under ~150 lines. Finished or superseded items are
deleted (git history keeps them), not annotated.

**OPEN grills blocking work:** none.

Reviewer at milestones: `opencode run -m surplus/deepseek-v4.1-flash`, run in a
herdr pane in workspace `flrev`, output teed to /tmp/flock-review/.
Research ground truth (file:line-cited) lives in `/home/noor/repos/flock-research/`
(`rootshell.md`, `heeler.md`, `fork-delta.md`, `heeler-host-helper.md`,
`herdr-architecture-verdict.md`); re-read before any item that says "per research".

## Done

- Phase 1: ghost-terminal hardening, panel auto-dismiss, persisted acks
  (load path broken, fixed in PR-1 e1), friends-first README.
- Phase 2: public `noor-latif/flock`, v0.1.0.

## Phase 3 — keyboard + filter

- ☐ 1. Arrow keys move the row cursor, enter activates (CursorSurface
  keyboard-cursor contract, mirroring the tailscale panel).
- ☐ 2. Type-to-filter, fzf-style fuzzy: subsequence match, ranked by score
  (contiguous runs and word-boundary hits win).
- ☐ 3. [needs grill] Per-agent context size in rows. Probed 2026-10-22: no
  context field in agent/pane/workspace JSON, and no `tokens` key at all in live
  output. `tokens` is a metadata map that only appears when a reporter writes it
  (`pane report-metadata`); nothing on this machine reports context. Needs a
  reporter per agent, or drop the item.

## Phase 3b — popup surfaces

- ☐ 0. Sidebar parity with the herdr TUI: spaces tree with state dot, branch +
  `↑N` git badge; agents grouped by workspace; `+ new tab` row; rename for
  tabs/workspaces. OPEN data gap [needs grill]: live `workspace list` carries a
  `worktree` object (repo root, checkout path) but no branch or ahead/behind;
  the TUI gets those over the client protocol (fork `server/client_shell.rs`
  git fields). Pick: flockd runs `git` itself vs fork patch. The tokens-map
  option is dead (see Phase 3.3).
- ☐ 1. Agentless panes: per-workspace disclosure, collapsed by default; rows
  behave like agent rows.
- ☐ 2. New-pane affordance for parallel agents in one cwd — folded into the
  Phase 7 launcher; pick logic stays first-pane meanwhile.
- ☐ 3. `fl update`: locate clone, `git pull --ff-only`, re-sync deployed
  copies, print old→new, hint `omarchy-restart-shell` on QML change.

## Phase 4 — activity chronology

- ☐ Sections reorder by most-recent activity, most-alive on top; rows inside
  keep state_change-seq order. Derive from flockd's event feed (M0.3), not poll
  deltas.

## Phase 5 — fork-free cutover (decided 2026-10-22)

**Decision:** fl goes fork-free. The fl window is foot running
`herdr agent attach <pane>` (stock herdr 0.9.0+). The control-stream machinery
in fl_client.py (~800 lines: bridge, snapshot/output pump, geometry claims,
query authority, fifo claim) is deleted, not patched. A phone takeover evicts
the attach and the window dies with it: no park screen, no banner, no reclaim
verb. Re-attach = popup row or `fl <pane>`. flock docs and install.sh drop the
fork entirely.

- ☐ M0.1 Cutover, three PRs, widget first. Attach via
  `herdr terminal attach <terminal_id>` (id from `herdr pane list`), NOT
  `herdr agent attach`. Verified 2026-10-22 against the running fork server
  and stock `/usr/bin/herdr` 0.9.1: `agent attach` and `agent get` return
  `agent_not_found` (exit 1) for shell panes. `terminal attach` on a shell pane
  is PROVEN by `python3 -I tests/pty_attach.py` (13 checks on a sandboxed
  server, never the live session; all pass with fork 0.9.3 and stock 0.9.1:
  `HERDR_BIN=/usr/bin/herdr python3 -I tests/pty_attach.py`). Re-run it after
  any herdr update and before PR-2. Constraints for PR-2:
  1. One attach path for agent and shell panes; no plain-foot-shell fallback.
  2. No window titles (decision: spartan look, nothing shown). Window identity
     is the foot app-id: `foot -a flock-<pane_id> -e …`, matched on the hyprctl
     client `class` EXACTLY (so `flock-1` never matches `flock-10`). Drop the
     `-T` title, the OSC 2 write and the widget's title matcher. TRAP: do not
     use `herdr terminal title set`; it retitles the user's interactive herdr
     client (`client.window_title.set`), not the foot window.
  3. A second attach is refused by the server (exit 1, "terminal attach
     failed: terminal <id> already has an attached client; retry with
     --takeover"; tested on fork 0.9.3 and stock 0.9.1). No herdr API exposes
     the attach owner, so the pre-check is a window-system check: hyprctl
     clients with class `flock-<pane_id>`. If found: focus it, print "window
     already open", do not spawn.
  4. Close semantics need a live parent: fl does not exec-replace itself. It
     catches SIGHUP/SIGTERM. Tested: SIGHUP ends the attach client, the pane
     survives, and the attach slot is free again. Exit codes (tested): detach
     (Ctrl+B q) exits 0; takeover and refusal exit 1 with "taken over" /
     "already has an attached client". Note: inside an attach Ctrl+B is the
     detach prefix, not readline's back-char (double-tap sends a literal one).
     On window close re-check with `herdr agent get <pane>`: ok → agent, leave
     the pane; `agent_not_found` → shell, `herdr pane close`. Never on
     park/error exits. Keep `read_close_config` (config.toml `[close]`,
     FLOCK_CLOSE_SHELLS) and move it into fl/fl.

  **PR-1 Widget fixes** (lands first, works with old fl):
  (e1) acks save/load format mismatch (BarWidget.qml:166-174 vs 143-157).
  (e2) window matcher: match titles ending `pane <id>` and class foot, not
  `indexOf("pane "+id)` (`pane 1` matches `pane 10`; :296-303). Interim: PR-2
  replaces this with the exact app-id match.
  (e3) clear the badge only after focus/spawn succeeded (focusProc.onExited,
  :313-323). (e4) drop `--force` from the widget's spawn command.

  **PR-2 Cutover** (atomic): fl spawns `foot -a flock-<pane_id>` and waits;
  `terminal attach <terminal_id>` for every pane; widget matches class
  `flock-<pane_id>`; focus-existing guard; on attach failure print the reason and wait for
  Enter; delete fl/fl_client.py entirely (~1140 lines; fl/fl never imports it,
  it only execs it, and has its own herdr helpers) plus fl/fl's fifo helpers
  (`fifo_for_pane`, `pane_is_attached`, `attached_hint`); delete `fl take` and
  the "●" marker in `fl list`; signal-gated
  close wrapper; install.sh accepts stock herdr (drops the probe at :51-67);
  README / AGENTS.md lose fl_client and fork references;
  architecture-notes.md deleted or marked historical.

  **PR-3 Docs** only if PR-2 gets too big; never split PR-2 itself.
- ☐ M0.2 One reader: `flockd --once` / `fl status --snapshot`; delete the QML
  shell pipeline.
- ☐ M0.3 flockd read-only, single host: snapshot + `events.subscribe`, per-host
  gap → snapshot reset. Degraded rows stay visible with status + last-good age;
  reconcile local 2-5 s, ssh 10-30 s. Socket contract: hello/version, mode
  0o600, rendered not-running state. flockd owns aggregate, action routing,
  notifier fan-out; NOT surface-local focus or the terminal data plane.
- ☐ M0.4-M0.7 actions split, ack ownership, multi-host, notifier + adapters.
  Blocked/done only; a blocked transition while flockd is down is lost
  (accepted; the badge is the ambient surface).

## Phase 7 — agent launcher

- ☐ 1. `fl new` wizard in a cwd: PATH-probe agent detection → kind/name/args →
  `tab.create{cwd, focus:false}` → `agent.start` with the `agent_pane_busy`
  retry and pane-close compensation on failure (per research `heeler.md` §3).
- ☐ 2. Popup "+ new agent" form sharing the same store logic.
- ☐ 3. Worktree toggle in both surfaces → `worktree.create` → `agent.start` in
  the returned root pane; `worktree.remove` compensation on failure.

## Phase 8 — remote hosts (not started; stock herdr only)

Decision: shared view/geometry over remote is bloat. SSH + stock herdr JSON API
+ PTY attach. First spike: does `herdr machine add <ssh-target>` fit flockd's
consumption shape? If yes, ride it and own only aggregation; else
`[[hosts]]` in config.toml. Then host → workspace popup sections and
`fl pair <code>` (Heeler QR ceremony; needs real OpenSSH, Tailscale SSH alone
cannot run it).

## Deferred (not committed)

- Env targets for the launcher (mise / devcontainer): when a repo gets one.
- macOS bar adapter: a dumb consumer of flockd's socket.
- iPhone push via Heeler relay: only if laptop-offline notification is needed.
- Fork rebase: stay pinned; do not carry our own rebase.

## Verified facts (probed 2026-10-22; re-probe before relying on them)

- Two binaries: fork `~/.local/opt/herdr-rootshell/bin/herdr` (0.9.3-rootshell)
  first on PATH, stock `/usr/bin/herdr` 0.9.1. Both have `agent attach`,
  `terminal attach`, `--takeover`, `machine add`. The stock CLI talks to the
  running fork server fine. Lifecycle event subscriptions exist since 0.9.0.
- Stock herdr 0.9.5 (official release binary, sha256-verified) is installed at
  `~/.local/opt/herdr-stock/bin/herdr`, not on PATH; pacman's `/usr/bin/herdr`
  stays 0.9.1 (omarchy repo has no newer build). tests/pty_attach.py passes
  13/13 with 0.9.5 as client+server and as client against the fork server.
- No herdr API reports which client owns a terminal attach.
- The fork source clone `~/repos/rootshell-herdr-fork` is 0.9.5-preview based,
  newer than the installed fork binary and stock: its error strings may differ.

## Environment facts

- Repo = plugin: manifest.json at root; deploy loop is in AGENTS.md.
- Server state is the user's live session: never `herdr server stop`; config
  goes through `herdr server reload-config`.
- Heeler plugin is installed on this laptop (`herdr plugin list`).
- Research clones (read-only scratch): /home/noor/repos/{rootshell,Heeler,
  rootshell-herdr-fork}.
