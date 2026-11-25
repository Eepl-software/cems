#!/usr/bin/env bash
# Runs vkQuake's `timedemo` on the JSNOW CPU Vulkan driver and prints the result line.
#
#   tools/vkquake_timedemo.sh <game-dir> <width> <height> [normal|fast] [demo]
#
# <game-dir> holds the vkQuake binary as ./vkq and the game data as ./id1 (LibreQuake
# works: see PROGRESS.md, Phase F). "fast" = vkQuake's own `r_scale 2` (3D view rendered
# at half resolution and upscaled by its compute shader; HUD stays at full resolution).
# Needs an X server in $DISPLAY (Xvfb works). Driver stats are written to <log>.
set -u
GAME=$1; W=$2; H=$3; MODE=${4:-normal}; DEMO=${5:-demo1}
ICD=$(cd "$(dirname "$0")/.." && pwd)/build/jsnow_icd.json
LOG=${LOG:-/tmp/vkq_timedemo_${W}x${H}_${MODE}.log}
SCALE=1; [ "$MODE" = fast ] && SCALE=2
cd "$GAME" || exit 1
VK_DRIVER_FILES="$ICD" JSNOW_ICD_STATS=1 stdbuf -oL -eL ./vkq -basedir . -width "$W" -height "$H" -window -nosound \
  +r_scale "$SCALE" +timedemo "$DEMO" > "$LOG" 2>&1 &
PID=$!
# The demo loop continues after timedemo prints its result: stop vkQuake there.
for _ in $(seq 1 7200); do
  if grep -q " fps$" "$LOG" 2>/dev/null; then break; fi
  kill -0 $PID 2>/dev/null || break
  sleep 1
done
kill $PID 2>/dev/null; wait $PID 2>/dev/null
RES=$(grep -m1 " fps$" "$LOG")
echo "${W}x${H} $MODE: ${RES:-no result (see $LOG)}"
