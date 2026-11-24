# JSNOW — CPU-only 3D renderer

An experiment in how fast pure-CPU rasterization can go. C++20, CMake, no GPU,
no window: frames are rendered into memory and one frame is saved as a PNG.

## Build & run

```sh
cmake -S . -B build && cmake --build build -j
./build/jsnow                      # baseline, 300 frames, saves frame 150 to jsnow.png
./build/jsnow --half               # trick 1: half resolution + 2x bilinear upscale
./build/jsnow --checker            # trick 2: 1/4 of the pixels per frame, rotating 2x2 pattern
./build/jsnow --reuse              # trick 3: reuse earlier frames via per-pixel motion vectors
./build/jsnow --all                # all three
./build/jsnow --bench --quality    # baseline, each trick, all tricks + PSNR vs baseline
```

Other flags: `--frames N`, `--threads N`, `--size WxH`, `--png PATH` (`""` disables),
`--png-frame K`. `-DJSNOW_NATIVE=ON` builds with `-march=native` instead of plain AVX2+FMA.
Without AVX2 the rasterizer falls back to a portable scalar path (same output).

## Pipeline

| stage | what it does |
|---|---|
| vertex | SoA transform of 53k vertices, outcodes, snapped screen coords (1/16 px), per-vertex Blinn-Phong half vector (view dependent, recomputed per frame). Auto-vectorized. |
| setup + bin | 64 triangle chunks in parallel: trivial frustum reject, back-face cull, near-plane + guard-band clipping, edge equations with top-left fill rule, attribute planes, bin into 64x64 tiles. |
| raster | Tiles pulled from an atomic queue by 4 threads. Each tile is rendered in a thread-local 64x64 color+depth buffer (L1/L2 resident). AVX2: 8 pixels per step — edge test, early depth test (reversed 1/w depth), then per-pixel lighting (normalized normal, Lambert + hemisphere ambient + Blinn-Phong ^32) only for surviving pixels. |
| reproject | Trick 3. Previous-frame pixel q has motion vector mv(q) from its depth and the two cameras. Each output pixel p solves q + mv(q) = p by 2 fixed-point iterations (AVX2, mv evaluated on the fly from the depth buffer). Pixels that don't converge to within 1 px are flagged invalid (disocclusions, off-screen). |
| scatter / compose | Trick 2. The quarter frame is rendered as a half-size image whose pixel centres land on one phase of the full grid; it is scattered into the history. With trick 3, valid history is clamped to the colour range of the 4 nearest fresh samples and invalid history is replaced by the nearest fresh sample. |
| upscale | Trick 1. 2x bilinear (9:3:3:1 weights), AVX2 16-bit arithmetic. |

How the tricks combine: `checker` alone keeps stale pixels in place (no motion
compensation). `reuse` alone renders a full frame every other frame and
reprojects in between. `checker+reuse` reprojects the history every frame and
refreshes a rotating quarter of it. `half` runs everything at 960x540 and
upscales at the end. Frame 0 of the temporal modes is a full render (bootstrap).

## Test scene

100,000 triangles: a 250x160-quad terrain (80,000) plus 50 UV spheres (400 each),
per-pixel lit, camera flying a circle over the terrain at 60 Hz time steps,
1920x1080 output. About 58,000 triangles survive culling each frame.

## Results

Machine: 4 vCPU Intel Xeon @ 2.1 GHz (cloud VM), GCC 13, AVX2+FMA, 4 threads.
300 timed frames after 8 warm-up frames. PSNR is against the baseline renderer
(mean squared error over every 5th frame), measured in a separate untimed pass.
Run-to-run variation on this shared VM is about ±15%.

| trick | FPS | ms/frame | PSNR | next bottleneck |
|---|---:|---:|---:|---|
| baseline | 171 | 5.85 | ref | per-pixel raster + shading: 4.8 of 5.9 ms |
| half | 317 | 3.16 | 34.9 dB | raster 1.8 ms, but ~1 ms is per-triangle cost that resolution can't shrink; geometry (vertex+setup) 1.0 ms |
| checker | 346 | 2.89 | 25.2 dB | same as half; quality is the real limit (stale pixels ghost under motion) |
| reuse | 206 | 4.85 | 37.5 dB | reprojection costs ~3.7 ms per use vs ~5.6 ms for a full render, so the saving is small |
| half+checker+reuse | 285 | 3.51 | 31.8 dB | post passes (reproject 0.94 + compose 0.41 + upscale 0.37 = 1.7 ms) and fixed geometry (0.93 ms); raster is only 0.86 ms |

Per-stage breakdown (ms/frame, averaged over all 300 frames):

| trick | vertex | setup+bin | raster | reproject | scatter/compose | upscale |
|---|---:|---:|---:|---:|---:|---:|
| baseline | 0.24 | 0.85 | 4.76 | – | – | – |
| half | 0.21 | 0.75 | 1.80 | – | – | 0.39 |
| checker | 0.24 | 0.75 | 1.74 | – | 0.16 | – |
| reuse | 0.11 | 0.41 | 2.48 | 1.84 | – | – |
| half+checker+reuse | 0.23 | 0.70 | 0.86 | 0.94 | 0.41 | 0.37 |

Other measurements:
- The scalar fallback (same algorithm, no SIMD) runs the baseline at 24.0 ms/frame
  (42 FPS); AVX2 makes the raster stage ~4.7x faster.
- Raster time at 480x272 / 960x540 / 1080p / 4K: 0.75 / 1.70 / 4.56 / 13.3 ms. Roughly
  0.5 ms is per-triangle work that doesn't depend on resolution; the rest scales with pixels.
- `--half --reuse` (not part of the required set) reached 2.46 ms (406 FPS) at 33.8 dB.

## Lessons from the optimization log

- **False sharing**: the per-chunk triangle vectors sat on shared cache lines, so
  setup was *slower* on 2 threads than on 1. `alignas(64)` cut setup+bin from 1.56 to 0.79 ms.
- **Reprojection latency**: the first version (3 dependent iterations per pixel,
  separate motion-vector buffers) cost 12 ms per frame. Evaluating motion on the fly,
  `rcp`+Newton instead of `div`, float index math instead of `mullo`, two interleaved
  8-pixel groups and 2 iterations brought it to ~3.7 ms at 1080p (0.94 ms at 540p).
- **Checker + reuse smearing**: gathering through disocclusions dragged foreground
  colours into the background. Validity flags with a fresh-sample fallback fixed it, and
  neighbourhood clamping raised PSNR from 28.0 to 34.1 dB (full res) and from 26.6 to 31.8 dB (all tricks).
