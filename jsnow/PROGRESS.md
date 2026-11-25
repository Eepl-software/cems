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
| C1 deferred + PBR + HDR/ACES (shadow 4.3, post 0.84) | baseline | 47.4 | 21.08 | ref | 0.62 | 1.61 | 13.67 | – | – | – | raster+shade 13.7 |
| C1 deferred + PBR + HDR/ACES (shadow 2.0, post 0.11) | fast | 156 | 6.40 | 32.6 | 0.25 | 0.68 | 2.60 | 0.37 | – | 0.35 | raster+shade 2.6, shadow 2.0 |
| C2 128 point lights, tiled culling (shadow 4.3, post 0.84) | baseline | 43.1 | 23.18 | ref | 0.58 | 1.58 | 15.81 | – | – | – | raster+shade 15.8 (lights ≈ +2.2) |
| C2 128 point lights (shadow 2.2, post 0.14) | fast | 130 | 7.71 | 33.0 | 0.32 | 0.84 | 3.36 | 0.42 | – | 0.41 | raster+shade 3.4, shadow 2.2 |
| C3 transparency (shadow 4.4, post 0.84) | baseline | 38.0 | 26.29 | ref | 0.63 | 1.73 | 18.68 | – | – | – | raster+shade 18.7 (water re-lit forward ≈ +3) |
| C3 transparency (shadow 2.1, post 0.11) | fast | 130 | 7.70 | 32.7 | 0.30 | 0.80 | 3.65 | 0.40 | – | 0.37 | raster+shade 3.7 |
| C4 bloom (shadow 4.5, post 3.6) | baseline | 31.9 | 31.31 | ref | 0.70 | 1.86 | 20.62 | – | – | – | raster+shade 20.6 (incl. fused bright pass), post 3.6 |
| C4 bloom (shadow 2.2, post 0.87) | fast | 107 | 9.35 | 32.6 | 0.34 | 0.88 | 4.23 | 0.43 | – | 0.38 | raster+shade 4.2 |
| C5 TAA (shadow 4.8, post 7.2) | baseline | 26.2 | 38.10 | ref | 0.73 | 2.07 | 23.29 | – | – | – | raster+shade 23.3, post 7.2 (TAA ≈ 3.5) |
| C5 TAA (shadow 2.3, post 1.3) | fast | 102 | 9.79 | 31.2 | 0.33 | 0.87 | 4.21 | 0.41 | – | 0.37 | raster+shade 4.2 |
| D1 5M tris (shadow 9.7, post 6.8) | baseline | 20.9 | 47.86 | ref | 1.47 | 3.32 | 26.60 | – | – | – | raster+shade 26.6, shadow 9.7 |
| D1 5M tris (shadow 5.2, post 1.4) | fast | 63.7 | 15.69 | 29.0 | 0.77 | 1.67 | 5.76 | 0.44 | – | 0.48 | raster+shade 5.8, shadow 5.2 |

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
- C1: tile-based deferred shading. Per 8-px group: resolve a G-buffer (linear albedo,
  normal, world pos, view depth, roughness, metallic) from the visibility buffer, then a
  lighting pass: Cook-Torrance (GGX D, Schlick-GGX visibility, Schlick Fresnel) + Lambert,
  metallic-roughness, sun (3.2 HDR, shadowed) + hemisphere sky ambient. The G-buffer
  stays in registers/L1 (never written to memory) — the CPU version of on-chip tile
  memory. Output = linear HDR float planes; `tonemap` (exposure, ACES fit, gamma-2 encode)
  writes RGBA8. Textures decoded with gamma 2. Materials: roughness/metallic/alpha;
  30% of spheres metallic (separate RNG keeps sphere placement).
  **Bug found & fixed in C1**: `Target` gained an `hdr[3]` member and the shadow pass's
  brace-initialiser silently put the shadow-map pointer into `hdr[1]` → shadows vanished.
  Bisect showed shadows worked through B7; now `Target` fields are assigned by name.
- C2: 128 point lights (`--lights N`, max 255; `--no-lights`), coloured lamps 1.5-3 m above
  the terrain, radius 9 m, inverse-square falloff with a smooth (1-(d/r)^4)^2 window, same
  GGX BRDF as the sun. Tiled culling per 16x16 sub-tile: each light's conservative screen
  rectangle (projected AABB corners, full screen if it crosses the near plane) and view-depth
  range against the sub-tile's min/max depth; per-group loop over the sub-tile's list.
  Lighting changed to dusk so the lamps are visible (sun 1.6/1.15/0.75, sky 0.10/0.14/0.26,
  exposure 1.6). Lights cost ≈ 2.2 ms at 1080p on 4 cores.
