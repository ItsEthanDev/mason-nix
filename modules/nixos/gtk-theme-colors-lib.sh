# Shared GTK3 theme color helpers for Conky, Kitty, etc.
theme_name() {
  if command -v xfconf-query >/dev/null 2>&1; then
    xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null && return 0
  fi
  if command -v gsettings >/dev/null 2>&1; then
    gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'"
    return 0
  fi
  return 1
}

find_gtk_css() {
  theme=$1
  for dir in ${XDG_DATA_DIRS:-/usr/share:/usr/local/share}; do
    css="$dir/themes/$theme/gtk-3.0/gtk.css"
    if [ -f "$css" ]; then
      printf '%s\n' "$css"
      return 0
    fi
  done
  if [ -f "/run/current-system/sw/share/themes/$theme/gtk-3.0/gtk.css" ]; then
    printf '%s\n' "/run/current-system/sw/share/themes/$theme/gtk-3.0/gtk.css"
    return 0
  fi
  return 1
}

gtk_color() {
  css=$1
  name=$2
  line=$(grep -m1 "@define-color[[:space:]]\+$name[[:space:]]" "$css" 2>/dev/null || true)
  if [ -z "$line" ]; then
    return 1
  fi
  hex=$(printf '%s\n' "$line" | sed -n 's/.*#\([0-9A-Fa-f]\{6\}\).*/\1/p' | head -n1)
  if [ -n "$hex" ]; then
    printf '#%s\n' "$(printf '%s' "$hex" | tr '[:upper:]' '[:lower:]')"
    return 0
  fi
  ref=$(printf '%s\n' "$line" | sed -n "s/.*@define-color $name[[:space:]]*@\\([^ ;]*\\).*/\\1/p")
  if [ -n "$ref" ]; then
    gtk_color "$css" "$ref"
    return $?
  fi
  return 1
}

pick_color() {
  css=$1
  shift
  for name in "$@"; do
    if color=$(gtk_color "$css" "$name"); then
      printf '%s\n' "$color"
      return 0
    fi
  done
  return 1
}

is_black() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    "#000000" | "#000") return 0 ;;
    *) return 1 ;;
  esac
}

hex_luminance() {
  hex=$(printf '%s' "$1" | tr -d '#')
  [ "${#hex}" -ne 6 ] && return 1
  r=$(printf '%d' "0x$(printf '%s' "$hex" | cut -c1-2)")
  g=$(printf '%d' "0x$(printf '%s' "$hex" | cut -c3-4)")
  b=$(printf '%d' "0x$(printf '%s' "$hex" | cut -c5-6)")
  printf '%d' $(((r * 299 + g * 587 + b * 114) / 1000))
}

is_light_theme() {
  bg=$(pick_color "$1" bg_color theme_bg_color button_bg_color || true)
  if [ -z "$bg" ]; then
    return 0
  fi
  lum=$(hex_luminance "$bg") || return 0
  [ "$lum" -gt 128 ]
}

pick_palette_color() {
  css=$1
  skip_black=${2:-0}
  shift 2
  for name in "$@"; do
    if color=$(gtk_color "$css" "$name"); then
      if [ "$skip_black" -eq 1 ] && is_black "$color"; then
        continue
      fi
      printf '%s\n' "$color"
      return 0
    fi
  done
  return 1
}
