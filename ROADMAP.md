# flock — tracked plan

Status markers: ☐ todo · ◐ in progress · ☑ done. Update them here, not in chat.
Decisions locked in grilling are recorded in the decision log at the bottom;
anything marked OPEN needs a grilling round before implementation.
Research ground truth for rounds 5-7 lives in `/home/noor/repos/flock-research/`
(`rootshell.md`, `heeler.md`, `fork-delta.md`, `heeler-host-helper.md`,
`herdr-architecture-verdict.md`) — file:line-cited; re-read before implementing
any item below that says "per research".

## Phase 1 — chicken fix + quick wins (friends blockers) — DONE

- ☑ 1. Ghost-terminal hardening — `apply_topology` re-resolves against the CLI
  before first-connect attach; park on vanish; re-resolve once on `not_found`.
- ☑ 2. Panel auto-dismiss — row click focuses/spawns AND closes the popup.
- ☑ 3. Persisted dismissals — acks in `${XDG_STATE_HOME:-~/.local/state}/flock/acks.json`,
  debounced write, pruned to still-done agents. Live-verified.
- ☑ 4. Friends-first README pass — fork as dependency #0, CLI vs widget split,
  dismissal semantics, troubleshooting rows.
- ☑ 5. Where-am-I — DISSOLVED (opencode's own hidden panel, not a flock surface).

## Phase 2 — publish — DONE

- ☑ GitHub public `noor-latif/flock`, main + v0.1.0; clean-clone friends path
  verified; real URL embedded in README + install.sh.

## Phase 3 — keyboard + filter

- ☐ 1. Arrow keys move the row cursor, enter activates; CursorSurface
  keyboard-cursor contract, mirroring the tailscale panel machinery.
- ☐ 2. Type-to-filter, fzf-style FUZZY (grilled decision): subsequence match
  ranked by score — contiguous runs and word-boundary hits win.
- ☐ 3. Per-agent context size in rows. RESEARCH CAVEAT: no `context_*` field
  exists in `AgentInfo`/`PaneInfo` in any repo — live-probe which `tokens` key
  carries it before designing the format (grill round 4 pending on format).

## Phase 3b — popup surfaces

- ☐ 1. Agentless panes: per-workspace disclosure section, collapsed by default;
  rows behave like agent rows (click = focus/spawn).
- ☐ 2. New-pane affordance for parallel agents in one cwd — folded into the
  Phase 7 launcher (`fl new` + popup "+ new agent"); pick logic stays
  first-pane meanwhile.
- ☐ 3. Self-update story `fl update` — locate clone, `git pull --ff-only`,
  re-sync deployed copies, print old→new, hint `omarchy-restart-shell` on QML
  change; friends get `omarchy plugin update flock` for the plugin half.

## Phase 4 — activity chronology (amended by flockd)

- ☐ 1. Sections (workspaces) reorder by most-recent activity, most-alive on
  top; rows inside keep state_change-seq order.
- ☐ 2. AMENDED: the design spike is overtaken by Phase 6 — flockd subscribes
  per host (`events.subscribe`), so chronology derives from the event feed
  (with per-host gap → snapshot reset) instead of poll deltas. Keep
  `pane.output_matched`/`scroll_changed` subscriptions as cheap activity
  signals if needed (fork-verified, research `fork-delta.md` §1g).

## Phase 5 — reclaim + window bugs (live failures, 2026-10-22 screenshots)

- ☐ 1. Takeover zombie: on `terminal.detached{reason:"takeover"}` the client
  today parks into a dead window with a scary banner. Fix: behave like herdr's
  own client — clean `terminal.detach`, keep the bridge, quiet retry loop, and
  resume the attach (claim:false) when the pane frees. One log line, no park
  UI, no exit. Native geometry-following (smallest device wins) is herdr's own
  behavior and is NOT reimplemented.
- ☐ 2. `focus_or_hint` breaks on hyprctl's Lua dispatch path: titles with
  `:`/spaces raise `')' expected near 'title'` and fl prints "focused its
  window" without checking the exit code. Fix quoting for the hl.dispatch
  wrapper, verify the exit status, fall back to the hint text on failure.
- ☐ 3. Kill the `fl take` pane-env fiction: it requires `HERDR_PANE_ID` + a
  live client fifo, i.e. it can never run in the parked window it exists for.
  Reclaim belongs to the popup/attach flow (decision r1: no suggested fl
  commands in user-facing messages). Fold any surviving need into `fl <pane>`
  collision handling.

## Phase 6 — flockd core (cordis-style authority for surfaces)

Shape verified against herdr's own architecture (research
`herdr-architecture-verdict.md`): one authority + thin clients is herdr's
proven layout; the cross-host aggregate is the only genuinely new layer.
flockd must SUBSCRIBE, not poll, and own as little as possible.

