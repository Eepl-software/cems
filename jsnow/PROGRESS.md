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

## Done
- Session 1: tiled AVX2 rasterizer, half/checker/reuse tricks, benchmark harness.
- A1: `--fast`.
- A2: textures (2048², mips, bilinear, SIMD sampling).
- A3: sun + 3-cascade shadow maps.
- A4: 1M-triangle scene, frustum culling, 3 LODs.
- A5: NEON path (cross-compiled, functionally verified under qemu).

## Next
- Phase B: first target = forward shading of tiny triangles (move to deferred / visibility buffer).
