if [ "''${KITTY_FROM_WATCHER:-}" != 1 ] && command -v xfconf-query >/dev/null 2>&1; then
  watch_pid_file="''${XDG_RUNTIME_DIR:-/tmp}/kitty/theme-watch.pid"
  mkdir -p "$(dirname "$watch_pid_file")"

  if [ ! -f "$watch_pid_file" ] || ! kill -0 "$(cat "$watch_pid_file")" 2>/dev/null; then
    last_theme=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)
    (
      while sleep 3; do
        current=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)
        if [ -n "$current" ] && [ "$current" != "$last_theme" ]; then
          last_theme=$current
          for pid in $(pidof kitty 2>/dev/null || true); do
            kill -SIGUSR1 "$pid" 2>/dev/null || true
          done
        fi
      done
    ) &
    echo $! > "$watch_pid_file"
  fi
fi
