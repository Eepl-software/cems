# JSNOW progress log

Goal: measure every step towards running AAA PC games on CPU only (no GPU).
Machine for all numbers: 4 vCPU Intel Xeon @ 2.1 GHz cloud VM (shared, ±15% run-to-run
noise), GCC 13, AVX2+FMA, 4 threads, 1920x1080 output, 300 frames.
`./build/jsnow --bench-fast --quality` produces the baseline / fast rows below.
PSNR is always against the *current* baseline renderer of that step.

## How to resume
```
cd jsnow && cmake -S . -B build && cmake --build build -j
./build/jsnow --bench-fast --quality --png ""
```
Tools installed in the session (needed again in a fresh container):
`apt-get install -y g++-aarch64-linux-gnu qemu-user vulkan-tools libvulkan-dev glslang-tools spirv-tools`

## Results table (one row per step)

| step | config | FPS | ms/frame | PSNR | vertex | setup+bin | raster | reproject | compose | upscale | bottleneck |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 0 (session 1) | baseline | 171 | 5.85 | ref | 0.24 | 0.85 | 4.76 | – | – | – | raster/shading |
| A1 --fast | baseline | 186 | 5.38 | ref | 0.20 | 0.77 | 4.41 | – | – | – | raster/shading |
| A1 --fast | fast | 475 | 2.10 | 33.8 | 0.10 | 0.34 | 0.87 | 0.44 | – | 0.35 | raster ≈ reproject+upscale |
| A2 textures | baseline | 92 | 10.91 | ref | 0.18 | 0.85 | 9.87 | – | – | – | raster: texture sampling + per-pixel attrs |
| A2 textures | fast | 306 | 3.27 | 32.9 | 0.09 | 0.39 | 2.01 | 0.44 | – | 0.33 | raster |
| A3 shadows | baseline | 40.5 | 24.72 | ref | 0.24 | 1.01 | 16.69 | – | – | – | raster (shadow lookups in forward shading of overdrawn px) 16.7, shadow passes 6.8 |
| A3 shadows | fast | 128 | 7.82 | 33.9 | 0.10 | 0.44 | 3.17 | 0.45 | – | 0.37 | shadow passes 3.3 (resolution independent) |
| A4 1M tris (shadow 10.4) | baseline | 22.9 | 43.63 | ref | 0.62 | 2.63 | 29.97 | – | – | – | raster: forward shading of tiny triangles wastes 8-lane groups |
| A4 1M tris (shadow 5.4) | fast | 71.7 | 13.94 | 33.9 | 0.31 | 1.26 | 6.12 | 0.50 | – | 0.39 | raster 6.1, shadow 5.4 |
| A5 NEON (x86 numbers; shadow 10.9) | baseline | 22.4 | 44.57 | ref | 0.70 | 2.75 | 30.18 | – | – | – | raster |
| A5 NEON (x86 numbers; shadow 5.2) | fast | 74.7 | 13.38 | 33.9 | 0.31 | 1.22 | 5.85 | 0.44 | – | 0.37 | raster ≈ shadow |
| B1 visibility buffer (shadow 11.2) | baseline | 34.4 | 29.09 | ref | 0.67 | 2.91 | 14.34 | – | – | – | raster 14.3, shadow 11.2 |
| B1 visibility buffer (shadow 5.4) | fast | 92.4 | 10.82 | 33.9 | 0.33 | 1.36 | 2.90 | 0.47 | – | 0.40 | shadow passes 5.4 (half the frame) |
| B2 staggered cascades (shadow 7.4) | baseline | 41.0 | 24.36 | ref | 0.68 | 2.76 | 13.56 | – | – | – | raster 13.6 (shading) |
| B2 staggered cascades (shadow 3.5) | fast | 120 | 8.35 | 33.9 | 0.30 | 1.23 | 2.56 | 0.44 | – | 0.37 | shadow 3.5, raster 2.6 |
| B3+B4 lazy attrs, coarse casters (shadow 4.6) | baseline | 45.5 | 21.95 | ref | 0.68 | 1.86 | 14.75 | – | – | – | raster 14.8 (tile shading ≈ 2/3) |
| B3+B4 lazy attrs, coarse casters (shadow 2.2) | fast | 142 | 7.02 | 33.9 | 0.30 | 0.79 | 2.94 | 0.46 | – | 0.38 | raster 2.9, shadow 2.2 |
| B5+B6 hw gather, shadow skip (shadow 4.3) | baseline | 52.9 | 18.91 | ref | 0.60 | 1.65 | 12.40 | – | – | – | raster 12.4 (tile shading) |
| B5+B6 hw gather, shadow skip (shadow 2.1) | fast | 154 | 6.48 | 33.9 | 0.27 | 0.74 | 2.62 | 0.40 | – | 0.38 | raster 2.6, shadow 2.1 |

## Decisions log
- A1: `--fast` = half resolution + reuse (best trade-off found in session 1).
  `--bench-fast` benchmarks baseline and fast only.

- A2: SIMD wrapper `simd.hpp` (AVX2 / NEON / scalar, 8 lanes) so every kernel is written once.
  Perspective-correct attributes (u, v, normal, world position; q = 1/w planes).
  Textures: 4 procedural tileable 2048² RGBA8 textures, full box-filtered mip chain,
  per-pixel LOD from analytic UV derivatives, bilinear within nearest mip
  (GL_LINEAR_MIPMAP_NEAREST), repeat wrap, 4 lane-wise gathers per pixel.
  Depth buffer now stores z/w = near/w (reprojection takes a depth scale).
  Scene = objects with up to 3 LOD index ranges + per-triangle material; draw lists per pass.
