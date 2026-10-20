#!/usr/bin/env bash
# hd — install the herdr companion client + bar widget for Omarchy.
#
# Run from inside this repo (cloned or downloaded); no sudo involved:
#
#   git clone https://github.com/<you>/hd-herdr.git && cd hd-herdr && ./install.sh
#
# What it does:
#   1. checks the prerequisites (python3, fzf, foot, and a herdr binary that
#      speaks the JSON control stream — the rootshell fork, not upstream)
#   2. installs the `hd` launcher + client into ~/.local
#   3. optionally installs the bar widget as an omarchy plugin and enables it
#   4. optionally sets sidebar_start_collapsed in the herdr config (with `hd`
#      every pane lives in its own window, so the in-herdr sidebar is dead
#      weight)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$HOME/.local/lib/hd-herdr"
BIN_DIR="$HOME/.local/bin"
HERDR_CONFIG="$HOME/.config/herdr/config.toml"

say()  { printf 'hd-install: %s\n' "$*"; }
fail() { printf 'hd-install: FAIL: %s\n' "$*" >&2; exit 1; }
skip() { printf 'hd-install: (skipped) %s\n' "$*"; }

interactive() { [[ -t 0 && -t 1 ]]; }

# ---------------------------------------------------------------- consent
if ! interactive; then
  if [[ ${HD_INSTALL_UNATTENDED:-} != 1 ]]; then
    fail "non-interactive run; set HD_INSTALL_UNATTENDED=1 to skip the checks"
  fi
elif command -v gum >/dev/null 2>&1; then
  gum style --border normal --padding "1 2" \
    "install hd?" \
    "" \
    "• adds ~/.local/lib/hd-herdr (client) and ~/.local/bin/hd (launcher)" \
    "• touches nothing outside \$HOME" \
    "" \
    "Rebinds a plain foot window to one herdr pane; the iPhone (rootshell)" \
    "keeps its pairing; claims only move on your explicit activation."
  gum confirm "Continue?" || { say "cancelled"; exit 0; }
fi

# ----------------------------------------------------------- prerequisites
python3 --version >/dev/null 2>&1 || fail "python3 is required (comes with omarchy)"
command -v fzf   >/dev/null 2>&1 || say "fzf not found — 'hd list' needs it (sudo pacman -S fzf)"
command -v foot  >/dev/null 2>&1 || say "foot not found — bar widget spawn-open needs it"

# herdr must resolve to the fork that ships the JSON control stream.
HERDR_RESOLVED=$(bash -lc 'command -v herdr' 2>/dev/null || true)
if [[ -z $HERDR_RESOLVED ]]; then
  fail "herdr not found on PATH. hd needs the rootshell fork (e.g.
  clone https://github.com/<fork>/herdr && install its release to ~/.local/opt/herdr-rootshell
  and add that bin dir to PATH in ~/.bashrc)"
fi
say "herdr: $HERDR_RESOLVED"

# control-stream probe: the first line on stdout must announce control_opened.
PROBE=$(timeout 5 bash -lc 'HERDR_CONTROL_CLIENT=hd/install HERDR_CONTROL_PROTOCOL=3 herdr control </dev/null 2>/dev/null | head -1' || true)
if [[ $PROBE != *control_opened* ]]; then
  fail "this herdr binary does not expose the JSON control stream.
  hd requires the rootshell fork build; upstream 0.9.x fails here. If you have
  both binaries, put the fork's bin dir FIRST on PATH (it wins via ~/.bashrc)."
fi
say "control stream: ok (protocol 3, hd client accepted)"

SERVER=$(env -u HERDR_ENV -u TERM_PROGRAM "$HERDR_RESOLVED" status 2>/dev/null | head -c 200 || true)
if [[ -z $SERVER ]]; then
  say "warning: herdr server is not running right now; start it once with: herdr"
fi

# ---------------------------------------------------------------- install
mkdir -p "$LIB_DIR" "$BIN_DIR"
cp "$REPO_DIR/hd/hd" "$REPO_DIR/hd/hd_client.py" "$LIB_DIR/"
cat > "$BIN_DIR/hd" <<SHIM
#!/usr/bin/env bash
exec python3 "\$HOME/.local/lib/hd-herdr/hd" "\$@"
SHIM
chmod +x "$BIN_DIR/hd" "$LIB_DIR/hd"
say "installed: $BIN_DIR/hd -> $LIB_DIR/hd"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "note: $BIN_DIR is not on your PATH; add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to ~/.bashrc (omarchy usually has it)" ;;
esac

# ---------------------------------------------------------------- widget
if [[ -d "$REPO_DIR" && -f "$REPO_DIR/manifest.json" ]]; then
  if [[ -d "$HOME/.config/omarchy/plugins/hd-herdr" ]]; then
    say "bar widget: already installed at ~/.config/omarchy/plugins/hd-herdr (update with: omarchy plugin update hd-herdr — or rerun this from a fresh clone)"
  elif command -v omarchy >/dev/null 2>&1 && interactive; then
    if gum confirm "Install the bar widget as an omarchy plugin now?" ; then
      # the widget loads hd/ out of the plugin dir it lives in, so this repo
      # IS the plugin — install it in place
      mkdir -p "$HOME/.config/omarchy/plugins"
      cp -a "$REPO_DIR/." "$HOME/.config/omarchy/plugins/hd-herdr/"
      omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
      say "bar widget: installed. enable it with: omarchy plugin enable hd-herdr --section right"
      say "(or pick it in the bar config after a shell restart)"
    else
      say "bar widget: left uninstalled. repo stays at $REPO_DIR"
    fi
  else
    say "bar widget: install later with:
      omarchy plugin add <this-repo-git-url> --enable
   (repo root is the plugin: manifest.json must stay at the top)"
  fi
fi

# ---------------------------------------------------------------- config
if [[ -f $HERDR_CONFIG ]] && grep -q "sidebar_start_collapsed" "$HERDR_CONFIG" 2>/dev/null; then
  skip "sidebar_start_collapsed already set in $HERDR_CONFIG"
elif [[ -f $HERDR_CONFIG ]] && interactive && command -v gum >/dev/null 2>&1; then
  if gum confirm "Set sidebar_start_collapsed = true in the herdr config?" ; then
    printf '\n# pane-per-window (hd) makes the sidebar dead weight\nsidebar_start_collapsed = true\n' >> "$HERDR_CONFIG" \
      && "$HERDR_RESOLVED" server reload-config >/dev/null 2>&1 \
      && say "herdr config: sidebar starts collapsed; applied via reload-config"
  fi
else
  say "optional: add 'sidebar_start_collapsed = true' under [ui] in $HERDR_CONFIG, then run: herdr server reload-config"
fi

say "done. try it: open a plain foot window (Win+Enter) and run 'hd'"
