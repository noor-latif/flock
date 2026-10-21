# AGENTS.md — winherd

winherd: herdr agents of the default rootshell-fork session, ONE WINDOW PER
PANE, surfaced as an omarchy bar badge + popup. This repo IS the omarchy
plugin (manifest.json at root) and ships the `wh` CLI. Start of any session:
read ROADMAP.md (the tracked plan), then `git log --oneline -5`.

## Map

- `BarWidget.qml` — bar badge + panel (popup). The only QML.
- `wh/wh` — launcher: resolve-or-create workspace for cwd, attach one pane.
- `wh/wh_client.py` — per-window pass-through client (control-stream bridge,
  VT pass-through, geometry ownership per rootshell#278 discipline).
- `install.sh` — user-level installer (probes the fork's control stream).
- `docs/architecture-notes.md` — fork protocol ground truth.
- `ROADMAP.md` — the plan; update statuses there when working it.

## Deploy + verify loop (after EVERY code edit)

```
cp BarWidget.qml ~/.config/omarchy/plugins/winherd/BarWidget.qml          # qml
cp wh/wh wh/wh_client.py ~/.config/omarchy/plugins/winherd/wh/            # plugin copy
cp wh/wh wh/wh_client.py ~/.local/lib/winherd/ && echo ok                 # live CLI
omarchy-restart-shell                                                     # QML never hot-reloads
journalctl --user _CMDLINE="quickshell -n -p /usr/share/omarchy/shell" --since "-20s" \
  | grep -iE "winherd|not a type|Unable" | grep -v "qmlscanner\|portal"
omarchy-shell winherd refresh     # expect "ok"
```
Plugin QML does NOT hot-reload: the shell runs with QS_DISABLE_FILE_WATCHER=1,
and "Local plugin changed, reloading" lines it logs are stale — restart to be
sure. Skip reload lines only when a NEW startup block follows them.

## Hard limits

- The user's machine IS the runtime. Never `herdr server stop` (use `herdr
  server reload-config` after config edits). No window spawns / panel
  toggles / focus steals without saying so first.
- herdr calls in tool shells need `env -u HERDR_ENV -u TERM_PROGRAM bash -lc`.
- Do not run `wh` bare in a tool shell — it execvp's a client that takes over
  stdin. Test topology with stubs (runpy + pick_and_prepare_target) or `wh
  status`.

## Design language (do not regress)

- Bar: ONE badge disc (`StateBadge`): count inside = waiting-on-you (blocked +
  done minus acked; 0 = bare disc; idle = bright thin ring, no "0"); color =
  worst state (blocked > working > done). Two digits go in a sideways pill.
  NEVER digits-as-inventory, +N suffixes, or !/✓ knocked-out marks — they
  were killed by decision (see ROADMAP decision log).
- Panel: first-party popup anatomy — PanelHero (+ badge), PanelSeparator,
  PanelSectionHeader small-caps, `CursorSurface` rows with hover pill; the
  focused agent's row is the selected one. Rows lead with a plain `StateDot`.
- State colors: working #98c379, blocked #e06c75, done #61afef, idle
  brighter mid-foreground ring (Qt.darker(foreground, 1.25), 2px).
- acks: in-memory map, pruned each poll to still-done agents; set on
  activation edges only (`applyClients` → `ackPane`). Counts skip acked.

## Fork quirks (already coded, don't "clean up" away)

- `workspace create` returns an OBJECT with a builtin root pane (old forks
  returned an id string) — accept both; skip `tab create` when the builtin
  pane exists, else create one.
- `first_pane` must use plain loops (a dict-comp once referenced an
  out-of-scope var → NameError; lesson: no scoping tricks in this repo).
- `herdr workspace close <id>` (positional).
- Window titles must END with `pane <pane_id>` — the widget's focus matcher
  scans hyprctl clients for exactly that needle; `wh pane <id>` is the
  pre-attach foot title and survives the same scan.

## Working with the user

- They judge by screenshots: write yours with `grim -g "x,y WxH"` + `magick
  ... -resize 500%`, and read theirs from ~/Pictures (newest first).
- Grill big design decisions in rounds (skill: grilling), with concrete
  pixel-anchored options and a recommended first option. Never abstract
  question wording.
- Pending grills live in ROADMAP.md as OPEN decisions — resolve them before
  implementing the item they gate.
- Git: plain commits work (global identity is set). Commit per completed plan item; ROADMAP status tick and
  commit in the same commit when possible.
- GitHub ssh/https push available: gh CLI authenticated as noor-latif,
  https protocol. Public repo name for phase 2: github.com/noor-latif/winherd.
