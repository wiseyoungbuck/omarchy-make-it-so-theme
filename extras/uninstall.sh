#!/usr/bin/env bash
# Remove everything extras/install.sh added. Leaves the theme itself in place.
set -euo pipefail

BINDINGS="$HOME/.config/hypr/bindings.lua"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

"$HOME/.local/bin/engine-hum" off >/dev/null 2>&1 || true
rm -f "$HOME/.local/bin/engine-hum" \
      "$HOME/.config/omarchy/bar/modules/engine-hum.qml" \
      "$HOME/.config/omarchy/hooks/post-boot.d/make-it-so-random-bg" \
      "$HOME/.config/omarchy/hooks/post-boot.d/make-it-so-engine-hum"
rm -rf "$HOME/.local/share/make-it-so"

if [[ -f $BINDINGS ]] && grep -qF 'engine-hum toggle' "$BINDINGS"; then
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  sed -i -e '/^-- Make It So theme: toggle the ambient engine hum/d' -e '/engine-hum toggle/d' "$BINDINGS"
fi

if [[ -f $SHELL_JSON ]] && jq -e '[.bar.layout.right[]?.id] | index("engine-hum")' "$SHELL_JSON" >/dev/null; then
  cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
  tmp=$(mktemp)
  jq --indent 2 '.bar.layout.right |= map(select(.id != "engine-hum"))' "$SHELL_JSON" > "$tmp" && mv "$tmp" "$SHELL_JSON"
fi

if [[ ${MAKE_IT_SO_NO_RELOAD:-0} != 1 ]]; then
  command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 || true
  command -v omarchy >/dev/null && omarchy restart shell >/dev/null 2>&1 || true
fi
echo "Make It So extras removed."