- A3: 3-cascade sun shadow maps (1024² each, splits 22/65/230 m), bounding-sphere fit +
  texel snapping, reversed-depth orthographic, depth-only raster mode, back-face culled
  casters, coarser LOD for cascades 1-2, 2x2 bilinear PCF, slope-scaled bias.
  Sun lowered to (0.62, 0.42, 0.32) for visible shadows. `--no-shadows` disables.
  Shadow-pass time is in the `shadow` column (includes its own vertex/setup/raster).
- A4: default scene is now `large`: 16x16 terrain chunks (40x40 quads each, LOD 40/20/10
  with 2 m skirts against cracks) + 50 spheres (2208/528/120 tris) = 1,011,520 triangles at
  full detail (1.36M across all LODs). Per-object bounding-sphere frustum culling (side +
  near planes; shadow passes side planes only). LOD = finest level whose edge projects to
  >= 5 px at a 1080-line reference. ~300k triangles submitted/frame, ~160k survive setup.
  `--scene small` keeps the 100k session-1 scene.
- A5: NEON backend lives in `simd.hpp` (two float32x4 per 8-lane value). Reprojection was
  ported from raw AVX2 to the wrapper. The 2x upscale keeps an AVX2 fast path; on other
  ISAs it uses the portable SWAR loop. Cross-build: `cmake -DCMAKE_TOOLCHAIN_FILE=cmake/aarch64-linux-gnu.cmake`.
  **Tested under qemu-aarch64 emulation**: output matches the AVX2 build at 70.3 dB PSNR
  (max channel diff 2/255, from rcp/rsqrt estimate differences); the forced-scalar build
  (`-DJSNOW_FORCE_SCALAR`) matches too. **Not performance-tested on real Apple Silicon**
  (qemu timings are meaningless); not compile-tested with Apple clang / macOS SDK.

## Phase B optimisation rounds
| round | change | baseline ms before → after | gain | fast ms before → after | gain |
|---|---|---|---:|---|---:|
| B7 | raster tiles scheduled largest-first (by binned triangle count). Kept (harmless) | 18.91 → 19.1 (2 runs: 18.87, 19.39) | 0% (<10%) | 6.48 → 6.59 | 0% |
| B6 | skip shadow lookups for 8-px groups that are all sky or all facing away from the sun; specular masked by n·L>0 | ~20.9 → 18.91 (B5+B6 combined 21.95 → 18.91 = 14%) | ~9.6% (<10%, conservative) | 7.02 → 6.48 combined | 8% |
| B5 | AVX2 hardware gather (`JSNOW_HW_GATHER`, CMake option, default ON; turn OFF on CPUs with the GDS/Downfall mitigation). A/B 3 runs | ~4% | <10% | – | – |
| B4 | shadow casters one LOD coarser than the camera (c0 +1, c1/c2 +2); frame-150 PSNR vs fine casters 45.0 dB, 0.26% of pixels differ by >10/255 (shadow-edge shifts). `JSNOW_SHADOW_LOD=0` restores | 24.36 → 21.95 | 11% | 8.35 → 7.02 | 16% |
| B3 | lazy attribute planes: setup builds only edges/depth + vertex ids; planes built per tile on first visible use (bit-identical). Setup 2.8 → 2.0 ms but tile raster grew by about as much | 24.36 → ~24.0 (A/B 3 runs: within noise) | ~2% (<10%) | – | – |
| B2 | staggered shadow cascades (c0 every frame, c1 every 2nd, c2 every 4th, kept only while they still cover the slice; 15% radius margin) | 29.09 → 24.36 | 16% | 10.82 → 8.35 | 23% |
| B1 | per-tile visibility buffer: raster writes depth + triangle id only; each tile shaded once per pixel, attributes resolved per distinct triangle per 8-px group, per-lane materials (texture array) | 44.57 → 29.09 | 35% | 13.38 → 10.82 | 19% |

B1 output is bit-identical to the forward renderer (same per-pixel math).
B2 quality cost: frame 150 / 297 vs always-updated cascades = 99.0 / 98.2 dB
(`JSNOW_SHADOW_NOCACHE=1` disables caching; `JSNOW_SHADOW_DEBUG=1` prints shadow sub-stages).
Quality pass now renders the reference every frame so its caches stay in step.

## Done
- Session 1: tiled AVX2 rasterizer, half/checker/reuse tricks, benchmark harness.
- A1: `--fast`.
- A2: textures (2048², mips, bilinear, SIMD sampling).
- A3: sun + 3-cascade shadow maps.
- A4: 1M-triangle scene, frustum culling, 3 LODs.
- A5: NEON path (cross-compiled, functionally verified under qemu).

## Next
- **Phase B stopped after B7**: B5, B6, B7 each gained <10% (stop rule). Phase B total:
  baseline 44.57 → 18.91 ms (2.36x), fast 13.38 → 6.48 ms (2.06x).
  Remaining profile (baseline): tile shading ~8 ms, visibility raster ~4.5 ms, shadow passes 4.4, setup 1.7.
- Phase C: C1 tile-deferred G-buffer + PBR + HDR + tone mapping; C2 100+ point lights with tiled
  culling; C3 transparency; C4 bloom; C5 TAA.
