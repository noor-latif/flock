# winherd roadmap

Small, ordered by how often they bite. One line each; expand when picked up.

- [ ] **Panel auto-dismiss** — clicking a row focuses/spawns the agent's window;
      the popup should also close itself, so one click ends in one motion
      (today the panel stays open over the freshly focused window).
- [ ] **Persist dismissals** — seen/acknowledged agents live in shell memory;
      a shell restart or relogin re-rings everything still done. A tiny state
      file keyed by pane id would carry them across.
- [ ] **Keyboard row cursor** — panel rows are mouse-first; wire the
      CursorSurface keyboard-cursor path (arrows to move, enter to activate).
- [ ] **Chronological, activity-aware rows** — rows should read like a
      recency list: the pane you touched least sinks to the bottom. The
      current sort key (`state_change_seq`) only moves on agent state
      changes — typing or focusing a pane does not. Needs per-pane last
      activity tracked in the widget from herdr's pane.focused events.
- [ ] **Publish the repo** — the friends path (`omarchy plugin add <url>
      --enable`) needs a real git host URL; README and install.sh still carry
      a `<you>/winherd` placeholder.
