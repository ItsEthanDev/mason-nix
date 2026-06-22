#!/bin/sh
# Outputs a calendar for Conky ${execpi}: month and today in ${color2}, other
# days in ${color1}. Centering is delegated to Conky's ${alignc} so it stays
# correct regardless of font metrics or locale (e.g. the double-width Japanese
# day-of-week headers produced by `cal` under ja_JP).
set -eu

today=$(date +%e | tr -d ' ')

month_line=$(cal | head -1 | tr '[:upper:]' '[:lower:]')
printf '${alignc}${color2}%s${color1}\n' "$month_line"

cal | tail -n +2 | tr '[:upper:]' '[:lower:]' | while IFS= read -r line; do
  highlighted=$(
    printf '%s' "$line" | sed -E \
      "s/(^|[[:space:]])(${today})([[:space:]]|$)/\\1\$\{color2\}\\2\$\{color1\}\\3/g"
  )
  printf '${alignc}%s\n' "$highlighted"
done