- ☐ 1. flockd (Python stdlib): per-host connection = `session.snapshot` once,
  then `events.subscribe` (fork hosts may add `control.list`/`events.gap`,
  capability-gated); blocking `agent.wait` for transitions. NO 2 s polling —
  herdr already computes transitions server-side.
- ☐ 2. NDJSON socket `$XDG_RUNTIME_DIR/flock/state.sock` mirroring herdr's wire
  shape (`{"id","method","params"}` / `{"id","result"|"error"}`) so surfaces are
  testable against herdr fixtures. Services: agents, hosts, actions, events.
- ☐ 3. Cross-host aggregate: merged agent list, per-host online/degraded
  status. Gap policy: one host's stream reports Lost/gap → reset THAT host's
  state from a fresh snapshot only (per-connection rule, never global).
- ☐ 4. Action routing: new_agent / prompt / focus / close / worktree → the
  target host's socket; no local heuristics (herdr's `--wait` verbs already
  return "submitted and reached state").
- ☐ 5. Notifier plugins: blocked/done → `notify-send` first; notifier = a
  plugin over flockd's event stream so cross-OS channels (relay → iPhone,
  Heeler-style) plug in without touching core.
- ☐ 6. Lifecycle: session-scoped, auto-start on first surface demand, dies
  with the session; `not running` is a rendered state surfaces show, never an
  exception. No handoff machinery (flockd holds no PTYs); durable bits
  (acks, last-seen cursors) to disk before exit.
- ☐ 7. BarWidget.qml consumes flockd (drops its own poll); the old poll stays
  only as reconnect fallback, and degraded hosts render visibly instead of
  silently showing stale state.
- ☐ 8. Docs: surface-plugin contract (the cordis mapping: surfaces claim
  nothing, consume events/actions; new capability once → every surface).

## Phase 7 — agent lifecycle launcher (the Heeler sheet, both surfaces)

- ☐ 1. `fl new` CLI wizard in a cwd: PATH-probe agent detection (Heeler's
  `command -v` marker trick, research `heeler.md` §3) → kind/name/args →
  `tab.create{cwd, focus:false}` → `agent.start{kind,name,pane_id,args}` with
  the `agent_pane_busy`/canonical-mode retry and pane-close compensation on
  failure (exact Heeler choreography).
- ☐ 2. Popup "+ new agent" row/form (host/workspace/agent/name/tab/args,
  worktree toggle) sharing the same store logic as `fl new`; bare `fl` typed in
  any terminal opens the in-terminal TUI popup (alt-screen list + keys over
  flockd's socket — feasible: same raw-tty machinery fl_client already uses).
- ☐ 3. Worktree sandbox: worktree toggle in both surfaces →
  `worktree.create{workspace_id, branch?, base?, label}` → `agent.start` in the
  returned root pane; generated `worktree/<adj>-<noun>-<nnnn>` default,
  typeable branch; `worktree.remove` compensation on failure. Agent env/configs
  are host-level (NOT per-checkout) — that is the whole "persisting configs"
  story; no copy step. Env targets (mise/devcontainer) DEFERRED — see Phase 10.

## Phase 8 — remote hosts (Heeler dialect; fork stays local-only)

Decision: shared view/geometry over remote is bloat — Heeler's stock-herdr
dialect wins for remotes (research `heeler.md` §1, `heeler-host-helper.md`).
The fork remains required ONLY on the laptop (fl windows).

- ☐ 1. `[[hosts]]` in config.toml: name, ssh alias, session, notify level,
  poll override. No daemon, no plugin, nothing installed on remotes beyond
  stock herdr + sshd (stream-local forwarding is the OpenSSH default).
- ☐ 2. Transport per host: SSH exec → direct-streamlocal onto `herdr.sock` for
  JSON RPC (snapshot + events.subscribe), PTY exec
  `HERDR_SOCKET_PATH=… herdr agent attach <pane> [--takeover]` for terminals.
  Remote attach is single-owner stock behavior — takeover prompt on collision
  (user-initiated only).
- ☐ 3. Popup sections become host → workspace; host rows carry status +
  measured latency (Heeler hosts-screen model); badge counts all hosts.
- ☐ 4. QR pairing, text-mode: adopt the Heeler plugin ceremony (ALREADY
  installed and enabled on this laptop) — `fl pair <code>` consumes the
  `HERDR-PAIR:1:…` envelope exactly as the iPhone does: connect with the
  Bootstrap Key, write the laptop's Device Key to stdin, pin the host
  fingerprint. No camera needed; the host renders the code via the plugin's
  `pair` action. Manual `[[hosts]]` entries stay the fallback.

## Phase 9 — deferred / future (explicitly not committed)

- ☐ Env targets for the launcher: mise / devcontainer (docker compose up +
  exec). Laptop has docker 29.9 + podman 6.1 + mise, zero devcontainer.json
  files; revisit when a repo actually gets one. User wants hands-on comfort
  with the isolation story first.
- ☐ macOS bar adapter: dumb consumer of flockd's socket (the port is the
  point of the core; design note only).
