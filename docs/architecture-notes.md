# hd — Architecture Notes (ground truth)

Source of truth: empirical probes against the **running fork server** (`0.9.3-rootshell.0.1.9`),
the rootshell Swift client (clone @ /tmp/opencode/rootshell), the fork server source
(clone @ /tmp/opencode/herdr-fork, master), rootshell's `docs/herdr-control-mode.md`,
and rootshell issues #278 / #407.

> NOTE on version drift: GitHub master's `herdr control` is a raw direct-attach CLI
> (`--takeover --cols --rows`) and does NOT contain the rootshell JSON bridge.
> The installed binary (release channel) does: first line `control_opened` + all
> `terminal.*` / `tab.*` JSON methods verified live. Build against the *running
> binary*, verify each assumption empirically; guard the client at runtime
> (fail loudly if `control_opened` capabilities lack `terminal_control_stream >= 2`).

## 0. Decision record

- **Model B** (user-confirmed): everything in the `default` session; per-project
  workspaces named by cwd basename; each laptop window = ONE pane of that shared
  session via a custom pass-through control-stream client; iPhone (rootshell)
  attaches to the same panes natively. Win+Enter stays stock (plain foot); `hd`
  / `hd list` do the connecting; sidebar collapsed globally; bar widget carries
  agent state (≤3 priority dots + badge popup).
- **Sequencing**: `omarchy update` first, then build. Packaging: all-in-one git
  repo (omarchy plugin manifest for the bar widget + install.sh for the rest).
- **Issue #278 (sticky-size)**: claim discipline only on activation edges;
  `claim:false` for routine updates; takeover never automatic; owner surfaced in UI.
- **Issue #407 (detach/resume)**: window close = detach + `control.close`;
  attaching to a pane that already has a live `hd` window focuses that window
  instead of silently double-attaching (second attach requires `--new`).

## 1. Transport & handshake (verified live)

- Spawn local process: `herdr control` (optionally `--session NAME`; env for the
  bridge: `HERDR_CONTROL_CLIENT=hd/<version>`, `HERDR_CONTROL_PROTOCOL=3`).
  Unset `HERDR_ENV`/`TERM_PROGRAM` before launching from inside a herdr pane.
- **The client sends no hello.** First stdout line (unsolicited):
  `{"id":"control","result":{"type":"control_opened","connection_id":…,"boot_id":"…-…","version":"0.9.3-rootshell.0.1.9","protocol":22,"capabilities":{"live_handoff":true,"detached_server_daemon":true,"endpoint_protocol_generation":1,"surface_interest":true,"health_check":true,"ssh_agent_registration":false,"terminal_control_stream":3,"control_features":["shared_attach","geometry_ownership","geometry_controller","control_list","client_identity","query_authority","event_drain","event_gap","auto_input","pane_geometry"],"server_pid":…},"control_protocol":3}}`
- `control.error` lines (`not_found`, `unsupported`) or an `error` object can
  appear instead — every startup path must read the first line before writing.
  A child exit code 2 also means "no control stream".
- Shared viewing requires `shared_attach + geometry_ownership + geometry_controller`
  (all present on this server). `control_protocol` 3 ⇒ `pane_geometry` allowed.

## 2. Subscription schema (this server build; empirically resolved)

`events.subscribe` takes `{"subscriptions":[{…}]}` — **one object per event**:

