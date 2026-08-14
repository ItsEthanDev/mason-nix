#!/usr/bin/env bash
set -euo pipefail

property="_CRT_SHADER"

usage() {
  cat <<'EOF'
Usage:
  crt-wrap --select            Toggle the CRT shader on a clicked window
  crt-wrap --on                Enable it on a clicked window
  crt-wrap --off               Disable it on a clicked window
  crt-wrap COMMAND [ARG ...]   Launch and tag the first new application window
EOF
}

set_window_state() {
  local window=$1
  local state=$2

  case "$state" in
    on)
      xprop -id "$window" -f "$property" 32c -set "$property" 1 >/dev/null
      ;;
    off)
      xprop -id "$window" -remove "$property" >/dev/null 2>&1 || true
      ;;
    toggle)
      if xprop -id "$window" "$property" 2>/dev/null | grep -q '= 1'; then
        set_window_state "$window" off
      else
        set_window_state "$window" on
      fi
      ;;
  esac
}

select_window() {
  printf 'Click a window to change its CRT shader state.\n' >&2
  xdotool selectwindow
}

snapshot_windows() {
  xprop -root _NET_CLIENT_LIST 2>/dev/null |
    sed -n 's/^.*# //p' |
    tr ',' '\n' |
    tr -d ' '
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --select|--toggle)
    set_window_state "$(select_window)" toggle
    exit 0
    ;;
  --on)
    set_window_state "$(select_window)" on
    exit 0
    ;;
  --off)
    set_window_state "$(select_window)" off
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
esac

before="$(mktemp)"
after="$(mktemp)"
trap 'rm -f "$before" "$after"' EXIT
snapshot_windows >"$before"

"$@" &
command_pid=$!

# Applications may create their X11 window in a helper process or hand the
# request to an already-running instance. Detecting a newly managed client
# window is therefore more reliable than matching only _NET_WM_PID.
deadline=$((SECONDS + 15))
while (( SECONDS < deadline )); do
  snapshot_windows >"$after"
  window="$(
    comm -13 \
      <(sort -u "$before") \
      <(sort -u "$after") |
      while read -r candidate; do
        [ -n "$candidate" ] || continue
        type="$(xprop -id "$candidate" _NET_WM_WINDOW_TYPE 2>/dev/null || true)"
        if [[ "$type" == *"_NET_WM_WINDOW_TYPE_NORMAL"* ]] ||
           [[ "$type" == *"_NET_WM_WINDOW_TYPE_DIALOG"* ]]; then
          printf '%s\n' "$candidate"
          break
        fi
      done
  )"

  if [ -n "$window" ]; then
    set_window_state "$window" on
    printf 'CRT shader enabled on window %s.\n' "$window" >&2
    wait "$command_pid" 2>/dev/null || true
    exit 0
  fi

  # Keep watching briefly even if a single-instance launcher exits immediately.
  sleep 0.1
done

printf 'crt-wrap: no new application window appeared within 15 seconds.\n' >&2
printf 'Use "crt-wrap --on" and click the desired window instead.\n' >&2
wait "$command_pid" 2>/dev/null || true
exit 1
