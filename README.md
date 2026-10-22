# flock — flocks all your agents into a native experience with omni-directional sync to your phone
I created this because I was annoyed at herdr not scaling well with my tiling window manager, and made me ditch years of tiling muscle memory and gave me a cluttered TUI. I missed the single focused windows and workspaces and created flock to give the herdr paradigm a deeper integration into my OS of choice (Currently the "AI-native" Omarchy distro) boosting the orchestration power.
Built on the "everything-is-a-plugin" framework behind the Deepseek harness, [Cordis](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cordis-tutorial/index.md) to allow you to do the same for your OS and distro. If you develop an abstraction for your own OS flavour, create an issue and I will add you to a list of supported endpoints at the end of this readme.

TLDR, what flock lets you do;
1. Bring your own OS
2. Bring your own cloud coding agents.
3. Bring your own terminal
4. Bring your own AI harness > BYOK
5. Bring all of this with you in your pocket with [Herdr Mobile](http://play.google.com/store/apps/details?id=dev.herdr.mobile&hl=en) for Android or [Heeler](https://github.com/ZingerLittleBee/Heeler) for iOS.
6. Bring it all back with **Herdr** powered multiplexing. No portal, or handing off back and forth.

Every session is always synced, no ACP involved, just native harness experience across all your devices.
Works wherever **Herdr** runs.

## Boring part:
`flock` rebinds plain terminal windows to single panes of your herdr session,
so an agent gets a real, movable window with your tiling kept for
*you*. Its batteries-included Omarchy bar widget (QuickShell + HyprLand) shows every agent in the session with its status and a click-to-focus. Your phone has access to the herdr sessions immediately, just like tmux. but with agent notifications built in. It's basically tmux -CC but built for the agent lifecycle.

## Everything below might be outdated and will get revamped soon
## Dependencies — read this first

| Need | Why |
|---|---|
| **Omarchy** | the bar widget is an omarchy-shell plugin |
| **The rootshell herdr fork** | the whole thing speaks the fork's JSON control stream (`herdr control`); upstream herdr 0.9.x has none — the installer refuses up front |
| `foot` | spawned agent windows |
| `python3` (3.9+) | launcher + client |
| `fzf` (optional) | only for `fl list` |

The fork must resolve on PATH even in compositor-exec'd windows (they skip
bashrc); set `HERDR_BIN_PATH` or make sure its `bin/` dir is on PATH
globally.

## Install

```sh
git clone https://github.com/noor-latif/flock.git && cd flock
./install.sh          # installs fl (~/.local/bin) + offers the bar widget
```

The installer verifies the running server *and* the control stream before
touching anything, then offers the plugin enable and the
`sidebar_start_collapsed` config (pane-per-window makes the in-herdr sidebar
dead weight).

## Usage — in a plain foot window (Win+Enter)

```sh
fl                     # attach to a pane of this cwd's workspace, find or create
fl list                # fzf over every pane of the session
fl take                # fit geometry (claim) for the pane this window holds
fl <pane_id> --force   # watch a claimed pane as a viewer, never claims
fl status              # agent JSON dump for scripting
```

## Usage — the bar badge and popup

The badge is one disc in the standard icon slot:

- **number inside = agents waiting on you** (blocked + finished-not-seen;
  empty disc when nobody waits, no "0")
- **color = the worst state on the floor**: red blocked > green working >
  blue done; all idle = a thin bright ring
- count ≥ 10 grows the disc sideways into a pill; the full number always
  fits
- hover = counts ("flock — 1 blocked · 1 done · 9 idle")

Click opens the panel: agents grouped by workspace, each row with its own
state dot, title, and `cwd · pane id`. **Clicking a row focuses that
agent's window (spawning one on the pane if none exists), marks it seen —
the badge count drops — and closes the panel.** Dismissals survive shell
restarts (`~/.local/state/flock/acks.json`); an agent that starts and
finishes again re-alerts on its own.

Right-click the badge re-polls. The widget never steals focus: only your
clicks move windows.

## Claim discipline (rootshell issue #278)

Claims move only on activation edges — the first attach on an unowned pane,
explicit `fl take`, or hydr focus of this window. A second `fl` window on a
claimed pane is a viewer, and the takeover never happens automatically:
`fl take` from the other side, or the phone's claim button, moves it
deliberately.

## Troubleshooting

- **"does not expose the JSON control stream"** — that's upstream herdr
  resolving first; put the fork's `bin/` first on PATH.
- **"herdr server is not running"** — start it once with `herdr`.
- **"pane <id> closed — run fl in its workspace again"** — the pane died
  between launch and attach (or was closed while the window attached);
  the window parked instead of chasing a dead id. Close it and `fl` again.
- **"another client owns this pane"** — someone else holds it (phone, or
  another window). Watch with `--force` or take the claim if it's yours.
- **Window title needs to end in `pane <id>`** — the bar focuses windows by
  that suffix; if a prompt customizer renames your window, re-append it.
- **Restart the shell after touching the widget**: `omarchy-restart-shell`
  (plugin QML does not hot-reload).

## Layout

```
manifest.json     omarchy bar-widget manifest (id: flock)
BarWidget.qml     badge + popup (Quickshell/omarchy-shell Panel)
fl/fl             launcher: find-or-create, rebind, fzf picker, attached-guard
fl/fl_client.py   the pass-through client (control stream ↔ pty)
install.sh        user-level installer (no sudo)
ROADMAP.md        tracked plan + decisions
AGENTS.md         notes for agents working on this repo
docs/             protocol & design notes
```

## Testing

`fl status` + `omarchy-shell flock refresh` ("ok") are the smoke tests.
The ghost-path/client behaviors are stub-tested in-session (see git log);
full multi-window e2e replayed from the dev scratch, not committed here.