- ☐ iPhone push via Heeler's relay/hooks: only if laptop-offline notification
  is ever required (laptop-offline means nobody is minding the badge anyway).
- ☐ Fork rebase posture: fork is 0.9.3-based, upstream 0.9.5 with input-IME +
  detection + perf fixes and `plugin update`; method surface unchanged. Stay
  pinned until kitknox integrates (their pattern), do NOT carry our own rebase.
  Revisit if a needed fix lands upstream first.

## Decision log (from grilling)

Rounds 1-4 (pre-publish): see git history of this file — badge/pill language,
dismissal semantics, close semantics, focus-on-collision, `--force` flag,
naming, chronology-by-sections, fuzzy filter.

Round 5-7 (2026-10-22, rootshell/Heeler research):

- **Takeover UX**: no special UX, no park screens, no exit-to-shell — fl
  behaves like herdr's native clients: quiet auto-reconnect when a takeover
  frees the pane. The user values herdr's native smallest-device geometry
  mirroring; fl must not fight it or wedge (Phase 5.1).
- **No suggested fl commands**: user-facing messages must not advertise CLI
  incantations ("run fl take…"); the popup owns agent lifecycle. `fl take` as
  a pane-env guard is dead (Phase 5.3).
- **Remote dialect**: Heeler wins for remotes by NOT using the fork: SSH +
  stock herdr JSON API + PTY attach. Shared view/geometry over remote =
  bloat. Fork stays a local-only dependency.
- **Heeler's "helper" demystified**: no host daemon exists — one herdr plugin
  (one-shot hooks + QR pairing popup + 120 s self-revoking bootstrap key) and
  a developer-hosted stateless push relay. flock adopts the plugin's pairing
  ceremony (already installed here) and nothing else from it.
- **Core architecture (flockd)**: adopted after verification against herdr's
  code (verdict file): shape correct, boundary corrected — subscribe per host,
  never poll; own only cross-host aggregate, action routing, fan-out;
  per-host gap reset; capability-gate fork-only features; session-scoped
  lifetime; rendered not-running state. Surfaces are dumb plugins over the
  NDJSON socket (cordis model: services + events, no logic in surfaces).
- **Launcher**: BOTH surfaces — `fl new` wizard and popup form — sharing one
  store; bare `fl` in a terminal opens the in-terminal TUI popup. Heeler's
  launch choreography (tab.create → agent.start + retry + compensation) is
  the contract.
- **Sandbox meaning**: "sandbox with persisting configs" = harness +
  environment selection; the persisting part is free (herdr agent env is
  host-level, not per-checkout). Worktree launch ships with the launcher;
  mise/devcontainer targets deferred to Phase 9.
- **Pairing**: Heeler QR ceremony over manual-only config; `fl pair <code>`
  is text-mode enrollment for a laptop (no camera).
- **Notifications**: blocked/done only, delivered by flockd notifier plugins;
  cross-OS ambition recorded — herdr as the moat for dev-on-the-go while
  flock gives the powerful desktop-native experience. No relay infra now.
- **Context-size caveat**: no schema field exists in any repo; the Phase 3.3
  row needs a live probe of the `tokens` map before its format grill.

## Environment facts (for any session touching this)

- Repo = plugin: manifest.json at root; deploy = rsync-minus-.git into
  ~/.config/omarchy/plugins/flock/ (process + restart/verify loop in AGENTS.md).
- Server state is the user's live session: NEVER `herdr server stop`;
  config goes through `herdr server reload-config`.
- Fork quirks live in docs/architecture-notes.md and are fixed into fl;
  workspace create returns an object with a builtin root pane (both shapes
  accepted).
- Heeler plugin is installed and enabled on this laptop
  (`herdr plugin list` → heeler, config at ~/.config/herdr/plugins/config/heeler).
- Research clones (read-only, scratch): /home/noor/repos/{rootshell,Heeler,
  rootshell-herdr-fork} and /tmp/rootshell-herdr-fork-branch (fork branch;
  re-clone from github.com/kitknox/herdr if /tmp was cleaned).
