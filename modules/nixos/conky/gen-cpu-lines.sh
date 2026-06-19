#!/bin/sh
set -eu

cpuLinesFile=$1
cores=$2

: > "$cpuLinesFile"
i=1
while [ "$i" -le "$cores" ]; do
  echo '${template1 \ Core\ '"$i"'}            ${template2}${cpu cpu'"$i"'}%                    ${template3}${cpubar cpu'"$i"'}' >> "$cpuLinesFile"
  i=$((i + 1))
done
