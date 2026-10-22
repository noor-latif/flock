# AGENTS.md — flock

flock: herdr agents of the default rootshell-fork session, ONE WINDOW PER
PANE, surfaced as an omarchy bar badge + popup. This repo IS the omarchy
plugin (manifest.json at root) and ships the `fl` CLI. Start of any session:
read ROADMAP.md (the tracked plan), then `git log --oneline -5`.

STATE: the fork is off PATH; `herdr` is stock 0.9.5 (see ROADMAP URGENT note).
New `fl` windows fail until the PR-2 cutover; the fork-quirk notes below describe
the still-running fork server.

## Map

- `BarWidget.qml` — bar badge + panel (popup). The only QML.
- `fl/fl` — launcher: resolve-or-create workspace for cwd, attach one pane.
- `fl/fl_client.py` — per-window pass-through client (control-stream bridge,
  VT pass-through, geometry ownership per rootshell#278 discipline).
- `install.sh` — user-level installer (probes the fork's control stream).
- `docs/architecture-notes.md` — fork protocol ground truth.
- `ROADMAP.md` — the plan; update statuses there when working it.

## Deploy + verify loop (after EVERY code edit)

```
cp BarWidget.qml ~/.config/omarchy/plugins/flock/BarWidget.qml          # qml
cp fl/fl fl/fl_client.py ~/.config/omarchy/plugins/flock/fl/            # plugin copy
cp fl/fl fl/fl_client.py ~/.local/lib/flock/ && echo ok                 # live CLI
omarchy-restart-shell                                                     # QML never hot-reloads
journalctl --user _CMDLINE="quickshell -n -p /usr/share/omarchy/shell" --since "-20s" \
  | grep -iE "flock|not a type|Unable" | grep -v "qmlscanner\|portal"
omarchy-shell flock refresh     # expect "ok"
```
Plugin QML does NOT hot-reload: the shell runs with QS_DISABLE_FILE_WATCHER=1,
and "Local plugin changed, reloading" lines it logs are stale — restart to be
sure. Skip reload lines only when a NEW startup block follows them.

## Anti-bloat (the repo is ~2k lines of code; keep it that way)

- Deletion over addition. A fix that removes code beats one that adds a layer.
  The Phase 5 cutover exists to delete ~800 lines — do not patch around them.
- No new files for planning, notes, reviews, or handoffs. Plans live in
  ROADMAP.md only, capped at ~150 lines; delete finished or superseded items
  instead of annotating them ("SUPERSEDED", "was wrong", strikethroughs).
- No speculative code or phases. If it is not in the next milestone, it is one
  line under "Deferred" in ROADMAP.md, not a design.
- No new dependencies, abstractions, config knobs, or flags without a request.
  One logical change per commit; a commit that only reshuffles docs needs a
  reason beyond "folded review round".
- Review output (/tmp/flock-review/, opencode runs) is scratch: fold the
  decision into ROADMAP.md in a line or two, never paste the findings.
- Docs describe what is true now. When code is deleted, delete or fix the doc
  that described it in the same commit.

## Hard limits

- The user's machine IS the runtime. Never `herdr server stop` (use `herdr
  server reload-config` after config edits). No window spawns / panel
  toggles / focus steals without saying so first.
- herdr calls in tool shells need `env -u HERDR_ENV -u TERM_PROGRAM bash -lc`.
- Do not run `fl` bare in a tool shell — it execvp's a client that takes over
  stdin. Test topology with stubs (runpy + pick_and_prepare_target) or `fl
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
- Until the PR-2 cutover: window titles must END with `pane <pane_id>` — the
  widget's focus matcher scans hyprctl clients for exactly that needle. PR-2
  replaces this with foot app-id `flock-<pane_id>` (no titles; ROADMAP M0.1).
- Safe herdr checks: `python3 -I tests/pty_attach.py` runs against a sandboxed
  server. Use it, not the live session, to test attach behaviour.

## Working with the user

- They judge by screenshots: write yours with `grim -g "x,y WxH"` + `magick
  ... -resize 500%`, and read theirs from ~/Pictures (newest first).
- Grill big design decisions in rounds (skill: grilling), with concrete
  pixel-anchored options and a recommended first option. Never abstract
  question wording.
- Pending grills live in ROADMAP.md as OPEN decisions — resolve them before
  implementing the item they gate.
- Git: plain commits work (global identity is set). Commit per completed
  plan item; ROADMAP status tick and commit in the same commit when
  possible.
- GitHub ssh/https push available: gh CLI authenticated as noor-latif,
  https protocol. Public repo name for phase 2: github.com/noor-latif/flock.

## Hard-won traps (do not relearn these)

- **Stub tests must patch real imported modules, never runpy**: runpy.run_path
  returns a snapshot dict — rebinding names on it does NOT reach the
  functions' true globals, so a "stubbed" call fired a REAL
  `herdr pane close` and deleted a live pane. Proof: 2026-10-22, wB:p1.
  Use importlib SourceFileLoader for the extension-less `fl/fl`; fake
  pane ids (wTEST:*) only; after any accidental fork mutation, verify
  workspace state and honestly restore + disclose to the user.
- **HERDR_ENV=1 rides in agent tool-shells AND trips the launcher's own
  TUI guard** — the `env -u HERDR_ENV -u TERM_PROGRAM` prefix applies to
  `fl` itself, not just herdr CLI calls.
- **Rename/contact-surface mechanics**: the plugin id lives in manifest.json
  + shell.json registration + the run-dir fifo subdir; pre-rename clients
  keep fifos under the old dir, so guards read both during transitions.
  Quickshell hot-reloads QML on plugin dir change ("Local plugin changed,
  reloading"); `omarchy-restart-shell` refuses while the session is locked.
- **Close semantics default** (grill round 3): window close (HUP/SIGTERM)
  parks agent panes (kept, agent runs server-side) and closes agentless
  panes via `herdr pane close` — freshness re-checked live before closing;
  overridden by ~/.config/flock/config.toml or FLOCK_CLOSE_SHELLS. The
  disposition never runs on park/error exits.
- **fl --force is a flag** parsed out of positional args everywhere — it
  once became a literal pane id ("attaching to --force", argparse crash).
- `herdr update` upgrades the fork binary; `--handoff` migrates the live
  server in place (agents survive). Upstream 0.9.x has no control stream →
  the fork stays dependency #0.
