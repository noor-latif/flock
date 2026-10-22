# flock — tracked plan

Status markers: ☐ todo · ◐ in progress · ☑ done. Update them here, not in chat.
Decisions locked in grilling are recorded in the decision log at the bottom;
anything marked OPEN needs a grilling round before implementation.

**OPEN grills blocking work:** none. RESOLVED 2026-10-22: claim-mode 5.1b —
mooted by the fork-free cutover (Phase 5); displaced UX = "herdr handles it"
(attach evicted, window dies, no UX); stale-state budget = keep degraded
rows visible with status + last-good age (arena pattern), reconcile local
2-5 s / ssh 10-30 s (M0.3; decision-log Review round).
Reviewers at milestones: `opencode run -m surplus/deepseek-v4.1-flash`,
run inside a herdr pane in workspace `flrev`, output teed to
/tmp/flock-review/. (History: opencode free tier exhausted 2026-10-22 —
ALL `-free` models quota-blocked, likely leaked zombie runs + M0 review;
minimax-m3.1 deprecated same day before use. Surplus key is the fallback
route.) M0 review → m0-review.md, M0.1 plan review → m01-review.md.
Research ground truth for rounds 5-7 lives in `/home/noor/repos/flock-research/`
(`rootshell.md`, `heeler.md`, `fork-delta.md`, `heeler-host-helper.md`,
`herdr-architecture-verdict.md`) — file:line-cited; re-read before implementing
any item below that says "per research".

## Phase 1 — chicken fix + quick wins (friends blockers) — DONE

- ☑ 1. Ghost-terminal hardening — `apply_topology` re-resolves against the CLI
  before first-connect attach; park on vanish; re-resolve once on `not_found`.
- ☑ 2. Panel auto-dismiss — row click focuses/spawns AND closes the popup.
- ☑ 3. Persisted dismissals — acks in `${XDG_STATE_HOME:-~/.local/state}/flock/acks.json`,
  debounced write, pruned to still-done agents.
  ⚠ M0 review found the load path broken (save/load format mismatch) —
  restart-load silently drops every ack; fix lands in M0.1(a). The earlier
  "LIVE VERIFIED" claim covered only the write side.
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

- ☐ 0. Sidebar parity (user request 2026-10-22, herdr TUI sidebar screenshot):
  popup shows (a) spaces tree with per-workspace state dot, branch +
  `↑N` git badge, worktree provenance rows; (b) agents grouped by
  workspace below (the "agents / grouped" list); (c) `+ new tab` row
  per workspace; (d) rename for tabs/workspaces (long-press/right-click
  → `tab.rename`/`workspace.rename`). DATA GAP (OPEN decision): socket
  `WorkspaceInfo` has NO branch/git_ahead_behind (fork
  `api/schema/workspaces.rs:62-76`) — the TUI's badge rides the client
  protocol (`server/client_shell.rs:87-89`, computed in
  `workspace/git/status.rs:193-341`). Pick: fork patch vs flockd git
  spawn vs tokens-map probe. Also probe whether `tokens` map carries
  context-size here (Phase 3.3 shares the probe).
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

## Phase 5 — fork-free cutover + window fixes (decided 2026-10-22)

**VERDICT (live probe + control.list, 658 samples):** the phone's takeover
was a direct `--takeover` attach that evicted fl's control-stream attach
(16:58:31 park). Server-side layout NEVER mirrored the phone (wG:t2 stayed
130x58 through the whole phone session) — "smallest device wins" is rendered
inside rootshell's client, not by the shared layout. The parked fl bridge
leaked (conn alive with 0 attaches 0 tabs for minutes, still answering
`pane_is_attached`, stale "geometry owned elsewhere" title). Meanwhile
the geometry claim-mode debate (5.1b follower-vs-owner) is MOOT under the
cutover below — no control-stream viewer, no claims, no succession.

**DECISION (grill 2026-10-22): fl goes fork-free, Heeler dialect.**
- fl window = foot running `herdr agent attach <pane>` PTY (stock herdr
  0.9.0+ API). The entire control-stream machinery in fl_client.py
  (~800 lines: bridge, snapshot/output/gap pump, geometry claims,
  query authority, fifo claim) is DELETED, not patched — with it die
  M0.1(c)-(h) and review findings 3-5, 10-13, 26-28.
- Displaced UX: NONE — herdr handles it. Phone takes over → the PTY attach
  is evicted → attach process exits → window closes/dies with it. No park
  screen, no banner, no reclaim verb. Re-attach = popup row / `fl <pane>`.
- Fork binary stays on the laptop for rootshell/phone only; flock's docs
  and install.sh drop it entirely (fork-independent install story).

