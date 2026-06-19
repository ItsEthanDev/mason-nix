#!/bin/sh
# Outputs a calendar for Conky ${execpi}: month and today in ${color2}, other days in ${color1}.
set -eu

today=$(date +%e | tr -d ' ')
month_line=$(
  cal | head -1 | sed 's/^/                    /' | tr '[:upper:]' '[:lower:]'
)

printf '${color2}%s${color1}\n' "$month_line"

cal | tail -n +2 | sed 's/^/                    /' | tr '[:upper:]' '[:lower:]' | while IFS= read -r line; do
  printf '%s\n' "$line" | sed -E \
    "s/(^|[[:space:]])(${today})([[:space:]]|$)/\\1\$\{color2\}\\2\$\{color1\}\\3/g"
done
