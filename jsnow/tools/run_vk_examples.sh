#!/usr/bin/env bash
# Runs Sascha Willems' Vulkan examples on the JSNOW ICD and reports status / FPS /
# missing features. Usage: run_vk_examples.sh <examples-repo> <out-dir> <example>...
# Needs an X server (e.g. Xvfb :99) in $DISPLAY and the ICD built in jsnow/build.
set -u
REPO=$1; OUT=$2; shift 2
ICD=$(cd "$(dirname "$0")/.." && pwd)/build/jsnow_icd.json
mkdir -p "$OUT"
echo "| example | status | FPS | missing features hit |"
echo "|---|---|---:|---|"
for ex in "$@"; do
  bin="$REPO/build/bin/$ex"
  [ -x "$bin" ] || { echo "| $ex | not built | – | – |"; continue; }
  rm -f "$OUT/$ex.missing" "$OUT/$ex.csv" "$OUT/$ex.ppm"
  ( cd "$REPO" && VK_DRIVER_FILES="$ICD" JSNOW_ICD_MISSING_LOG="$OUT/$ex.missing" \
      JSNOW_ICD_DUMP="$OUT/$ex.ppm:10" timeout 90 "$bin" -b -bw 0 -br 4 -bf "$OUT/$ex.csv" -rp ./ \
      < /dev/null > "$OUT/$ex.log" 2>&1 )
  rc=$?
  fps=$(tail -n1 "$OUT/$ex.csv" 2>/dev/null | awk -F, '{print $5}')
  miss=$(sort -u "$OUT/$ex.missing" 2>/dev/null | tr '\n' ';' | sed 's/;$//; s/;/; /g')
  if [ -n "$fps" ]; then st="runs"; elif [ $rc -eq 124 ]; then st="timeout"; else st="fails (exit $rc)"; fi
  [ -s "$OUT/$ex.ppm" ] || st="$st, no frame presented"
  echo "| $ex | $st | ${fps:-–} | ${miss:-–} |"
done