- ☐ M0.1-forkfree Cutover PR (plan review verdicts folded —
  /tmp/flock-review/m01-review.md, surplus/deepseek-v4.1-flash, 16 findings;
  E: three PRs, widget first):
  PR-1 Widget fixes (safe pre-cutover): (e1) acks load/save round-trip
  (flat map on disk vs doc.acked loader), (e2) pane matcher endsWith +
  class check, (e3) ack only after action success (focusProc onExited),
  (e4) drop `--force` from the spawn command in lockstep with PR-2.
  PR-2 Cutover (atomic — title + wrapper + install.sh in the same PR):
  (a) fl spawn-and-WAIT, never exec — the close-semantics wrapper needs a
  surviving parent; keep resolve-or-create workspace flow, `fl list`,
  `fl status`.
  (a2) AGENTLESS PANES: `herdr agent attach` refuses non-agent panes
  (`agent_not_found`, verified live + terminal_targets.rs:74-92), and
  fl's default path attaches the workspace's first pane (often a shell) —
  agentless targets fall back to plain `herdr pane attach`-equivalent:
  spawn foot with a plain shell `herdr pane focus`/`pane run bash` —
  NO close semantics for shell panes (window close just closes the shell;
  herdr reaps it per its own semantics).
  (a3) Title emission is fl's job: `agent attach` clients are never
  foreground (headless.rs:1493-1519, clients.rs:467-473) and receive NO
  WindowTitle — fl sets the title via foot's `-T` argument at spawn
  (`foot -T "fl:<ws> — pane <id>"`), plus an OSC 2 write from the
  surviving wrapper BEFORE the child takes the terminal (belt and braces;
  the attach TUI never rewrites it); static title only (no live status
  segment post-exec).
  (a4) Focus-existing guard: fifo is gone; second `fl <pane>` must not
  exit-1-and-die (server refuses a second attach, headless.rs:1787-1799) —
  pre-attach `herdr` check: if `agent attach` fails with
  "already attached", tell the user the window is live (hyprctl title
  match, same needle as the widget) instead of spawning a dying window.
  (a5) Error hold: attach failures under `foot -e` flash and vanish —
  on non-takeover errors, print and `read -r` (hold the window) so the
  text is readable.
  (b) window title: keep `pane <pane_id>` suffix last (widget matcher);
  old `fl:<ws> — status — viewing…` dynamic segment is dead by design.
  (c) delete fl_client.py control-stream paths; keep only what `fl list`/
  `fl new` need (CLI JSON calls — those are stock APIs).
  (d) `fl take` verb deleted (fifo gone with the client); `fl list`'s "●"
  attachment marker goes with it (accept: no marker until flockd).
  (d2) Close semantics (round-3 decision), CORRECTED by review: gate on
  SIGHUP/SIGTERM caught by the wrapper — NEVER exit code (takeover and
  real errors both exit 1; detach exits 0). On window-close signal:
  re-check agent-ness with `herdr agent get <pane>` (definitive;
  `agent_status:"unknown"` lies for shell panes), close if agentless via
  `herdr pane close`; agent panes stay (server-side park).
  (e2b) install.sh: drop the `herdr control` probe (install.sh:51-67
  hard-rejects stock herdr today); accept stock herdr ≥0.9.0.
  (f) roadmap/docs: architecture-notes.md marked historical; README drops
  `fl take`/`--force`/claim-discipline; AGENTS.md de-fl_client.
  PR-3 Docs (f) if cutover grows too large — split only (f), never 2.
- ☐ M0.2 One reader (unchanged): `flockd --once` / `fl status --snapshot`;
  delete QML shell pipeline.
- ☐ M0.3 Daemon read-only single-host — now trivially stock-API: snapshot +
  events.subscribe (0.9.0+), no control.* anywhere in flock.
  OPEN grill: stale-state budget — hide degraded host rows vs render with
  last-good timestamp; reconcile interval per host class (local 2-5 s,
  ssh 10-30 s). Blocks M0.3's degraded-render work.
- ☐ M0.4-M0.7 unchanged (actions split, ack ownership, multi-host,
  notifier + adapters).

Probe artifacts kept for reference: /tmp/flock-review/{probe.py,
probe-live.log} (geometry never mirrored; zombie bridge evidence).

## Phase 6 — flockd core (superseded ordering: see Phase 5 M0.2-M0.7)

Boundary (from M0 review, verdict A): flockd owns aggregate + action
fan-out + notifier registry + degraded-state truth. It does NOT own:
herdr's machine catalog (Phase 8 spike decides catalog owner — if
`herdr machine add` fits, flockd aggregates over herdr supervisors
instead of a second `[[hosts]]` transport), surface-local focus, or the
terminal data plane. Host-qualified identity and a hello/version +
socket mode 0o600 + not_running error shape are part of the socket
contract (M0.3). Notifier durability: a blocked transition while flockd
is down is lost unless a herdr hook spools it — accept-and-document for
now (badge is the ambient surface; revisit if push wanted).

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

## Phase 8 — remote hosts (Heeler dialect; flock is fork-independent)

Decision: shared view/geometry over remote is bloat — Heeler's stock-herdr
dialect wins for remotes (research `heeler.md` §1, `heeler-host-helper.md`).
Since the Phase 5 cutover, flock requires stock herdr only — the fork
binary is the user's own phone/rootshell concern, not a flock dependency
on any machine.

