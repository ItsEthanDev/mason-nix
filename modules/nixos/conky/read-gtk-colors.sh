theme=$(theme_name 2>/dev/null || true)
css=""
if [ -n "$theme" ]; then
  css=$(find_gtk_css "$theme" 2>/dev/null || true)
fi

if [ -n "$css" ]; then
  if is_light_theme "$css"; then
    # Light themes: muted palette tones instead of pure black on the desktop.
    COLOR1=$(pick_palette_color "$css" 1 \
      disabled_fg_color dark_shadow wm_inactive_title wm_inactive_title_text \
      fg_color theme_fg_color text_color theme_text_color || true)
    COLOR3=$(pick_palette_color "$css" 0 \
      dark_shadow borders wm_inactive_title disabled_fg_color light_shadow || true)
  else
    # Dark themes: foreground and inactive palette tones.
    COLOR1=$(pick_palette_color "$css" 0 \
      fg_color theme_fg_color text_color theme_text_color \
      wm_inactive_title_text disabled_fg_color || true)
    COLOR3=$(pick_palette_color "$css" 0 \
      dark_shadow borders wm_inactive_title disabled_fg_color || true)
  fi

  COLOR2=$(pick_palette_color "$css" 0 \
    active_title_color wm_active_title selected_bg_color theme_selected_bg_color \
    active_title_text wm_active_title_text || true)

  COLOR_DEFAULT=$COLOR1
fi

COLOR_DEFAULT=${COLOR_DEFAULT:-#b1b1b1}
COLOR1=${COLOR1:-$COLOR_DEFAULT}
COLOR2=${COLOR2:-#888888}
COLOR3=${COLOR3:-#333333}

printf 'THEME_NAME=%q\n' "${theme:-unknown}"
printf 'COLOR_DEFAULT=%s\n' "$COLOR_DEFAULT"
printf 'COLOR1=%s\n' "$COLOR1"
printf 'COLOR2=%s\n' "$COLOR2"
printf 'COLOR3=%s\n' "$COLOR3"
