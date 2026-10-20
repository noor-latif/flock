# hd — one window, one agent

`hd` rebinds a plain terminal window to a single [herdr](https://github.com/herdr) pane,
so you stop choosing between "agent visible in the tiling layout" and "agent in a real
window". Your iPhone (rootshell) pairing and the macOS/Linux herdr session keep working
as before — `hd` is only another client of the same session.

Pairs with the Omarchy bar widget in this repo: a single state-colored status icon
and a click-to-focus list of every agent grouped by workspace.

## Quickstart

Prereqs: Omarchy (or any Hyprland + foot setup), the herdr fork with the JSON control
stream on PATH (`bash -lc 'command -v herdr'`), `python3`, `fzf`.

```sh
git clone https://github.com/<you>/hd-herdr.git && cd hd-herdr
./install.sh          # client + launcher; offers bar-widget install
```

Then, in a plain terminal window (Win+Enter):

```sh
hd            # attach this window to a pane of the focused workspace (find or create)
hd list       # pick any pane with fzf (open a new window for it)
hd take       # take over the pane whose window you're replacing (via its title)
hd <pane-id> --force   # shared viewing: this window watches, never claims
```

## How it behaves

- **1 window = 1 pane.** The window rebinds itself to the pane: herdr's server sends
  snapshots, keystrokes flow in, geometry follows yours. Hyprland keybinds are untouched;
  no session, tab or pane is ever created except when you ask for a *new* pane.
- **Claims move only when you move them** (rootshell issue #278 discipline). Attaching a
  second window to a claimed pane gives you a *viewer*, not the claim: `--force` or
  picking the pane again in `hd list` hints exactly that.
- **Titles stay truthful**: the window title ends in `pane <id>` so the bar widget (and
  any script) can find the window that shows a given pane.

## Bar widget

Enabled via `omarchy plugin add <this-repo-url> --enable --section right` (repo root is
the plugin). It polls `herdr agent list` + `workspace list` every 2s and shows:

- one status icon in the standard omarchy icon slot, colored by the worst active state
  (blocked alert · working activity · done check · dim when nothing is active)
- a hover tooltip with the counts ("herdr agents — 3 working · 1 blocked · 9 idle")
- click → panel with **all** agents grouped by workspace; a row click focuses the window
  viewing that pane, spawning one if none exists

Settings (`manifest.json` schema): `refreshIntervalSec` (default 2). No digits or dots
in the bar — icons never carry counts, the panel is the detail surface. No desktop
notifications in v1; no focus stealing — the widget only focuses/open windows on
explicit clicks.

## Troubleshooting

- **`hd: this herdr binary does not expose the JSON control stream`** — you resolved to
  upstream `herdr` (0.9.x). Use the rootshell fork and put its `bin/` first on PATH.
- **`herdr server is not running`** — start the server once with `herdr`.
- **A window says the pane is already attached** — another window owns it. Take the hint
  it prints: `hd <pane> --force` to watch, or don't.
- **The herdr sidebar is still visible in new tabs** — add `sidebar_start_collapsed =
  true` under `[ui]` in `~/.config/herdr/config.toml`, then `herdr server reload-config`
  (never `herdr server stop` while agents are running).
- **iPhone (rootshell)** — nothing changes for the phone; it attaches to the same server.
  Pair as usual; `hd` windows and the phone can view shared panes under the same claim
  rules.

**Pairing order for phone + hd:** the phone's rootshell session was paired against this
herdr server already — `hd` windows just join it. In practice: the phone keeps whatever
pane it has paired; a newly opened `hd` window attaches to the pane you pick (or the
focused workspace's pane) as a *viewer* if the phone (or another window) holds the
claim; `hd take` (inside a window whose client is live) is what moves the claim to this
window. The phone's own claim button does the same from that side. Nothing on the phone
needs reinstalling; add the laptop's `hd` claim moves to your normal claim discipline.

## Layout

```
manifest.json     omarchy bar-widget manifest (id: hd-herdr)
BarWidget.qml     the widget (Quickshell/omarchy-shell Panel)
hd/hd             launcher: find-or-create, rebind, fzf picker, attached-guard
hd/hd_client.py   the client itself (control stream ↔ pty)
install.sh        user-level installer (no sudo)
docs/             protocol & design notes
```

## Testing

`e2e_multi.py` (in the dev scratch, not this repo) exercises the full path with two
fake windows: snapshot replay, shared viewing, claim handover, resize while claimed,
and pane persistence across client exit.