- ☐ 1. `[[hosts]]` in config.toml: name, ssh alias, session, notify level,
  poll override. No daemon, no plugin, nothing installed on remotes beyond
  stock herdr + sshd (stream-local forwarding is the OpenSSH default).
- ☐ 2. Transport per host: SSH exec → direct-streamlocal onto `herdr.sock` for
  JSON RPC (snapshot + events.subscribe), PTY exec
  `HERDR_SOCKET_PATH=… herdr agent attach <pane> [--takeover]` for terminals.
  Remote attach is single-owner stock behavior — takeover prompt on collision
  (user-initiated only). EVALUATE FIRST against `herdr machine add <ssh-target>`
  (upstream's saved-machine catalog: SSH stdio bridge → local socket,
  independent reconnects, `--machine` prefixing): if its per-host bridge fits
  flockd's consumption shape, ride herdr's maintained path instead of a
  bespoke flock transport; flockd then owns only aggregation. Decide with a
  spike before writing transport code.
- ☐ 3. Popup sections become host → workspace; host rows carry status +
  measured latency (Heeler hosts-screen model); badge counts all hosts.
- ☐ 4. QR pairing, text-mode: adopt the Heeler plugin ceremony (ALREADY
  installed and enabled on this laptop) — `fl pair <code>` consumes the
  `HERDR-PAIR:1:…` envelope exactly as the iPhone does: connect with the
  Bootstrap Key, write the laptop's Device Key to stdin, pin the host
  fingerprint. No camera needed; the host renders the code via the plugin's
  `pair` action. Manual `[[hosts]]` entries stay the fallback. CAVEAT
  (plugin README): Tailscale SSH alone cannot run the ceremony — it needs
  real OpenSSH on the host (authorized_keys forced commands); plugin skips
  `SSH-2.0-Tailscale` servers. All our hosts are Tailscale, so verify each
  remote runs stock sshd (Tailscale subnet routing or plain tailscaled with
  OpenSSH on :22 is fine).

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

Review round (2026-10-22, post-commit advisories — folded in. NOTE: the
first two bullets below described the fork-dialect world and are
SUPERSEDED by the fork-free cutover decision (Phase 5, same day) — kept
as history, not current truth; the geometry-ownership root cause in
bullet 2 was wrong once already and is moot under the PTY attach):

- **flockd is subscribe-push + poll-as-repair**, not pure-push: every native
  herdr client pairs subscriptions with snapshot reconciliation; the 2 s
  poll survives as repair/slow-reconcile only. STALE-STATE BUDGET: resolved
  by arena evidence (herdr TUI, rootshell, Heeler all keep degraded rows
  visible with status/last-good info; none hide) — default locked: visible
  with timestamp, per-host reconcile local 2-5 s / ssh 10-30 s (M0.3).
  ~~was an open grill~~.
- **[SUPERSEDED — was wrong] Takeover zombie root cause is fl's geometry
  ownership**: claim-on-attach evict theory; the live probe showed the
  phone evicted fl's ATTACH via direct --takeover while the tab geometry
  never left fl's stored size, and rootshell's mirroring is client-side.
  Moot under fork-free (no control-stream viewer, no claims).
- **Focus fix uses the widget's proven form**: `hl.dsp.focus({window =
  "title:…"})`, not legacy `hyprctl dispatch focuswindow` (still valid —
  applies to popup row focus in the widget).
- **Park message fiction**: [SUPERSEDED by cutover — fl take and the park
  path are deleted outright, not reworded].
- **Phase 8 transport must be evaluated against `herdr machine add`**
  (upstream saved-machines + SSH stdio bridge) before building a bespoke
  flock transport — ride herdr's maintained path where it fits.
- **Pairing caveat**: Heeler's ceremony needs real OpenSSH; Tailscale SSH
  alone can't run it (forced commands). Verify remotes run stock sshd.

## Environment facts (for any session touching this)

- Repo = plugin: manifest.json at root; deploy = rsync-minus-.git into
  ~/.config/omarchy/plugins/flock/ (process + restart/verify loop in AGENTS.md).
- Server state is the user's live session: NEVER `herdr server stop`;
  config goes through `herdr server reload-config`.
- docs/architecture-notes.md is HISTORICAL since the fork-free cutover —
  describes the control-stream dialect fl no longer speaks. Fork quirks
  (workspace-create object shape, title suffix, close semantics) that
  survive the cutover are noted in the relevant roadmap items.
- Round-3 close semantics (window close → park agent panes / close
  agentless panes) survived fl_client's deletion: its new home is the
  M0.1-forkfree attach wrapper — on attach-process exit, re-check pane
  agent-ness against the CLI, then close if agentless (same freshness
  rule; never on park/error exits).
- Heeler plugin is installed and enabled on this laptop
  (`herdr plugin list` → heeler, config at ~/.config/herdr/plugins/config/heeler).
- Research clones (read-only, scratch): /home/noor/repos/{rootshell,Heeler,
  rootshell-herdr-fork} and /tmp/rootshell-herdr-fork-branch (fork branch;
  re-clone from github.com/kitknox/herdr if /tmp was cleaned).
