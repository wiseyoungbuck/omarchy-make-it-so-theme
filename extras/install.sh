#!/usr/bin/env bash
# Install the Make It So extras: the engine hum, its bar toggle, its keybinding,
# and the login hooks (random wallpaper, hum on at login).
#
# Omarchy never runs code from a theme installed with `omarchy theme install`,
# so these are opt-in. Run this yourself after installing the theme:
#   ~/.config/omarchy/themes/make-it-so/extras/install.sh
#
# Safe to run again; it only adds what is missing. Undo with uninstall.sh.
#
#   --plain-icon   show a generic rocket glyph in the bar instead of the Starfleet delta
#   --delta-icon   back to the delta (the default)
# MAKE_IT_SO_NO_RELOAD=1 skips reloading Hyprland and the shell (used by tests).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share/make-it-so"
MODULES="$HOME/.config/omarchy/bar/modules"
HOOKS="$HOME/.config/omarchy/hooks/post-boot.d"
BINDINGS="$HOME/.config/hypr/bindings.lua"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
ICON=""
for arg in "$@"; do
  case $arg in
    --plain-icon) ICON=plain ;;
    --delta-icon) ICON=delta ;;
    *) echo "usage: ${0##*/} [--plain-icon|--delta-icon]" >&2; exit 2 ;;
  esac
done
BIND_LINE='o.bind("SUPER + ALT + E", "Engine hum", "engine-hum toggle")'

for dep in mpv socat busctl jq pgrep; do
  command -v "$dep" >/dev/null || { echo "Missing dependency: $dep" >&2; exit 1; }
done

say() { printf '  %s\n' "$*"; }
echo "Installing Make It So extras"

install -Dm755 "$SRC/bin/engine-hum" "$BIN/engine-hum"
install -Dm644 "$SRC/share/engine-hum.flac" "$SHARE/engine-hum.flac"
install -Dm644 "$SRC/share/delta.svg" "$SHARE/delta.svg"
install -Dm644 "$SRC/bar/engine-hum.qml" "$MODULES/engine-hum.qml"
for hook in "$SRC"/hooks/post-boot.d/*; do
  install -Dm755 "$hook" "$HOOKS/$(basename "$hook")"
done
say "engine-hum, sound, bar icon and login hooks"

# Keybinding: Super+Alt+E toggles the hum.
if [[ -f $BINDINGS ]] && grep -qF 'engine-hum toggle' "$BINDINGS"; then
  say "keybinding already present"
else
  mkdir -p "$(dirname "$BINDINGS")"
  [[ -f $BINDINGS ]] && cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  printf '\n-- Make It So theme: toggle the ambient engine hum ("Engage").\n%s\n' "$BIND_LINE" >> "$BINDINGS"
  say "keybinding Super+Alt+E"
fi

# Bar: the delta toggle, placed after the audio widget (or at the end of the right side).
if [[ -f $SHELL_JSON ]]; then
  if jq -e '[.bar.layout.right[]?.id] | index("engine-hum")' "$SHELL_JSON" >/dev/null; then
    say "bar icon already placed"
  else
    cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
    tmp=$(mktemp)
    jq --indent 2 '.bar.layout.right |= (
        (map(.id) | index("omarchy.audio")) as $i
        | if $i == null then . + [{"id":"engine-hum","type":"qml"}]
          else .[:$i+1] + [{"id":"engine-hum","type":"qml"}] + .[$i+1:] end)' \
      "$SHELL_JSON" > "$tmp" && mv "$tmp" "$SHELL_JSON"
    say "bar icon placed next to audio"
  fi
else
  say "no ~/.config/omarchy/shell.json yet: add {\"id\":\"engine-hum\",\"type\":\"qml\"} to bar.layout.right yourself"
fi

# Bar icon choice, kept on the widget's own shell.json entry.
if [[ -n $ICON && -f $SHELL_JSON ]]; then
  tmp=$(mktemp)
  if [[ $ICON == plain ]]; then
    jq --indent 2 '(.bar.layout.right[] | select(.id == "engine-hum")) += {"icon": "plain"}' "$SHELL_JSON" > "$tmp"
  else
    jq --indent 2 '(.bar.layout.right[] | select(.id == "engine-hum")) |= del(.icon)' "$SHELL_JSON" > "$tmp"
  fi
  mv "$tmp" "$SHELL_JSON"
  say "bar icon: $ICON"
fi

if [[ ${MAKE_IT_SO_NO_RELOAD:-0} != 1 ]]; then
  command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 || true
  command -v omarchy >/dev/null && omarchy restart shell >/dev/null 2>&1 || true
fi

echo "Done. Toggle the hum with Super+Alt+E or the delta in the bar."
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not on your PATH." ;; esac