- C3: transparency. Water plane at y = -3 (4x4 chunks, 8,192 tris, alpha 0.55, roughness
  0.08) fills the valleys; 8 floating glass spheres (alpha 0.3, 3 LODs). Objects flagged
  `transparent` go to a second draw list, set up into a second set of 64 chunks with their own
  tile bins. Per tile, after opaque deferred lighting: transparent triangles sorted
  back-to-front by depth at their bbox centre, depth-tested against opaque depth (no
  write), forward-shaded with the same G-buffer resolve + PBR lighting (sun, shadows, tiled
  point lights) and alpha-blended into the HDR tile. Limitations (logged): transparent
  objects cast no shadows; per-triangle (not per-pixel) sorting; sub-tile light lists use
  opaque depth bounds, so a light in front of all opaque surfaces of a sub-tile can miss
  a glass sphere; reprojection uses opaque depth for transparent pixels. `--no-transparency`.
- C4: HDR bloom. Bright pass (threshold 1.0, firefly clamp 16 per sample) + box downsample
  to 1/4 of the *output* resolution (factor 4 at full res, 2 at half res / checker), fused
  into the rasterizer's tile write-out (the tile is still in L1, saves re-reading 24 MB of
  HDR). 5 levels, separable 5-tap Gaussian per level, 9:3:3:1 bilinear upsample-accumulate;
  levels 1-4 run serially in one task (tiny). Tone mapping adds bloom (strength 0.35)
  with a bilinear upsample using fixed per-phase weights. Bloom costs ≈ 2.5 ms at 1080p
  (noisy: 1.5-5 ms). `--no-bloom`, `JSNOW_BLOOM_DEBUG=1`.
  Fixed on the way: first version cost 10 ms (non-vectorizable clamped loops), and
  `--fast` PSNR fell to 21 dB because single-pixel specular "fireflies" (HDR ~1e3 on smooth
  metal/glass) dominated the bloom differently at each resolution and coarse levels were
  upsampled nearest-neighbour (64-px blocks). Firefly clamp + bilinear upsampling → 32.6 dB.
- Note: VM timing noise grew during C3/C4 (same binary: 28.3-33.2 ms baseline).
- C5: TAA. Halton(2,3) sub-pixel jitter (8-frame cycle) applied through the viewport
  offset; resolve after tone mapping on RGBA8: backward reprojection with the current
  depth and the previous camera (unjittered sample positions), bilinear history fetch,
  3x3 neighbourhood min/max clamp on packed bytes (new wrapper ops minu8/maxu8/avgu8),
  blend 1/8 current + 7/8 history via three rounding byte averages. History = previous
  *displayed* image (so reprojected `--reuse` frames feed it too). Not combined with
  `--checker` (sub-images already use fixed sample offsets). `--no-taa`. Costs ≈ 3.5 ms at
  1080p (post column) — optimisation target.
- **Phase C complete**: deferred shading (C1), PBR (C1), 128 point lights + tiled culling
  (C2), transparency (C3), bloom (C4), ACES tone mapping (C1), TAA (C5).
  Full-quality frame: 38 ms (26 FPS) at 1080p; `--fast`: 9.8 ms (102 FPS) at 31.2 dB.
- D1: `--scene huge` (new default): 320x320 m terrain (32x32 chunks, 3 LODs + skirts),
  480 cylinder towers (2880/720/168 tris, 1.5-4 m radius, 8-30 m tall, flagged as occluders),
  50 spheres, 8 glass spheres, water. 5,123,136 triangles at full detail (6.86M across all
  LODs, 3.7M vertices, built in 1.3 s). ~580k triangles submitted / ~286k binned per frame.

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
- Phase D: D1 5M-triangle scene; D2 meshlets (triangle clusters with bounds + normal cones);
  D3 hierarchical-Z occlusion culling; D4 LOD streaming (residency budget + background loads);
  then repeat Phase B (targets: raster+shade, TAA 3.5 ms, bloom 2.5 ms, shadows 4.8 ms).
