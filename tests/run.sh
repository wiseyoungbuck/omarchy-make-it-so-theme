#!/usr/bin/env bash
# Make It So test suite. No dependencies beyond bash, python3 and the tools the
# theme itself uses; tests that need a live session (audio, D-Bus, mpv-mpris)
# skip themselves when it isn't there.
#
#   tests/run.sh               run everything
#   tests/run.sh hum           run tests whose name contains "hum"
#   MAKE_IT_SO_CHECK_INSTALLED=1 tests/run.sh installed   also compare this repo
#                              with the copies installed on this machine
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HUM="$ROOT/extras/bin/engine-hum"
QML="$ROOT/extras/bar/engine-hum.qml"
WORK="$(mktemp -d)"
trap 'pkill -f "^mpv .*--title=mis-test-$$" 2>/dev/null; rm -rf "$WORK"' EXIT

pass=0 fail=0 skip=0
failed=()

skip() { echo "    skip: $*"; exit 77; }
die()  { echo "    $*"; exit 1; }
assert_eq() { [[ $1 == "$2" ]] || die "expected '$2', got '$1'${3:+ ($3)}"; }
need() { for c in "$@"; do command -v "$c" >/dev/null || skip "needs $c"; done; }
py() { python3 -I - "$@"; }

# Wait up to $1 seconds for a command to succeed.
eventually() {
  local deadline=$((SECONDS + $1)); shift
  until "$@"; do (( SECONDS >= deadline )) && return 1; sleep 0.25; done
}

# ---------------------------------------------------------------- theme files

test_colors_has_every_key_omarchy_expects() {
  local ref=/usr/share/omarchy/themes/catppuccin/colors.toml keys
  if [[ -f $ref ]]; then
    keys=$(grep -oE '^[a-z_]+' "$ref" | sort -u)
  else
    keys="accent background foreground selection red yellow green cyan blue magenta"
  fi
  for k in $keys; do
    grep -qE "^$k[[:space:]]*=" "$ROOT/colors.toml" || die "colors.toml is missing '$k'"
  done
}

test_colors_are_valid_hex() {
  local bad
  bad=$(grep -E '^[a-z_]+[[:space:]]*=' "$ROOT/colors.toml" | grep -vE '^(mode|hyprland_)' |
        grep -vE '=[[:space:]]*"#[0-9a-fA-F]{6}"' || true)
  [[ -z $bad ]] || die "not a #rrggbb colour: $bad"
}

test_text_colors_are_readable_on_the_background() {
  py "$ROOT/colors.toml" <<'EOF' || exit 1
import re, sys
c = dict(re.findall(r'^(\w+)\s*=\s*"(#[0-9a-fA-F]{6})"', open(sys.argv[1]).read(), re.M))
def lum(h):
    v = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    v = [x / 12.92 if x <= .03928 else ((x + .055) / 1.055) ** 2.4 for x in v]
    return .2126 * v[0] + .7152 * v[1] + .0722 * v[2]
def ratio(a, b):
    a, b = sorted((lum(a), lum(b)), reverse=True)
    return (a + .05) / (b + .05)
bg = c["background"]
body = ["foreground", "light_foreground", "bright_foreground", "accent"] + \
       [k for k in c if k.split("_")[-1] in ("red", "yellow", "orange", "green", "cyan", "blue", "magenta")]
bad = [f"{k} {c[k]} = {ratio(c[k], bg):.2f}:1" for k in body if ratio(c[k], bg) < 4.5]
bad += [f"{k} {c[k]} = {ratio(c[k], bg):.2f}:1 (needs 3)" for k in ("dark_foreground", "muted") if ratio(c[k], bg) < 3]
bad += [f"foreground on selection = {ratio(c['foreground'], c['selection']):.2f}:1"] if ratio(c["foreground"], c["selection"]) < 4.5 else []
if bad:
    print("    below WCAG AA:\n      " + "\n      ".join(bad)); sys.exit(1)
EOF
}

