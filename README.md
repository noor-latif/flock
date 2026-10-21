# winherd — one window, one agent

`winherd` rebinds plain terminal windows to single panes of your herdr session,
so an agent gets a real, movable window with your tiling kept for
*you*. Its Omarchy bar widget shows every agent in the session as one status
badge and a click-to-focus popup. Your iPhone (rootshell) pairing is
unaffected — `wh` windows are just more clients of the same session.

## Dependencies — read this first

| Need | Why |
|---|---|
| **Omarchy** | the bar widget is an omarchy-shell plugin |
| **The rootshell herdr fork** | the whole thing speaks the fork's JSON control stream (`herdr control`); upstream herdr 0.9.x has none — the installer refuses up front |
| `foot` | spawned agent windows |
| `python3` (3.9+) | launcher + client |
| `fzf` (optional) | only for `wh list` |

The fork must resolve on PATH even in compositor-exec'd windows (they skip
bashrc); set `HERDR_BIN_PATH` or make sure its `bin/` dir is on PATH
globally.

## Install

```sh
git clone https://github.com/noor-latif/winherd.git && cd winherd
./install.sh          # installs wh (~/.local/bin) + offers the bar widget
```

The installer verifies the running server *and* the control stream before
touching anything, then offers the plugin enable and the
`sidebar_start_collapsed` config (pane-per-window makes the in-herdr sidebar
dead weight).

## Usage — in a plain foot window (Win+Enter)

```sh
wh                     # attach to a pane of this cwd's workspace, find or create
wh list                # fzf over every pane of the session
wh take                # fit geometry (claim) for the pane this window holds
wh <pane_id> --force   # watch a claimed pane as a viewer, never claims
wh status              # agent JSON dump for scripting
```

## Usage — the bar badge and popup

The badge is one disc in the standard icon slot:

- **number inside = agents waiting on you** (blocked + finished-not-seen;
  empty disc when nobody waits, no "0")
- **color = the worst state on the floor**: red blocked > green working >
  blue done; all idle = a thin bright ring
- count ≥ 10 grows the disc sideways into a pill; the full number always
  fits
- hover = counts ("winherd — 1 blocked · 1 done · 9 idle")

Click opens the panel: agents grouped by workspace, each row with its own
state dot, title, and `cwd · pane id`. **Clicking a row focuses that
agent's window (spawning one on the pane if none exists), marks it seen —
the badge count drops — and closes the panel.** Dismissals survive shell
restarts (`~/.local/state/winherd/acks.json`); an agent that starts and
finishes again re-alerts on its own.

Right-click the badge re-polls. The widget never steals focus: only your
clicks move windows.

## Claim discipline (rootshell issue #278)

Claims move only on activation edges — the first attach on an unowned pane,
explicit `wh take`, or hydr focus of this window. A second `wh` window on a
claimed pane is a viewer, and the takeover never happens automatically:
`wh take` from the other side, or the phone's claim button, moves it
deliberately.

## Troubleshooting

- **"does not expose the JSON control stream"** — that's upstream herdr
  resolving first; put the fork's `bin/` first on PATH.
- **"herdr server is not running"** — start it once with `herdr`.
- **"pane <id> closed — run wh in its workspace again"** — the pane died
  between launch and attach (or was closed while the window attached);
  the window parked instead of chasing a dead id. Close it and `wh` again.
- **"another client owns this pane"** — someone else holds it (phone, or
  another window). Watch with `--force` or take the claim if it's yours.
- **Window title needs to end in `pane <id>`** — the bar focuses windows by
  that suffix; if a prompt customizer renames your window, re-append it.
- **Restart the shell after touching the widget**: `omarchy-restart-shell`
  (plugin QML does not hot-reload).

## Layout

```
manifest.json     omarchy bar-widget manifest (id: winherd)
BarWidget.qml     badge + popup (Quickshell/omarchy-shell Panel)
wh/wh             launcher: find-or-create, rebind, fzf picker, attached-guard
wh/wh_client.py   the pass-through client (control stream ↔ pty)
install.sh        user-level installer (no sudo)
ROADMAP.md        tracked plan + decisions
AGENTS.md         notes for agents working on this repo
docs/             protocol & design notes
```

## Testing

`wh status` + `omarchy-shell winherd refresh` ("ok") are the smoke tests.
The ghost-path/client behaviors are stub-tested in-session (see git log);
full multi-window e2e replayed from the dev scratch, not committed here.