- Core topology set (rootshell's `topologySubscriptions`) is accepted **without
  `pane_id`**: `workspace.{created,updated,closed,renamed,moved,reordered,focused}`,
  `tab.{created,closed,renamed,moved,focused}`,
  `pane.{created,updated,closed,focused,moved,exited}`, `layout.updated`.
- `pane.agent_status_changed` **REQUIRES a concrete `pane_id`** — without one the
  request errors `missing field pane_id`; with `null` errors `invalid type: null,
  expected a string`. Subscribe per attached pane only.
- Other legal types (from the server's own variant listing): `workspace.
  metadata_updated`, `worktree.{created,opened,removed}`, `pane.output_matched`,
  `pane.agent_detected`, `pane.sc`roll_changed. Unknown types are rejected with
  the full variant list (runtime-discoverable).
- Ack: `{"type":"subscription_started"}`. Events then arrive as
  `{"event":"<tab_created>", "data":{…}}` — note **underscores in pushed event
  names** (`tab_created`) vs dots in subscription types (`tab.created`).

## 3. Topology (verified live)

- `session.snapshot` → result `{snapshot:{version,protocol,focused_workspace_id,
  focused_tab_id,focused_pane_id,workspaces,tabs,panes,layouts,agents}}`.
- `WorkspaceInfo`: `workspace_id,number,label,focused,pane_count,tab_count,active_tab_id,agent_status`.
- `TabInfo`: `tab_id,workspace_id,number,label,focused,pane_count,agent_status`.
- `PaneInfo`: `pane_id,terminal_id,workspace_id,tab_id,focused,cwd,foreground_cwd,
  label,agent,title,terminal_title,terminal_title_stripped,display_agent,agent_status,
  state_labels,tokens,agent_session,scroll{offset_from_bottom,max_offset_from_bottom,
  viewport_rows},revision`.
- `PaneInfo` for a pane created in the *same* bridge lifetime is present
  immediately (verified). A pane created before the bridge attaches may be
  missing from that bridge's first snapshot in one probe — re-request after
  subscribing; topology can also be rebuilt from the JSON API (`herdr pane list`
  / `tab list` / `workspace list`) which shares these shapes.
- `agents{}` entries mirror AgentInfo (id fields per rootshell AgentInfo list).

## 4. Streams per pane (verified live)

- `terminal.attach` params: `{target: <terminal_id>, answer_queries:"client",
  history_limit_bytes:1048576, takeover:false}` → result `{type:"terminal_attached",
  attach_id:"5-0", terminal_id, pane_id}`.
  - On a server/terminal already owned and `takeover:false`, expect the same
    failure path as rootshell: error response / `ServerShutdown`-like reason.
    **Never auto-takeover.** Park with an affordance instead.
  - `answer_queries:"client"` is always sent (rootshell never changes it).
- Pushed record `terminal.snapshot` can arrive BEFORE the attach response
  continuation — always key routing on `attach_id`.
  Fields: `{type:"terminal.snapshot",attach_id,snapshot:{seq,active_screen:"primary"|"alternate",
  primary:<VT string>,alternate:<VT string>,state_ansi:<VT>,pen_ansi?,
  cursor:{x,y,visible,shape,pending_wrap,pending_wrap_cell?},
  state:{cols,rows,title?,cwd?,mouse_reporting?,bracketed_paste?,focus_reporting?},truncated}}`.
- `terminal.output{type,attach_id,seq,bytes(base64)}` — apply in order; >16 MiB
  line = stream kill; queue cap 8 MiB; EOS-carry cap 256 KiB.
- `terminal.gap{attach_id,seq,dropped_bytes}` → **invalidate queue, request exactly
  ONE snapshot** (`terminal.snapshot` method `{attach_id}`; the repair comes as a
  pushed record, ack ≠ payload), render nothing until it lands.
- `terminal.authority{attach_id,answers_queries:bool}` — boundary markers must
  ride the output (rootshell's `CSI ?15999$p / ?15998$p` self-probes consumed
  against replies `?15999;0$y / ?15998;0$y`). Absent ⇒ we answer (protocol-1 rule).
- `tab.layout{type,layout:{workspace_id,tab_id,zoomed,area{x,y,width,height},
  focused_pane_id,panes:[{pane_id,focused,rect{x,y,width,height},terminal_size?}...],
  geometry_controller?{kind:"control"|"client"|"none",connection_id,chrome}}}` —
  pushed for every tab (9 records observed right after attach). This is how a
  follower learns the owner's layout; `geometry_controller` names the owner.
- `terminal.detached{attach_id,reason:"closed"|"takeover"}` — takeover ⇒ park the
  pane with a "take control" affordance; never auto re-attach.
- Input: `terminal.input{attach_id,bytes<base64>[,auto:true]}` fire-and-forget
  ids `i<N>`; responses `r<N>`/`t<N>`; typed input never blocks on responses.
- `control.close` `{"method":"control.close","params":{}}` on any exit path —
  dead bridges otherwise keep counting as viewers that can hold geometry.
- Keepalive: `ping` `{}` every 30 s, 10 s timeout; request deadline 15 s;
  reconnect backoff 2^n capped at 30 s (rootshell values).

## 5. Geometry claim policy (verified forms)

- `tab.set_geometry {tab_id,cols,rows,cell_width_px,cell_height_px,chrome:"none",
  claim:<bool?>}` (owner = `geometry_controller.connection_id`).
- `cell px` measured from `TIOCGWINSZ` pixel fields (foot reports ws_xpixel/ws_ypixel).
- `claim:true` ONLY: (a) first push when owner is unknown/none, (b) activation
  edge — attach, or our foot window becoming the focused Hyprland window
  (watch `hyprland-ipc socket2` `activewindow` events), (c) explicit user action
  (`hd take`, divider drag on a foreign tab). One-shot, consumed on send.
- All other resizes `claim:false` (stored server-side, applied "the moment we
  interact"). Owners change only via server events — never self-evict.
- Floor: runtime clamps pane grids to ≥4 cols ×2 rows (`runtime.rs:252`).

## 6. Input routing & query authority

- Pane programs' CSI/DSR/DA queries surface in our output and get answered by
  foot's emulator reach us on stdin; classify replies per rootshell
  `isAutomaticReply` (CSI finals c/n/R/t/y + focus I/O + kitty-flags u; OSC/DCS);
  forward via `terminal.input auto:true` (server has `auto_input`).
- While NOT the query authority (`terminal.authority answers_queries:false`),
  swallow our foot's local replies instead of sending them.
- Never use focus-in reports as interaction (they must not steal geometry).

## 7. Snapshot replay discipline (from rootshell's `replayBytes`)

`CAN (0x18)` → `\e[?2026h\e[?1049l\e[0m\e[?25l` → `\e[r\e[?69l\e[?6l\e[?7h\e[4l\e(B\f` →
`\e[3J\e[2J\e[H` → primary content → (if alternate: `\e[?1049h\e[2J\e[H` + alternate)
→ `state_ansi` → DECOM-aware CUP to cursor → pending-wrap cell reprint (if any,
with pen_ansi) → `\e[?2026l`. Prefix each replay with CAN + authority marker.

## 8. hd components (to build)

| Piece | Notes |
|---|---|
| `hd` (bash→python entry) | arg verb: attach flow / `list` (fzf) / take / status. Creates workspace (cwd basename, reuse if exists) + tab w/ single root pane (CLI `tab create --cwd … --no-focus`), then execs the pass-through client in THIS window. |
| `hd-client` (python3 stdlib only) | the control-stream terminal: spawn bridge, subscribe, snapshot, attach target pane, byte-pump (output→stdout, stdin→input, replies→auto), geometry push, gap/snapshot recovery, keepalive, clean close. Titles: `hd:<workspace>/<pane>` (+agent/status suffix). |
| `hd list` | fzf over snapshot panes (`workspace/tab · agent status · cwd`), attach current window. |
| `hd status` / `agent list` for the widget | JSON API polling (`herdr agent list` every 2s) — event feeds proven but scoped; polling is robust and cross-session. |
| Bar widget (omarchy plugin QML) | ≤3 dots (blocked→done→working, latest first), badge popup grouped by workspace; click = `hl.dsp.focus({window = "title:hd:[^ ]*<pane>"})` or spawn `hd <pane>`. |
| Hyprland focus watcher | socket2 `activewindow>>class,title` → send `ACTIVATE` to the matching hd-client over its control fifo → claim:true push. |
| Installer + repo | `~/repos/hd-herdr`: `hd/` client, `plugin/` manifest+QML, `install.sh` (checks omarchy, herdr fork presence & version, PATH, config.toml sidebar collapse, foot app-ids, hyprctl form). |

## 9. Open verifications (before v1 ships)

- [ ] `terminal.detach` graceful record semantics on the live bridge.
- [ ] claim:true acceptance + follower layout on this server (two clients).
- [ ] gap generation under output flood (dd through a pane) — repair path.
- [ ] alternate-screen snapshot replay correctness in vim/htop.
- [ ] named session bridge (`--session work`) env plumbing.
- [ ] `herdr control` behavior when server stopped (bridge error line?).
