#!/usr/bin/env bash
# One-command JSNOW benchmark for Apple Silicon Macs (also works on any arm64/x86-64
# Linux or macOS box). Builds the renderer with the NEON path (-mcpu=native) and
# prints the same results tables as the Linux runs in PROGRESS.md / FINAL_REPORT.md.
#
#   cd jsnow && tools/bench_mac.sh            # full table (6 configs, 300 frames, 1080p)
#   tools/bench_mac.sh --quick                # baseline + --fast only, 120 frames
#
# Needs only the Xcode command line tools (clang++). No Homebrew, no CMake.
# The Vulkan driver (icd/) and vkQuake are Linux/X11-only and are not built here.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build-mac"
CXX=${CXX:-c++}
FRAMES=300
QUICK=0
for a in "$@"; do
  case "$a" in
    --quick) QUICK=1; FRAMES=120 ;;
    --frames=*) FRAMES=${a#--frames=} ;;
    *) echo "usage: $0 [--quick] [--frames=N]"; exit 1 ;;
  esac
done
mkdir -p "$OUT"

# ---- machine info
ARCH=$(uname -m)
if [ "$(uname -s)" = Darwin ]; then
  MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model)
  NCPU=$(sysctl -n hw.ncpu)
  PCORES=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "?")
  ECORES=$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || echo "0")
  MEM=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  echo "machine: $MODEL, $NCPU cores ($PCORES performance + $ECORES efficiency), ${MEM} GB, $ARCH"
else
  echo "machine: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //'), $(nproc) threads, $ARCH"
fi

# ---- build (NEON on arm64, AVX2 on x86-64)
FLAGS=(-std=c++20 -O3 -fno-math-errno -DNDEBUG -DJSNOW_HAVE_ZLIB=1)
case "$ARCH" in
  arm64|aarch64)
    if echo 'int main(){}' | "$CXX" -x c++ -mcpu=native -o /dev/null - 2>/dev/null; then FLAGS+=(-mcpu=native)
    elif echo 'int main(){}' | "$CXX" -x c++ -mcpu=apple-m1 -o /dev/null - 2>/dev/null; then FLAGS+=(-mcpu=apple-m1); fi ;;
  x86_64|amd64) FLAGS+=(-mavx2 -mfma -DJSNOW_HW_GATHER=1) ;;
esac
SRCS=(main engine texture shadow occlusion streaming scene raster post png)
echo "building: $CXX ${FLAGS[*]}"
FILES=(); for s in "${SRCS[@]}"; do FILES+=("$ROOT/src/$s.cpp"); done
"$CXX" "${FLAGS[@]}" "${FILES[@]}" -o "$OUT/jsnow" -lz -lpthread 2>"$OUT/build.log" || { cat "$OUT/build.log"; exit 1; }
cd "$OUT"

# ---- benchmark
if [ $QUICK = 1 ]; then
  echo; echo "== 1920x1080, baseline + --fast, $FRAMES frames"
  ./jsnow --bench-fast --quality --frames "$FRAMES" --png '' | tee "$OUT/bench_1080.txt"
else
  echo; echo "== 1920x1080, all configs, $FRAMES frames"
  ./jsnow --bench --quality --frames "$FRAMES" --png '' | tee "$OUT/bench_1080.txt"
  echo; echo "== 1280x720, baseline + --fast, $FRAMES frames"
  ./jsnow --bench-fast --quality --frames "$FRAMES" --size 1280x720 --png '' | tee "$OUT/bench_720.txt"
fi
echo
echo "Results saved in $OUT/. Paste the tables (and the machine line above) into PROGRESS.md."
