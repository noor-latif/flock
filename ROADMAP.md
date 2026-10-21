# winherd — tracked plan

Status markers: ☐ todo · ◐ in progress · ☑ done. Update them here, not in chat.
Decisions locked in grilling round 1 are recorded in the decision log at the
bottom; anything marked OPEN needs a grilling round before implementation.

## Phase 1 — chicken fix + quick wins (friends blockers)

- ☑ 1. Ghost-terminal hardening — when the target pane dies between launcher
  pick and client attach, `wh_client.py` loops "not_found" every ~20s on a
  stale terminal id (seen live 2026-10-21 13:15). FIXED: `apply_topology`
  re-resolves against the CLI before any first-connect attach (snapshot lag
  guard) and parks when the pane is not in herdr anymore;
  `attach_now → _attach_with` re-resolves once on `not_found`, and a second
  miss on the fresh id parks with "pane closed — run wh in its workspace
  again". Terminal-only launches keep working (no pane id → no park logic).
  Stub-verified: 5 paths (park/re-resolve/vanish/terminal-only/lag).
- ☑ 2. Panel auto-dismiss — clicking a row focuses/spawns the agent's window
  AND closes the popup (`applyClients` → `root.close()`). LIVE check pending
  (deployed; shell restart was refused by a locked session).
- ☑ 3. Persisted dismissals — acks survive restarts in
  `${XDG_STATE_HOME:-~/.local/state}/winherd/acks.json` (debounced single
  write; same prune rule: ack lives only while its pane is still done).
  Load/save/prune is instrumented with journal logs pending the unlock
  restart, because the seeded fake id survived two polls with no error —
  the chain has one silent link the logs will name. LIVE check pending.
- ☑ 4. Friends-first README pass — fork is dependency #0 in a table, CLI vs
  badge/panel usage split, dismissal semantics + acks file documented, new
  troubleshooting rows (parking, ownership, title suffix), stale design
  text replaced with the badge language.
- ◐ 5. Where-am-I feedback — attached foot windows show no indication of
  which pane/tab they hold (window title exists but isn't visible anywhere;
  in-window text would pollute agent scrollback — NOT acceptable).
  Planned: reorder title so `pane <id> · <workspace>` survives bar-side
  truncation, and verify the omarchy bar's title widget actually shows it.
  OPEN decision: whether plain-shell (non-agent) panes also get a one-line
  in-window notice after attach; agent panes never do.

## Phase 2 — publish

- ☐ 1. GitHub public repo, account `noor-latif` (gh CLI authenticated, https).
  Repo name `winherd`. Push main + tag v0.1.0.
- ☐ 2. Verify the friends path from a clean clone: `omarchy plugin add
  https://github.com/noor-latif/winherd` (or the repo-root install), then
  README/getting-started line for `wh` in a plain foot window.
- ☐ 3. Embed the real URL in README + install.sh (they still carry the
  `<you>/winherd` placeholder).

## Phase 3 — keyboard + filter

- ☐ 1. Arrow keys move the row cursor, enter activates; CursorSurface
  keyboard-cursor contract (single highlight guarantee), mirroring
  /usr/share/omarchy/shell/plugins/panels/tailscale/Panel.qml machinery.
- ☐ 2. Type-to-filter: typing opens a filter; matching style OPEN
  (substring recommended first, fuzzy second) — grill round 2 territory.

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
- Keyboard: arrows + enter, plus type-to-filter.
- Publish target: GitHub public under noor-latif.
- Order: chicken fix + quick wins first, publish fourth, chronology last.
- Naming: repo/CLI/plugin all `winherd`/`wh` (hd → wh rename done 2026-10-21;
  never reintroduce `hd` — it shadows hexdump's alias on some distros).

## Environment facts (for any session touching this)

- Repo = plugin: manifest.json at root; deploy = rsync-minus-.git into
  ~/.config/omarchy/plugins/winherd/ (Artificial process documented in
  AGENTS.md along with the restart/verify loop).
- Server state is the user's live session: NEVER `herdr server stop`;
  config goes through `herdr server reload-config`.
- Fork quirks live in docs/architecture-notes.md and fixed into wh;
  workspace create returns an object with a builtin root pane (both id
  and object shapes accepted).