test_palette_signature_is_unchanged() {
  # The colours the theme is built around. Change these on purpose, not by accident.
  local -A want=(
    [mode]=dark [background]="#11141c" [foreground]="#e3d8c3"
    [accent]="#e8666e" [yellow]="#e2b25a" [selection]="#4a2329"
  )
  for k in "${!want[@]}"; do
    assert_eq "$(sed -nE "s/^$k[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$ROOT/colors.toml")" "${want[$k]}" "$k"
  done
  grep -qE '^hyprland_active_border.*rgba\(cc3a40ee\).*rgba\(b3232cee\).*rgba\(f2c272ee\)' "$ROOT/colors.toml" ||
    die "active border is no longer the crimson-to-gold uniform gradient"
}

test_icon_theme_is_yaru_red() {
  assert_eq "$(tr -d '[:space:]' < "$ROOT/icons.theme")" "Yaru-red-dark"
}

test_theme_root_has_nothing_omarchy_would_strip() {
  local f
  for f in "$ROOT"/*.lua "$ROOT"/{alacritty.toml,foot.ini,ghostty.conf,kitty.conf,vscode.json}; do
    [[ -e $f ]] && die "$(basename "$f") would be dropped by 'omarchy theme install'; generate it from colors.toml instead"
  done
  return 0
}

test_backgrounds_are_only_the_eight_originals_at_4k() {
  local want="1-seize-the-time.webp
2-things-are-only-impossible-until-they-are-not.webp
3-we-work-to-better-ourselves.webp
4-make-it-so.webp
5-lets-see-whats-out-there.webp
6-ten-forward.webp
7-tea-earl-grey-hot.webp
8-the-skys-the-limit.webp"
  # Guard against shipping the downloaded (copyrighted) screencaps by mistake.
  assert_eq "$(ls "$ROOT/backgrounds")" "$want" "backgrounds/ must hold only the generated originals"
  need magick
  local f
  for f in "$ROOT"/backgrounds/*; do
    assert_eq "$(magick identify -format '%wx%h' "$f")" "3840x2160" "$(basename "$f")"
  done
}

test_generator_writes_the_shipped_background_names() {
  local f
  for f in "$ROOT"/backgrounds/*; do
    grep -qF "\"$(basename "$f")\"" "$ROOT/tools/make_bgs.py" || die "$(basename "$f") is not produced by tools/make_bgs.py"
  done
}

test_dedication_is_in_place() {
  local phrase
  for phrase in "In honor of" "Patrick Stewart" "Gene Roddenberry" "better future for all humanity" \
                "Neither man nor anyone connected to Star Trek has endorsed it"; do
    grep -qF "$phrase" "$ROOT/README.md" || die "README.md lost its dedication: '$phrase'"
  done
}

test_unlock_art_is_ready_for_plymouth() {
  need magick
  assert_eq "$(magick identify -format '%wx%h' "$ROOT/unlock.png")" "800x188" "unlock.png size"
  assert_eq "$(magick identify -format '%[opaque]' "$ROOT/unlock.png")" "False" "unlock.png must be transparent"
  assert_eq "$(magick identify -format '%wx%h' "$ROOT/preview-unlock.png")" "1920x1080" "preview-unlock.png size"
}

test_hand_tuned_app_files_have_every_key() {
  local tpl=/usr/share/omarchy/default/themed f k
  [[ -d $tpl ]] || skip "needs Omarchy's templates to compare against"
  for f in btop.theme shell.toml; do
    for k in $(grep -oE '^(theme\[[a-z_0-9]+\]|[a-z-]+)[[:space:]]*=' "$tpl/$f.tpl" | sed -E 's/[[:space:]]*=$//' | sort -u); do
      grep -qE "^$(printf '%s' "$k" | sed 's/[][]/\\&/g')[[:space:]]*=" "$ROOT/$f" || die "$f is missing $k (Omarchy's template has it)"
    done
  done
}

test_hand_tuned_app_files_keep_their_character() {
  assert_eq "$(tr -d '[:space:]' < "$ROOT/keyboard.rgb")" "#b3232c" "keyboard lights in uniform crimson"
  grep -qx 'theme\[title\]="#e2b25a"' "$ROOT/btop.theme" || die "btop titles should be pip gold"
  grep -qx 'theme\[cpu_end\]="#e8666e"' "$ROOT/btop.theme" || die "btop CPU should heat to crimson"
  ! grep -q '{{' "$ROOT/btop.theme" "$ROOT/shell.toml" || die "unrendered template placeholders"
  py "$ROOT/shell.toml" <<'PY' || exit 1
import re, sys
s = open(sys.argv[1]).read()
def get(sect, key):
    m = re.search(r'(?ms)^\[' + re.escape(sect) + r'\]\n(.*?)(?=^\[|\Z)', s)
    v = re.search(r'(?m)^' + re.escape(key) + r'\s*=\s*"([^"]*)"', m.group(1))
    return v.group(1) if v else None
want = {("bar", "active"): "#e8666e", ("notifications", "countdown"): "#e2b25a",
        ("polkit", "accent"): "#e2b25a", ("image-picker", "selected-border"): "#e2b25a",
        ("menu", "selected-text"): "#e8666e"}
bad = [f"[{a}] {b} = {get(a, b)} (want {v})" for (a, b), v in want.items() if get(a, b) != v]
if bad: print("    shell.toml drifted: " + "; ".join(bad)); sys.exit(1)
PY
}

test_fan_work_disclaimers_are_in_place() {
  local phrase
  for phrase in "Unofficial fan work" "not affiliated with" "CBS Studios Inc." "Paramount" \
                "trademarks of" "No endorsement" "Simple Icons" "non-commercial"; do
    grep -qiF "$phrase" "$ROOT/README.md" || die "README.md lost its disclaimer: '$phrase'"
  done
  grep -qF "Copyright (c) 2026 wiseyoungbuck" "$ROOT/LICENSE" || die "LICENSE lost its copyright line"
  grep -qF "grants no rights" "$ROOT/LICENSE" || die "LICENSE lost its third-party carve-out"
}

test_repo_ships_no_third_party_media() {
  # Only generated art: no stills, screencaps or ripped audio anywhere in the tree.
  local found
  found=$(cd "$ROOT" && git ls-files --cached --others --exclude-standard 2>/dev/null |
          grep -iE '\.(jpe?g|gif|png|webp|bmp|tiff?|mp3|ogg|opus|wav|m4a|flac|mp4|mkv|webm)$' |
          grep -vxE '(preview|preview-unlock|unlock)\.png|backgrounds/[1-8]-[a-z-]+\.webp|extras/share/engine-hum\.flac' || true)
  [[ -z $found ]] || die "unexpected media in the repo: $found"
}

test_notification_icon_is_the_same_delta() {
  local qml_path svg_path
  qml_path=$(sed -nE 's/.*PathSvg \{ path: "([^"]*)" \}.*/\1/p' "$QML")
  svg_path=$(sed -nE 's/.*<path fill="[^"]*" d="([^"]*)".*/\1/p' "$ROOT/extras/share/delta.svg")
  assert_eq "$svg_path" "$qml_path" "notification icon and bar icon must be the same outline"
  grep -qF -- '-i "$icon"' "$HUM" || die "notifications must carry the delta icon"
}

# ------------------------------------------------------------ engine-hum: unit

test_scripts_parse() {
  local f
  for f in "$HUM" "$ROOT"/extras/*.sh "$ROOT"/extras/hooks/post-boot.d/* "$ROOT"/tests/run.sh; do
    bash -n "$f" || die "syntax error in $f"
  done
}

test_scripts_are_executable() {
  local f
  for f in "$HUM" "$ROOT"/extras/*.sh "$ROOT"/extras/hooks/post-boot.d/*; do
    [[ -x $f ]] || die "$f is not executable"
  done
}

test_hum_rejects_unknown_commands() {
  local out code=0
  out=$(ENGINE_HUM_TAG="mis-test-$$" "$HUM" bogus 2>&1) || code=$?
  assert_eq "$code" 2 "exit code"
  [[ $out == usage:* ]] || die "no usage message: $out"
}

test_hum_status_reports_off_as_inactive_json() {
  need jq
  local out
  out=$(ENGINE_HUM_TAG="mis-test-$$" "$HUM" status)
  jq -e '.text and .tooltip and (.class == null)' <<<"$out" >/dev/null || die "bad off status: $out"
}

test_hum_title_match_is_exact() {
  # A player titled engine-hum-something must not count as the hum.
  grep -qF -- '--title=$TAG( |$)' "$HUM" || die "engine-hum must anchor its title match"
  grep -qF -- '--title=engine-hum( |$)' "$QML" || die "the bar icon must anchor its title match"
}

test_hum_volume_defaults_saves_and_clamps() {
  export ENGINE_HUM_TAG="mis-test-$$" ENGINE_HUM_STATE="$WORK/vol/state"
  unset ENGINE_HUM_VOLUME
  assert_eq "$("$HUM" volume)" 75 "default volume"
  assert_eq "$("$HUM" volume 40)" 40
  assert_eq "$("$HUM" volume)" 40 "volume is remembered"
  assert_eq "$(cat "$ENGINE_HUM_STATE")" 40 "saved to the state file"
  assert_eq "$("$HUM" volume 250)" 100 "clamped to 100"
  assert_eq "$("$HUM" volume 08)" 8 "leading zeros are decimal"
  local code=0; "$HUM" volume loud >/dev/null 2>&1 || code=$?
  assert_eq "$code" 2 "non-numbers rejected"
  assert_eq "$("$HUM" volume)" 8 "a rejected value changes nothing"
}

# ----------------------------------------------------- engine-hum: integration

hum_env() {
  export ENGINE_HUM_TAG="mis-test-$$" ENGINE_HUM_VOLUME=0 ENGINE_HUM_QUIET=1 \
         ENGINE_HUM_SOCK="$WORK/hum.sock" ENGINE_HUM_RESUME_AFTER=1 \
         ENGINE_HUM_SOUND="$ROOT/extras/share/engine-hum.flac" \
         ENGINE_HUM_STATE="$WORK/state-$BASHPID/volume"   # never the user's saved volume
}
hum_live() {
  need mpv socat busctl jq pactl
  busctl --user list >/dev/null 2>&1 || skip "no user D-Bus session"
  pactl info >/dev/null 2>&1 || skip "no audio server"
  hum_env
  trap 'pkill -KILL -f "^mpv .*--title=$ENGINE_HUM_TAG( |\$)" 2>/dev/null || true' EXIT   # no hum outlives its test
}
hum_pid()    { pgrep -f "^mpv .*--title=$ENGINE_HUM_TAG( |$)"; }
hum_count()  { pgrep -fc "^mpv .*--title=$ENGINE_HUM_TAG( |$)"; }
hum_paused() { [[ $(echo '{"command":["get_property","pause"]}' | socat - "UNIX-CONNECT:$ENGINE_HUM_SOCK" 2>/dev/null | jq -r .data) == true ]]; }
hum_playing(){ [[ $(echo '{"command":["get_property","pause"]}' | socat - "UNIX-CONNECT:$ENGINE_HUM_SOCK" 2>/dev/null | jq -r .data) == false ]]; }
hum_off()    { "$HUM" off >/dev/null 2>&1; eventually 5 bash -c "! pgrep -f '^mpv .*--title=$ENGINE_HUM_TAG( |\$)' >/dev/null"; }

test_hum_on_off_and_toggle() {
  hum_live
  "$HUM" on
  eventually 5 hum_playing || die "hum did not start playing"
  jq -e '.class == "active"' <<<"$("$HUM" status)" >/dev/null || die "status not active while on"
  "$HUM" on; sleep 0.5
  assert_eq "$(hum_count)" 1 "a second 'on' must not start another player"
  "$HUM" toggle
  eventually 5 bash -c "! pgrep -f '^mpv .*--title=$ENGINE_HUM_TAG( |\$)' >/dev/null" || die "toggle did not stop it"
  "$HUM" toggle
  eventually 5 hum_playing || die "toggle did not start it again"
  hum_off || die "off did not stop it"
}

test_hum_volume_applies_live_and_at_start() {
  hum_live
  export ENGINE_HUM_STATE="$WORK/vol-live/state" ENGINE_HUM_VOLUME=0
  "$HUM" volume 30 >/dev/null
  "$HUM" on; eventually 5 hum_playing || die "hum did not start"
  vol() { echo '{"command":["get_property","volume"]}' | socat - "UNIX-CONNECT:$ENGINE_HUM_SOCK" | jq -r '.data | floor'; }
  assert_eq "$(vol)" 30 "starts at the saved volume"
  "$HUM" volume 55 >/dev/null
  assert_eq "$(vol)" 55 "changes while playing"
  hum_off
}

test_hum_is_invisible_to_media_players() {
  hum_live
  "$HUM" on; eventually 5 hum_playing || die "hum did not start"
  local pid; pid=$(hum_pid)
  sleep 1
  if busctl --user list --no-legend | awk -v p="$pid" '$1 ~ /^org\.mpris\.MediaPlayer2\./ && $2 == p' | grep -q .; then
    hum_off; die "the hum registered itself as an MPRIS media player"
  fi
  hum_off
}

test_hum_ignores_sound_effects() {
  hum_live
  "$HUM" on; eventually 5 hum_playing || die "hum did not start"
  # A short stream that is not a media player: like a notification or UI sound.
  mpv --no-video --really-quiet --load-scripts=no --volume=0 --title="mis-test-$$-fx" "av://lavfi:sine=d=3" &
  local fx=$!
  sleep 2.5
  hum_playing || { kill $fx 2>/dev/null; hum_off; die "hum paused for a sound effect"; }
  wait $fx 2>/dev/null
  hum_off
}

test_hum_pauses_for_music_and_resumes_after() {
  hum_live
  [[ -e /etc/mpv/scripts/mpris.so || -e $HOME/.config/mpv/scripts/mpris.so ]] || skip "needs mpv-mpris to stand in for a music player"
  export ENGINE_HUM_RESUME_AFTER=3
  "$HUM" on; eventually 5 hum_playing || die "hum did not start"
  # A media player playing (silently): mpv with mpv-mpris loaded.
  mpv --no-video --really-quiet --volume=0 --title="mis-test-$$-music" "av://lavfi:sine=d=5" &
  local music=$!
  eventually 4 hum_paused || { kill $music 2>/dev/null; hum_off; die "hum kept playing over music"; }
  wait $music 2>/dev/null
  sleep 1
  hum_paused || { hum_off; die "hum came back the moment the music stopped, not after a quiet spell"; }
  eventually 8 hum_playing || { hum_off; die "hum did not resume after the music stopped"; }
  hum_off
}

# Watchers bound to a given player (engine-hum watch <mpv-pid>).
watchers_for() { pgrep -fc "^bash $HUM watch $1\$" || true; }

test_hum_watcher_exits_with_the_hum() {
  hum_live
  "$HUM" on; eventually 5 hum_playing || die "hum did not start"
  local pid; pid=$(hum_pid)
  one_watcher() { [[ $(watchers_for "$pid") == 1 ]]; }
  no_watcher()  { [[ $(watchers_for "$pid") == 0 ]]; }
  eventually 3 one_watcher || die "no watcher bound to the player"
  hum_off
  eventually 4 no_watcher || die "watcher outlived the hum"
}

test_hum_quick_off_on_leaves_exactly_one_watcher() {
  hum_live
  local i; for i in 1 2 3; do "$HUM" on; "$HUM" off >/dev/null; done
  "$HUM" on; eventually 5 hum_playing || die "hum did not start"
  assert_eq "$(hum_count)" 1 "players after a quick off/on"
  sleep 2.5   # long enough for stale watchers to notice their player is gone
  assert_eq "$(watchers_for "$(hum_pid)")" 1 "watchers for the running hum"
  local stale=0 w
  while read -r w; do kill -0 "${w##* }" 2>/dev/null || stale=$((stale + 1)); done < <(pgrep -fa "^bash $HUM watch [0-9]+$")
  assert_eq "$stale" 0 "watchers left behind for players that are gone"
  hum_off
}

# ---------------------------------------------------------------- login hooks

fake_home() {
  export HOME="$WORK/home-$1"
  mkdir -p "$HOME/.local/state/omarchy/current" "$HOME/.local/bin" "$WORK/stubs-$1"
  echo "$2" > "$HOME/.local/state/omarchy/current/theme.name"
  # omarchy stub: record calls instead of changing the wallpaper.
  printf '#!/bin/sh\necho "$*" >> "%s/calls"\n' "$WORK/stubs-$1" > "$WORK/stubs-$1/omarchy"
  printf '#!/bin/sh\necho "engine-hum $*" >> "%s/calls"\n' "$WORK/stubs-$1" > "$HOME/.local/bin/engine-hum"
  chmod +x "$WORK/stubs-$1/omarchy" "$HOME/.local/bin/engine-hum"
  export PATH="$WORK/stubs-$1:$PATH" CALLS="$WORK/stubs-$1/calls"
  : > "$CALLS"
}

test_random_wallpaper_hook_picks_from_both_folders() {
  fake_home rbg make-it-so
  local hook="$ROOT/extras/hooks/post-boot.d/make-it-so-random-bg"
  mkdir -p "$HOME/.config/omarchy/themes/make-it-so/backgrounds" "$HOME/.config/omarchy/backgrounds/make-it-so"
  touch "$HOME/.config/omarchy/themes/make-it-so/backgrounds/"{a.webp,b.webp} \
        "$HOME/.config/omarchy/backgrounds/make-it-so/"{c.jpg,d.png} \
        "$HOME/.config/omarchy/backgrounds/make-it-so/notes.txt"
  local i; for i in $(seq 40); do "$hook"; done
  assert_eq "$(wc -l < "$CALLS")" 40 "one wallpaper set per login"
  ! grep -v '^theme bg set ' "$CALLS" | grep -q . || die "unexpected call: $(grep -v '^theme bg set ' "$CALLS" | head -1)"
  ! grep -q 'notes.txt' "$CALLS" || die "picked a non-image file"
  local distinct; distinct=$(sort -u "$CALLS" | wc -l)
  (( distinct >= 3 )) || die "only $distinct distinct wallpapers in 40 logins; not random"
  grep -q '/themes/make-it-so/' "$CALLS" && grep -q '/backgrounds/make-it-so/' "$CALLS" || die "did not draw from both folders"
}

test_random_wallpaper_hook_leaves_other_themes_alone() {
  fake_home rbg2 tokyo-night
  mkdir -p "$HOME/.config/omarchy/backgrounds/make-it-so"; touch "$HOME/.config/omarchy/backgrounds/make-it-so/a.jpg"
  "$ROOT/extras/hooks/post-boot.d/make-it-so-random-bg"
  [[ ! -s $CALLS ]] || die "changed the wallpaper under another theme: $(cat "$CALLS")"
}

test_login_hum_hook_engages_only_under_this_theme() {
  fake_home hum1 make-it-so
  "$ROOT/extras/hooks/post-boot.d/make-it-so-engine-hum"
  assert_eq "$(cat "$CALLS")" "engine-hum on"
  fake_home hum2 catppuccin
  "$ROOT/extras/hooks/post-boot.d/make-it-so-engine-hum"
  [[ ! -s $CALLS ]] || die "started the hum under another theme"
}

# ------------------------------------------------------------------ bar icon

delta_path() { sed -nE 's/.*PathSvg \{ path: "([^"]*)" \}.*/\1/p' "$QML"; }

test_bar_icon_renders_like_a_glyph() {
  grep -q 'preferredRendererType: Shape.CurveRenderer' "$QML" || die "the delta must use the curve renderer (smooth at fractional scale)"
  ! awk '/component Delta/,0' "$QML" | grep -q 'layer.enabled' || die "the delta must not render through a layer (it goes rough at 1.33x)"
  grep -q 'iconComponent' "$QML" && grep -q 'BarIconButton' "$QML" || die "the icon must go through BarIconButton like Omarchy's own"
}

test_bar_icon_is_one_colour_and_dims_when_off() {
  local n; n=$(grep -c 'fillColor:' "$QML")
  assert_eq "$n" 1 "one filled shape"
  grep -q 'color: root.running ? root.fg : Qt.darker(root.fg, 1.55)' "$QML" || die "on/off colours changed"
  ! grep -qiE 'strokeColor: [^t]|#e2b25a|#e8666e' "$QML" || die "the icon picked up extra colours"
}

test_bar_icon_is_the_tng_delta_without_the_ring() {
  [[ -n $(delta_path) ]] || die "no PathSvg found"
  py "$(delta_path)" <<'EOF' || exit 1
import re, sys
nums = [float(n) for n in re.findall(r'-?\d+(?:\.\d+)?', sys.argv[1])]
cmds = re.findall(r'[A-Za-z]', sys.argv[1])
if set(cmds) - set("MLCQZ"): print("    unexpected path commands", set(cmds)); sys.exit(1)
if cmds.count("M") != 1: print("    the delta must be a single closed outline (no ring)"); sys.exit(1)
pts = list(zip(nums[0::2], nums[1::2]))
xs, ys = [p[0] for p in pts], [p[1] for p in pts]
w, h = max(xs) - min(xs), max(ys) - min(ys)
def check(ok, msg):
    if not ok: print("    " + msg); sys.exit(1)
check(abs(h - 24) < 0.5 and abs(min(ys)) < 0.2, f"delta must fill the 24-unit height (got {h:.2f})")
check(0.6 < w / h < 0.7, f"delta proportions drifted: {w/h:.3f} (TNG delta is ~0.65)")
apex = min(pts, key=lambda p: p[1])
check(abs(apex[0] - (min(xs) + w / 2)) < 0.6, "the crown must stand upright over the centre, not lean")
# The notch: the highest point of the bottom cut-out, i.e. the topmost point
# below mid-height that sits between the two bottom tips.
tips = sorted([p for p in pts if p[1] > 23], key=lambda p: p[0])
lo, hi = tips[0][0], tips[-1][0]
inner = [p for p in pts if p[1] > 12 and lo + 1 < p[0] < hi - 1]
peak = min(inner, key=lambda p: p[1])
check(peak[0] > min(xs) + w * 0.55, f"the notch must peak right of centre like the real emblem (at {peak[0]:.2f} of {w:.2f})")
check(13 < peak[1] < 16.5, f"the notch must cut about 40% up into the delta (peak at y={peak[1]:.2f})")
EOF
}

test_bar_controls_click_scroll_and_panel() {
  grep -q '^Panel {' "$QML" || die "the widget must be an Omarchy Panel (popup lifecycle)"
  grep -q 'if (code === Qt.RightButton) root.toggleHum()' "$QML" || die "right click must toggle the hum"
  grep -q 'else if (code === Qt.LeftButton) { root.refresh(); root.toggle() }' "$QML" || die "left click must open the panel"
  grep -q 'onWheelMoved: function(delta) { root.setVolume(root.volume + (delta > 0 ? 5 : -5)) }' "$QML" || die "scroll must step the volume by 5"
  grep -q 'PanelSlider' "$QML" && grep -q 'minimum: 0; maximum: 100' "$QML" || die "panel needs a 0-100 volume slider"
  grep -q 'ToggleSwitch' "$QML" || die "panel needs the on/off switch"
  grep -q 'command: \[root.script, "volume", String(target)\]' "$QML" || die "slider must set volume through engine-hum"
  grep -q 'ipcTarget: "engine-hum"' "$QML" || die "panel must answer omarchy-shell engine-hum open/close/toggle"
}

test_bar_icon_box_matches_its_artwork() {
  # Omarchy fits icons by their item bounds; a mismatched box shrinks or pads the glyph.
  grep -q 'width: iconSize \* 15.6 / 24' "$QML" || die "Delta item width no longer matches the path's 15.6x24 bounds"
  grep -q 'scale: Qt.size(d.height / 24, d.height / 24)' "$QML" || die "path scale must be uniform"
}

# ----------------------------------------------------------------- installer

install_home() {
  export HOME="$WORK/inst-$1" MAKE_IT_SO_NO_RELOAD=1
  # uninstall.sh runs `engine-hum off`; aim it at a test name so it can never
  # stop the real hum playing on this machine.
  export ENGINE_HUM_TAG="mis-test-$$-inst"
  mkdir -p "$HOME/.config/hypr" "$HOME/.config/omarchy"
  printf -- '-- user bindings\no.bind("SUPER + RETURN", "Terminal", "ghostty")\n' > "$HOME/.config/hypr/bindings.lua"
  cat > "$HOME/.config/omarchy/shell.json" <<'EOF'
{ "bar": { "layout": { "left": [{"id":"omarchy.menu"}],
  "right": [{"id":"omarchy.tray"},{"id":"omarchy.audio"},{"id":"aristoi.monitor"}] } },
  "idle": {"lock": 1800}, "version": 1 }
EOF
}

test_installer_puts_everything_in_place_once() {
  need jq mpv socat busctl
  install_home a
  "$ROOT/extras/install.sh" >/dev/null || die "install failed"
  "$ROOT/extras/install.sh" >/dev/null || die "second install failed"
  local f
  for f in .local/bin/engine-hum .config/omarchy/hooks/post-boot.d/make-it-so-random-bg \
           .config/omarchy/hooks/post-boot.d/make-it-so-engine-hum; do
    [[ -x $HOME/$f ]] || die "$f missing or not executable"
  done
  cmp -s "$ROOT/extras/share/engine-hum.flac" "$HOME/.local/share/make-it-so/engine-hum.flac" || die "sound not installed"
  cmp -s "$QML" "$HOME/.config/omarchy/bar/modules/engine-hum.qml" || die "bar icon not installed"
  cmp -s "$ROOT/extras/share/delta.svg" "$HOME/.local/share/make-it-so/delta.svg" || die "notification icon not installed"
  assert_eq "$(grep -c 'engine-hum toggle' "$HOME/.config/hypr/bindings.lua")" 1 "keybinding lines"
  grep -q 'SUPER + ALT + E' "$HOME/.config/hypr/bindings.lua" || die "wrong key"
  grep -q 'SUPER + RETURN' "$HOME/.config/hypr/bindings.lua" || die "clobbered existing bindings"
  assert_eq "$(jq -c '[.bar.layout.right[].id]' "$HOME/.config/omarchy/shell.json")" \
            '["omarchy.tray","omarchy.audio","engine-hum","aristoi.monitor"]' "bar order"
  assert_eq "$(jq -c '.bar.layout.right[] | select(.id=="engine-hum")' "$HOME/.config/omarchy/shell.json")" \
            '{"id":"engine-hum","type":"qml"}'
  assert_eq "$(jq -c '.idle' "$HOME/.config/omarchy/shell.json")" '{"lock":1800}' "other settings kept"
}

test_installer_appends_to_the_bar_when_there_is_no_audio_widget() {
  need jq mpv socat busctl
  install_home b
  jq '.bar.layout.right = [{"id":"omarchy.tray"}]' "$HOME/.config/omarchy/shell.json" > "$WORK/s" && mv "$WORK/s" "$HOME/.config/omarchy/shell.json"
  "$ROOT/extras/install.sh" >/dev/null || die "install failed"
  assert_eq "$(jq -c '[.bar.layout.right[].id]' "$HOME/.config/omarchy/shell.json")" '["omarchy.tray","engine-hum"]'
}

test_uninstaller_removes_exactly_what_was_added() {
  need jq mpv socat busctl
  install_home c
  cp "$HOME/.config/hypr/bindings.lua" "$WORK/bindings.orig"
  jq -S . "$HOME/.config/omarchy/shell.json" > "$WORK/shell.orig"
  "$ROOT/extras/install.sh" >/dev/null && "$ROOT/extras/uninstall.sh" >/dev/null || die "install/uninstall failed"
  [[ ! -e $HOME/.local/bin/engine-hum && ! -e $HOME/.local/share/make-it-so && ! -e $HOME/.config/omarchy/bar/modules/engine-hum.qml ]] ||
    die "files left behind"
  ls "$HOME/.config/omarchy/hooks/post-boot.d/" 2>/dev/null | grep -q make-it-so && die "hooks left behind"
  diff <(grep -v '^$' "$WORK/bindings.orig") <(grep -v '^$' "$HOME/.config/hypr/bindings.lua") >/dev/null || die "bindings.lua not restored"
  diff "$WORK/shell.orig" <(jq -S . "$HOME/.config/omarchy/shell.json") >/dev/null || die "shell.json not restored"
}

test_suite_never_touches_the_real_hum() {
  # Every place the tests run engine-hum must carry a test tag.
  grep -q 'export ENGINE_HUM_TAG="mis-test-$$-inst"' "$ROOT/tests/run.sh" || die "installer tests must use a test tag"
  grep -qE 'export ENGINE_HUM_TAG="mis-test-\$\$"' "$ROOT/tests/run.sh" || die "hum tests must use a test tag"
}

test_installer_switches_the_bar_icon() {
  need jq mpv socat busctl
  install_home d
  "$ROOT/extras/install.sh" --plain-icon >/dev/null || die "install --plain-icon failed"
  assert_eq "$(jq -c '.bar.layout.right[] | select(.id=="engine-hum")' "$HOME/.config/omarchy/shell.json")" \
            '{"id":"engine-hum","type":"qml","icon":"plain"}'
  "$ROOT/extras/install.sh" >/dev/null
  assert_eq "$(jq -r '.bar.layout.right[] | select(.id=="engine-hum") | .icon' "$HOME/.config/omarchy/shell.json")" plain \
            "a plain re-install keeps the chosen icon"
  "$ROOT/extras/install.sh" --delta-icon >/dev/null
  assert_eq "$(jq -c '.bar.layout.right[] | select(.id=="engine-hum")' "$HOME/.config/omarchy/shell.json")" \
            '{"id":"engine-hum","type":"qml"}'
  local code=0; "$ROOT/extras/install.sh" --bogus >/dev/null 2>&1 || code=$?
  assert_eq "$code" 2 "unknown options rejected"
}

test_bar_icon_has_a_plain_fallback() {
  grep -q 'readonly property bool plainIcon: setting("icon", "delta") === "plain"' "$QML" || die "no icon setting"
  grep -q 'iconComponent: root.plainIcon ? null : barDelta' "$QML" || die "bar does not switch to the glyph"
  grep -q 'iconComponent: root.plainIcon ? heroGlyph : heroDelta' "$QML" || die "panel does not switch to the glyph"
}

# ------------------------------------------- optional: this machine vs. repo

test_installed_copies_match_the_repo() {
  [[ ${MAKE_IT_SO_CHECK_INSTALLED:-0} == 1 ]] || skip "set MAKE_IT_SO_CHECK_INSTALLED=1"
  local pair
  for pair in "$HUM:.local/bin/engine-hum" "$QML:.config/omarchy/bar/modules/engine-hum.qml" \
              "$ROOT/extras/share/engine-hum.flac:.local/share/make-it-so/engine-hum.flac" \
              "$ROOT/extras/hooks/post-boot.d/make-it-so-random-bg:.config/omarchy/hooks/post-boot.d/make-it-so-random-bg" \
              "$ROOT/extras/hooks/post-boot.d/make-it-so-engine-hum:.config/omarchy/hooks/post-boot.d/make-it-so-engine-hum" \
              "$ROOT/colors.toml:.config/omarchy/themes/make-it-so/colors.toml"; do
    cmp -s "${pair%%:*}" "$HOME/${pair#*:}" || die "~/${pair#*:} differs from the repo"
  done
}

# -------------------------------------------------------------------- runner

filter="${1:-}"
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  [[ -n $filter && $t != *"$filter"* ]] && continue
  printf '%-70s' "${t#test_}"
  out=$( (set -e; "$t") 2>&1 ); code=$?
  case $code in
    0)  echo "ok"; pass=$((pass + 1)) ;;
    77) echo "skip"; skip=$((skip + 1)); [[ -n $out ]] && echo "$out" ;;
    *)  echo "FAIL"; fail=$((fail + 1)); failed+=("$t"); [[ -n $out ]] && echo "$out" ;;
  esac
done
echo
echo "$pass passed, $fail failed, $skip skipped"
(( fail == 0 ))
