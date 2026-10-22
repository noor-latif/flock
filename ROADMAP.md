# flock — tracked plan

Status markers: ☐ todo · ◐ in progress · ☑ done. Update them here, not in chat.
Decisions locked in grilling round 1 are recorded in the decision log at the
bottom; anything marked OPEN needs a grilling round before implementation.

## Phase 1 — chicken fix + quick wins (friends blockers)

- ☑ 1. Ghost-terminal hardening — when the target pane dies between launcher
  pick and client attach, `fl_client.py` loops "not_found" every ~20s on a
  stale terminal id (seen live 2026-10-21 13:15). FIXED: `apply_topology`
  re-resolves against the CLI before any first-connect attach (snapshot lag
  guard) and parks when the pane is not in herdr anymore;
  `attach_now → _attach_with` re-resolves once on `not_found`, and a second
  miss on the fresh id parks with "pane closed — run fl in its workspace
  again". Terminal-only launches keep working (no pane id → no park logic).
  Stub-verified: 5 paths (park/re-resolve/vanish/terminal-only/lag).
- ☑ 2. Panel auto-dismiss — clicking a row focuses/spawns the agent's window
  AND closes the popup (`applyClients` → `root.close()`). LIVE check pending
  (deployed; shell restart was refused by a locked session).
- ☑ 3. Persisted dismissals — acks survive restarts in
  `${XDG_STATE_HOME:-~/.local/state}/flock/acks.json` (debounced single
  write; same prune rule: ack lives only while its pane is still done).
  LIVE VERIFIED 16:47: the instrumentation shows load parsed, prune fired,
  and the file converged to {} — the earlier "untouched file" was the old
  QML still running behind a refused restart.
- ☑ 4. Friends-first README pass — fork is dependency #0 in a table, CLI vs
  badge/panel usage split, dismissal semantics + acks file documented, new
  troubleshooting rows (parking, ownership, title suffix), stale design
  text replaced with the badge language.
- ☑ 5. Where-am-I feedback — DISSOLVED, not a flock surface: the confusion
  was specific to opencode's own UI (the user hides opencode's right panel,
  so its session title vanishes); every other agent shows its own title and
  the popup already lists workspace + cwd + pane id per row. Title already
  ends `pane <id>` for window matching. Revisit only if a shell-pane notice
  is ever wanted; agent panes never get in-window text.

## Phase 2 — publish

- ☑ 1. GitHub public repo, account `noor-latif` (gh CLI authenticated, https).
  Repo name `flock`. Push main + tag v0.1.0.
- ☑ 2. Verify the friends path from a clean clone: fresh `git clone` of the
  public URL — manifest id, badge, LICENSE, executable install.sh confirmed;
  placeholder/identity greps empty over the whole history (one real email
  was found in AGENTS.md post-publish and purged via filter-branch +
  force-push + tag retarget). Full `omarchy plugin add` on an untouched
  omarchy box is the one thing only a friend's machine can prove.
- ☑ 3. Embed the real URL in README + install.sh.

## Phase 3 — keyboard + filter

- ☐ 1. Arrow keys move the row cursor, enter activates; CursorSurface
  keyboard-cursor contract (single highlight guarantee), mirroring
  /usr/share/omarchy/shell/plugins/panels/tailscale/Panel.qml machinery.
- ☐ 2. Type-to-filter: typing opens a filter; matching is fzf-style FUZZY
  (grilled decision): subsequence match ranked by score — contiguous runs
  and word-boundary hits win, position-independent otherwise.
