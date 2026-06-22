theme=$(theme_name 2>/dev/null || true)
css=""
if [ -n "$theme" ]; then
  css=$(find_gtk_css "$theme" 2>/dev/null || true)
fi

foreground=#000000
background=#c3c3c3
accent=#000082
accent_text=#ffffff
muted=#9c9c9c
shadow=#888888
highlight=#ffffff
inactive_tab_bg=#808080
inactive_tab_fg=#c0c0c0

if [ -n "$css" ]; then
  foreground=$(pick_color "$css" \
    fg_color theme_fg_color text_color theme_text_color || true)
  background=$(pick_color "$css" \
    base_color theme_base_color bg_color theme_bg_color || true)
  accent=$(pick_color "$css" \
    selected_bg_color theme_selected_bg_color active_title_color wm_active_title || true)
  accent_text=$(pick_color "$css" \
    selected_fg_color theme_selected_fg_color active_title_text wm_active_title_text || true)
  muted=$(pick_color "$css" \
    disabled_fg_color wm_inactive_title_text || true)
  shadow=$(pick_color "$css" \
    dark_shadow borders wm_inactive_title || true)
  highlight=$(pick_color "$css" \
    light_shadow selected_fg_color theme_selected_fg_color || true)
  inactive_tab_bg=$(pick_color "$css" \
    wm_inactive_title disabled_fg_color dark_shadow || true)
  inactive_tab_fg=$(pick_color "$css" \
    wm_inactive_title_text disabled_fg_color || true)
fi

foreground=${foreground:-#000000}
background=${background:-#c3c3c3}
accent=${accent:-#000082}
accent_text=${accent_text:-#ffffff}
muted=${muted:-#9c9c9c}
shadow=${shadow:-#888888}
highlight=${highlight:-#ffffff}
inactive_tab_bg=${inactive_tab_bg:-#808080}
inactive_tab_fg=${inactive_tab_fg:-#c0c0c0}

if [ -n "$css" ] && ! is_light_theme "$css"; then
  # Dark themes: swap surface/text and use brighter ANSI brights.
  color0=$foreground
  color1=#ff6b6b
  color2=#69db7c
  color3=#ffd43b
  color4=$accent
  color5=#da77f2
  color6=#66d9e8
  color7=$muted
  color8=$shadow
  color9=#ff8787
  color10=#8ce99a
  color11=#ffe066
  color12=$accent
  color13=#e599f7
  color14=#99e9f2
  color15=$highlight
else
  color0=$foreground
  color1=#800000
  color2=#008000
  color3=#808000
  color4=$accent
  color5=#800080
  color6=#008080
  color7=$muted
  color8=$shadow
  color9=#ff0000
  color10=#00ff00
  color11=#ffff00
  color12=$accent
  color13=#ff00ff
  color14=#00ffff
  color15=$highlight
fi

printf '# Auto-generated from GTK theme: %s\n' "${theme:-unknown}"
printf 'foreground %s\n' "$foreground"
printf 'background %s\n' "$background"
printf 'cursor %s\n' "$accent"
printf 'cursor_text_color %s\n' "$accent_text"
printf 'selection_foreground %s\n' "$accent_text"
printf 'selection_background %s\n' "$accent"
printf 'url_color %s\n' "$accent"
printf 'color0 %s\n' "$color0"
printf 'color1 %s\n' "$color1"
printf 'color2 %s\n' "$color2"
printf 'color3 %s\n' "$color3"
printf 'color4 %s\n' "$color4"
printf 'color5 %s\n' "$color5"
printf 'color6 %s\n' "$color6"
printf 'color7 %s\n' "$color7"
printf 'color8 %s\n' "$color8"
printf 'color9 %s\n' "$color9"
printf 'color10 %s\n' "$color10"
printf 'color11 %s\n' "$color11"
printf 'color12 %s\n' "$color12"
printf 'color13 %s\n' "$color13"
printf 'color14 %s\n' "$color14"
printf 'color15 %s\n' "$color15"
printf 'active_tab_foreground %s\n' "$accent_text"
printf 'active_tab_background %s\n' "$accent"
printf 'inactive_tab_foreground %s\n' "$inactive_tab_fg"
printf 'inactive_tab_background %s\n' "$inactive_tab_bg"
