# flock — tracked plan

Status markers: ☐ todo · ◐ in progress · ☑ done. Update them here, not in chat.
Decisions locked in grilling are recorded in the decision log at the bottom;
anything marked OPEN needs a grilling round before implementation.

**OPEN grills blocking work:** (1) geometry claim-mode (Phase 5.1b — after a
live takeover probe); (2) stale-state budget per host class (Phase 6 / M0.3).
External reviewer: `opencode run -m opencode/deepseek-v4.1-flash-free` reviews
each milestone (M0 done → /tmp/flock-review/m0-review.md).
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

## Phase 5 — reclaim + window bugs (amended by M0 review)

The M0 review (`/tmp/flock-review/m0-review.md`, deepseek-v4.1-flash, verified
spot-checks) corrected two committed premises: protocol-3 tab followers are
NOT evicted by a second follower (`EvictScope::TabFollowerTakeover` evicts
only terminal-geometry attaches / protocol ≤1, fork `control_stream.rs:36-53`)
— so the takeover evict on the desktop must come from a direct terminal
attach (`--takeover`), and the claim-mode question needs a live probe
(`control.list` during a real takeover) before any design is locked.
Also "pure follower (no stored size)" and "phone-off restores desktop
geometry" are mutually exclusive: `tab.set_geometry{claim:false}` is
documented as stored-only (terminal.rs:180-183), and restore works only via
stored sizes (successor rule `control_stream.rs:426-461`), but a stored size
claims the tab on next keystroke (`:1495-1533`). OPEN 5.1b grill is exactly
one probe question: **does phone-off restore desktop geometry WITHOUT a
desktop keystroke — and if it needs one, is keystroke-claims acceptable?**
Answer decides follower-vs-owner; nothing else in the fork needs more
reading.

- ☐ M0.1 Fix-before-daemonise (one PR, mechanical parts):
  (a) acks loader/save mismatch — saveAcks writes a flat map, ackLoad
  requires `doc.acked`; on-disk file is flat ⇒ acks never load, Phase 1.3's
  "live-verified" was false. Fix round-trip.
  (b) widget pane matcher: `indexOf("pane "+id)` matches `w1:p1` inside
  `w1:p10` and ignores window class — use `endsWith` + class check (fl/fl
  already does).
  (c) park() leaks bridge/fifo/title and the parked client still answers
  `pane_is_attached` true — cleanup() on park, and the parked message must
  say `fl <pane> --force` (never `fl take`).
  (d) first-snapshot race: assign attach_id before pump processes the
  pushed snapshot (route by pending-attach queue, not by id compare).
  (e) ping timeout ("ping failed") never triggers reconnect — classify
  errors properly; single-flight reconnect (dedupe scheduled tasks).
  (f) monotonic request ids (fixed ids like "rt"/"att" collide across
  concurrent refreshes; wrong-reply delivery).
  (g) focus fix: `hl.dsp.focus({ window = "title:<escaped>" })` (widget's
  proven form), verify exit status.
  (h) `resolve_tab_id` fallback to snapshot pane record; claim-mode decision
  (5.1b) after the live probe — needs a grill, NOT in this PR.
- ☐ M0.2 One reader: extract widget's read path into `flockd --once` /
  `fl status --snapshot`; delete QML's shell pipeline. One parser, one schema.
- ☐ M0.3 Daemon read-only single-host (plain API socket, NOT control stream —
  `agent.wait`/`agent.prompt` are refused on control streams;
  `control.list` works on any connection). Widget consumes state.sock,
  falls back to the same `--once` implementation, renders degraded.
  Ack ledger stays widget-local until M0.5.
  OPEN grill: stale-state budget — hide degraded host rows vs render with
  last-good timestamp; reconcile interval per host class (local 2-5 s,
  ssh 10-30 s). Blocks M0.3's degraded-render work.
- ☐ M0.4 Actions split by owner: `host.*` (new_agent/prompt/close_pane/
  worktree) via flockd; `surface.focus_window` stays local; ack conditional
  on action result (today widget acks before focus succeeds).
- ☐ M0.5 Ack ownership → flockd (single writer; prune only on authoritative
  host snapshots — current prune drops acks during degraded polls).
- ☐ M0.6 Multi-host: host-qualified ids everywhere (acks, titles, fifos,
  actions — bare `w1:p1` collides across hosts), cross-host ordering key
  (`state_change_seq` is per-host; add host-local seq + receive time),
  gap policy extended with boot_id + pane-set changes.
- ☐ M0.7 Notifier plugin + fl TUI + macOS adapter. RULE: control plane via
  flockd only — terminal attach/output stays direct host↔surface, flockd
  never proxies `terminal.*`.

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

Review round (2026-10-22, post-commit advisories — folded in):

- **flockd is subscribe-push + poll-as-repair**, not pure-push: every native
  herdr client pairs subscriptions with snapshot reconciliation; the 2 s
  poll survives as repair/slow-reconcile only. Stale-state budget per host
  class is an explicit grill item (Phase 6.1b).
- **Takeover zombie root cause is fl's geometry ownership**, not just parked
  UX: claim-on-attach/focus makes the fork treat fl as a size-owner and evict
  it when the phone resizes. Follower-only mode (`claim:false` always) is the
  candidate that matches the user's "smallest device wins" mental model —
  verify phone-off restores desktop geometry live before choosing
  (Phase 5.1b).
- **Focus fix uses the widget's proven form**: `hl.dsp.focus({window =
  "title:…"})`, not legacy `hyprctl dispatch focuswindow` (Phase 5.2).
- **Park message fiction**: after takeover the fifo is gone, so the message
  must name `fl <pane> --force`, never `fl take` (Phase 5.1a).
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
- Fork quirks live in docs/architecture-notes.md and are fixed into fl;
  workspace create returns an object with a builtin root pane (both shapes
  accepted).
- Heeler plugin is installed and enabled on this laptop
  (`herdr plugin list` → heeler, config at ~/.config/herdr/plugins/config/heeler).
- Research clones (read-only, scratch): /home/noor/repos/{rootshell,Heeler,
  rootshell-herdr-fork} and /tmp/rootshell-herdr-fork-branch (fork branch;
  re-clone from github.com/kitknox/herdr if /tmp was cleaned).