- ☐ 3. Per-agent context size in popup rows (user request 2026-10-22; the
  fork's agent data exposes it today). Format grilling round 4.

## Phase 3b — popup surfaces (grill round 4)

- ☐ 1. Agentless panes in the popup: per-workspace disclosure section
  (user sketch: expandable under each workspace), collapsed by default so
  shells never clutter the agent view. Rows behave like agent rows:
  click = focus/spawn window.
- ☐ 2. New-pane affordance for parallel agents in one cwd (user workflow:
  "2 or 3 new agents in the same cwd, branching in big repos"). Options on
  the table: `fl --new` typed in the cwd (matches muscle memory), a
  "+ new pane" popup row per workspace, or both. Pick logic stays
  first-pane meanwhile; auto-focus-on-collision already paths around it.
- ☐ 3. Self-update story `fl update` — design: locate the flock clone
  (omarchy plugin clone if present, else a known dev repo, else fresh
  clone of github.com/noor-latif/flock), git pull --ff-only, re-sync
  ~/.local/lib/flock + ~/.local/bin/fl + the deployed plugin copy, print
  old→new version, and hint omarchy-restart-shell when the QML changed.
  Friends on the plugin path get `omarchy plugin update flock` for the
  plugin half; fl update handles the CLI half. (herdr side: `herdr update`
  downloads+installs the fork build itself; --handoff migrates the live
  server in place — agents survive.)

## Phase 4 — activity chronology

- ☐ 1. Sections (workspaces) reorder by most-recent activity, most-alive on
  top; row order inside a section stays state_change-seq based.
- ☐ 2. Design spike first: the widget polls (`agent list` every 2s); it has
  no live event feed today, and `state_change_seq` only moves on agent
  state changes. Pane activity needs `pane.focused`-style events — decide
  between a persistent control-stream connection in the widget vs deriving
  activity from cheap periodic snapshot fields.

## Decision log (from grilling)

- Bar icon = ONE badge: count inside = waiting-on-you (blocked + done,
  minus dismissed); color = worst state (blocked red > working green >
  done blue > idle bright thin ring, no "0" when idle). From 10 up the
  disc grows into a pill carrying the full number. The old !/✓ marks and
  the +N suffix are dead everywhere.
- Panel rows: plain color dots (marks already gone), selected pill on the
  focused agent's row.
- Dismissal semantics: focus == clear; activation focuses/spawns and marks
  seen; acked agents skip out of badge/tooltip/hero counts.
- Chronology: sections reorder by activity (rows inside unchanged).
- Keyboard: arrows + enter, plus type-to-filter with FUZZY matching.
- Where-am-I: dissolved (opencode's hidden panel, not flock).
- Close semantics (round 3): window close parks agents (pane + agent keep
  running server-side, badge keeps state) and closes agentless panes —
  no junk shells; overridable via ~/.config/flock/config.toml [close].
- Collision path (round 3): fl on an already-viewed pane auto-focuses the
  live window (hyprctl by title suffix), hint only as fallback; --force
  parsed as a flag everywhere.
- Fork-verified facts: `herdr pane close <pane_id>` is the shell-cleanup
  verb; `herdr update` upgrades the fork binary with `--handoff` moving the
  live server in place (agents survive); the fork stays a hard dependency
  (upstream 0.9.x has no control stream — attach, claims, geometry
  ownership and query authority all live there).
- Publish target: GitHub public under noor-latif.
- Order: chicken fix + quick wins first, publish fourth, chronology last.
- Naming (final, grill rounds 3-4): repo/CLI/plugin all `flock`/`fl`.
  Banned: `hd` (shadows hexdump's alias on some distros); `winherd`/`wh`
  (skim-read as "herdr for Windows 11" — the rename was made hours after
  first publish, zero users harmed).

## Environment facts (for any session touching this)

- Repo = plugin: manifest.json at root; deploy = rsync-minus-.git into
  ~/.config/omarchy/plugins/flock/ (Artificial process documented in
  AGENTS.md along with the restart/verify loop).
- Server state is the user's live session: NEVER `herdr server stop`;
  config goes through `herdr server reload-config`.
- Fork quirks live in docs/architecture-notes.md and fixed into fl;
  workspace create returns an object with a builtin root pane (both id
  and object shapes accepted).
