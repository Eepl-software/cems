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
| D2 meshlets (shadow 9.8, post 6.8) | baseline | 20.7 | 48.20 | ref | 1.42 | 3.27 | 26.71 | – | – | – | raster+shade 26.7 |
| D2 meshlets (shadow 4.6, post 1.3) | fast | 72.5 | 13.79 | 29.0 | 0.62 | 1.38 | 5.08 | 0.41 | – | 0.36 | raster+shade 5.1, shadow 4.6 |
| D3 HiZ occlusion (shadow 9.9, post 7.0, cull 1.3) | baseline | 20.6 | 48.58 | ref | 1.37 | 3.02 | 25.98 | – | – | – | raster+shade 26.0 (pixel shading, not triangles) |
| D3 HiZ occlusion (shadow 4.6, post 1.2, cull 0.5) | fast | 72.4 | 13.81 | 29.0 | 0.59 | 1.24 | 4.86 | 0.43 | – | 0.38 | raster+shade 4.9, shadow 4.6 |
| D4 LOD streaming `--stream` 64 MB (shadow 9.6, post 6.5) | baseline | 21.5 | 46.41 | 99.0 vs fully resident | 1.26 | 2.88 | 24.85 | – | – | – | raster+shade 24.9 |
| D4 LOD streaming `--stream` 64 MB (shadow 4.7, post 1.2) | fast | 71.6 | 13.96 | 29.0 | 0.61 | 1.25 | 4.90 | 0.43 | – | 0.38 | raster+shade 4.9, shadow 4.7 |
| D4 `--stream --stream-budget 16` (thrashing) | baseline | 22.4 | 44.73 | 45.2 vs fully resident | 1.21 | 2.44 | 23.55 | – | – | – | 5.7% of LOD picks fall back |
| DB1 static shadow caching (shadow 0.6, post 6.4) | baseline | 27.7 | 36.14 | ref | 1.30 | 2.75 | 23.88 | – | – | – | raster+shade 23.9 |
| DB1 static shadow caching (shadow 0.5, post 1.3) | fast | 99.3 | 10.08 | 29.0 | 0.63 | 1.27 | 4.94 | 0.42 | – | 0.39 | raster+shade 4.9 |

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
- D2: meshlets. Every object LOD is cut into clusters of <= 128 consecutive triangles;
  generators now emit quads in 8x8 blocks (terrain, cylinder sides, sphere bands) so a
  cluster is compact. Each cluster stores a bounding sphere and a normal cone (mean face
  normal + max deviation). Per frame: object frustum test + LOD, then per cluster frustum
  test (only for objects straddling a plane) and cone back-face test (eye direction with the
  sphere's angular radius; shadow passes use the light direction). `--no-meshlets`.
  Result: submitted triangles 592k → 450k (-24%), but frame time is unchanged within noise:
  setup was already rejecting those triangles cheaply, and only ~5% of clusters are
  cone-culled (terrain faces the camera; coarse tower/sphere LOD blocks span 120-240°).
  Meshlets are mainly the unit for D3's occlusion culling.
- D3: hierarchical-Z occlusion culling (`occlusion.cpp`). HiZ = 480x272 min-depth
  (= farthest) pyramid; object and meshlet spheres are projected (nearest-depth radius,
  +10%), tested at the level where the footprint is <= 2x2 texels, and culled if their
  nearest point is > 1 m behind the farthest occluder (margin for coarse occluders).
  Three HiZ sources were tried:
  1. occluder pre-pass (terrain chunks + towers at LOD2, depth-only raster at 480x272):
     459 meshlets + 12 objects culled, but costs 3.75 ms → net loss (`--occlusion-prepass`);
  2. last frame's depth re-projected into the current view by scatter: holes (= no
     occluder) propagate up the min pyramid → only 154 meshlets culled
     (`JSNOW_OCCLUSION_REPROJECT=1`);
  3. **default**: last frame's displayed depth min-reduced to 480x272 and tested with last
     frame's camera (scene is static; 1 frame of camera lag): 454 meshlets + 12 objects
     culled for ~1.0 ms; vs no occlusion 66 dB PSNR (no visible popping).
  Honest result: binned triangles −14%, frame time unchanged within noise. This view
  looks down over the field, only ~9% of meshlets are hidden, and the remaining cost is
  per-pixel shading, which occlusion does not reduce. `--no-occlusion`.
- D4: LOD streaming (`--stream`, `streaming.cpp`). LOD0/LOD1 of every object (6,8M-tri
  scene: 5.1M + 1.3M tris) start non-resident: their slice of the mesh arrays is zeroed
  and the bytes live in a per-entry backing store (stand-in for the disk). Every pass asks
  `Scene::lodProvider` for the LOD it wants and draws the finest resident LOD at or coarser
  than it (the coarsest LOD is always resident); misses enqueue a load. A background thread
  serves the queue nearest-first, `memcpy`s the data back into place, throttles to a
  simulated device (1000 MB/s + 2 ms per load, `--stream-bw`) and evicts LRU entries not
  used in the last 2 frames when over budget (`--stream-budget`, default 64 MB).
  Honest limits: data movement is real but memory is not actually released (regions are
  fixed in the arrays); warm-up frames pre-stream the start area; the quality reference
  is a second fully resident copy of the scene.
  Results (300 frames): 64 MB → 34 MB loaded in 751 loads, 0.3% fallback picks, PSNR 99 dB
  (no visible difference), no measurable cost. 16 MB → thrashing: 6,314 loads / 5,909
  evictions, 394 MB streamed, 5.7% fallbacks, PSNR 45 dB.
- **Phase D features complete** (5M tris, meshlets, HiZ, streaming). Next: repeat Phase B.

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

## Phase D-B: Phase B repeated on the 5M scene
Feature costs measured by switching each off (baseline, 100 frames, before DB1): shadows
~15 ms (passes 10 + lookups), transparency ~6.5, TAA ~6, bloom ~6.5, point lights ~5.5.

| round | change | baseline ms before → after | gain | fast ms before → after | gain |
|---|---|---|---:|---|---:|
| DB4 | point-light culling on 8x8 instead of 16x16 sub-tiles. A/B 3 runs each: no gain (36.5-42.1 vs 38.7-41.9 ms, noise) → **reverted** | ~0% | <10% | – | – |
| DB3 | `-DJSNOW_NATIVE=ON` (`-march=native`, AVX-512 for auto-vectorized loops; hand kernels stay 8-lane AVX2). A/B 2 runs: 37.2/37.9 vs 34.1/37.6 ms → ≤4%, within noise. Left as an option, default off | ≤4% | <10% | – | – |
| DB2 | bloom: SIMD fused bright pass (column sums over f rows, 8 lanes), tone-map computes only the bloom row and adds it in the SIMD loop. Bloom ~3 → ~1.7 ms | 36.14 → ~35.1 (2 runs 34.9/35.7 vs 36.1) | ~3% (<10%) | – | – |
| DB1 | static shadow caching: scene and sun are static, so a cascade is re-rendered only when its cached map stops covering the current frustum slice (c0 margin 12%, c1/c2 15%) instead of on a schedule. Frame 120/149 vs always-updated maps: 94.8/95.0 dB. Dynamic objects would need invalidation (not modelled). `JSNOW_SHADOW_STAGGER=1` restores B2 | 46.41 → 36.14 | 22% | 13.96 → 10.08 | 28% |

## Phase E: JSNOW as a Vulkan driver (`icd/`)
`libjsnow_icd.so` + generated `build/jsnow_icd.json`. Run any Vulkan app on it with
`VK_DRIVER_FILES=$PWD/build/jsnow_icd.json` (Xvfb works: `Xvfb :99 &; DISPLAY=:99`).
Env: `JSNOW_ICD_STATS=1` (avg submit time), `JSNOW_ICD_NO_PRESENT=1`,
`JSNOW_ICD_DUMP=/path/frame.ppm:N` (dump N-th presented frame), `JSNOW_ICD_THREADS=n`,
`JSNOW_ICD_MISSING_LOG=file` (append unsupported features hit at runtime).

Design: loader interface v2 (loader owns xcb surfaces); dispatchable handles carry the
loader magic; one memory type (host RAM, coherent), linear images; command buffers are
recorded as closures and executed synchronously in vkQueueSubmit (fences signal
immediately); generic Vulkan rasterizer (clip z∈[0,w] + guard band, viewport, Vulkan
area/front-face rules, cull, depth compare ops, blending ADD, perspective-correct
varyings), fragments in 4x2 blocks with helper lanes for derivatives, horizontal bands
across the thread pool; presentation via `xcb_put_image`.
SPIR-V (`icd/spirv.cpp`): parser + interpreter executing 8 invocations per step (8
vertices or a 4x2 pixel block). Values are 8-lane arrays; pointers carry per-lane
offsets (dynamic indexing), std140/430 buffer layouts from decorations, GLSL.std.450
subset, derivatives from lane neighbours, OpFunctionCall, structured branches (uniform
→ vector; divergent → automatic re-run one lane at a time), OpKill, OpPhi, sampling with
implicit LOD (bilinear, nearest mip).

| app | resolution | FPS | ms/frame | status |
|---|---|---:|---:|---|
| vkcube (Vulkan-Tools 1.3.275) | 500x500 | 137 | 7.3 (7.26 in vkQueueSubmit) | renders correctly (frame 30 checked: textured, lit via dFdx/dFdy normals, depth-tested); presentation ≈0.1 ms |
| Sascha Willems `triangle` | 1280x720 | 59-76 | 13-17 | renders correctly (needed Vulkan 1.1 core) |
| vkQuake 1.30.1 + LibreQuake e1m1 (free assets, built locally) | 1280x720 | – | – | **blocked**: `vkCreateComputePipelines` (cs_tex_warp); also needs multiple subpasses, texel buffers |

### Official-style Vulkan samples (Sascha Willems' examples, 31 tested; run 3 after E3/E4)
"no frame presented" = fewer than 10 frames in the 4 s benchmark window (too slow, not wrong).
FPS from the examples' own `-b` benchmark mode (1280x720, includes presentation).
Khronos' Vulkan-Samples (the official set) need Vulkan 1.1 + ~20 submodules (VMA, glfw,
tracy, OpenCL headers, ...); Sascha Willems' examples were used as the practical set.

| example | status | FPS | missing features hit |
|---|---|---:|---|
| triangle | runs | 74.1104 | – |
| pipelines | runs | 4.8077 | dynamic state 2 |
| descriptorsets | runs | 22.5607 | – |
| dynamicuniformbuffer | runs | 18.1600 | – |
| pushconstants | runs | 23.2044 | – |
| specializationconstants | runs | 7.3457 | dynamic state 2 |
| texture | runs | 23.8670 | – |
| texturearray | runs | 30.2004 | – |
| texturecubemap | runs | 10.4942 | – |
| texturemipmapgen | runs | 7.1776 | separate images/samplers (bound per binding only) |
| gltfloading | runs | 9.1491 | – |
| gltfskinning | runs | 43.3333 | – |
| gltfscenerendering | runs, no frame presented | 0.9482 | – |
| instancing | runs, no frame presented | 0.3946 | – |
| indirectdraw | runs, no frame presented | 0.0741 | – |
| offscreen | runs, no frame presented | 0.6939 | – |
| shadowmapping | runs, no frame presented | 1.2006 | depth bias; dynamic state 3; vkCmdSetDepthBias |
| shadowmappingcascade | runs, no frame presented | 0.0928 | – |
| deferred | runs, no frame presented | 0.7474 | – |
| ssao | runs, no frame presented | 0.1630 | – |
| hdr | runs, no frame presented | 0.4296 | – |
| bloom | runs, no frame presented | 1.6717 | – |
| multisampling | runs | 13.4339 | – |
| particlesystem | runs | 9.7462 | primitive topology 0 |
| computeshader | fails (exit 255), no frame presented | – | compute pipelines; descriptor type 3 |
| stencilbuffer | runs | 17.4905 | stencil test |
| occlusionquery | runs | 11.0522 | – |
| radialblur | runs, no frame presented | 0.5112 | – |
| multithreading | runs, no frame presented | 0.6732 | – |
| pbrbasic | runs, no frame presented | 0.5448 | – |
| negativeviewportheight | runs | 21.0151 | – |

Round history: run 1 (E2) 22/31 run, 6 crash (missing core entry points → null function
pointers), 2 fail. Run 2 (E3: queries, indirect draws, events, buffer views, resolve, MRT,
RGBA16F/R8/depth sampling, spec constants, MatrixInverse, image size queries,
maintenance1) 26/31. Run 3 (E4: OpSpecConstantOp folding, masked if/else, layout cache,
parallel VS, allocation-free setup) 30/31 (only `computeshader`). Speed-ups E3→E4:
gltfloading 4.0→9.1 FPS, pushconstants 8.6→23.2, pbrbasic 0.25→0.54, multithreading
0.25→0.67.

### Missing features, ordered by how much they block
1. **Shader interpreter speed** — 17/31 examples < 2 FPS. Example: shadowmapping spends
   3.9 s of 4 s in raster+FS (~8.7 µs per 8-pixel block). Interpreting SPIR-V costs
   ~100-1000x a native kernel. Fix: JIT SPIR-V → native SIMD (LLVM or a custom x86/ARM
   emitter), like SwiftShader (Reactor) or lavapipe (gallivm).
2. **Compute pipelines** (GLCompute model, workgroups, shared memory, barriers, storage
   buffer/image writes, atomics) — blocks `computeshader`, vkQuake, and every modern game.
3. Multiple subpasses / input attachments (vkQuake, deferred renderers).
4. Texel buffers (uniform/storage texel buffer reads/writes) (vkQuake).
5. Stencil test (stencilbuffer renders without it), depth bias (shadow acne in shadowmapping),
   points/lines topology (particlesystem), separate sampled images + samplers
   (texturemipmapgen), divergent loops (fall back to 8x per-lane re-run), early returns
   inside divergent branches, MSAA (rendered single-sampled), blend ops other than ADD,
   BC/ETC/ASTC texture compression, dynamic rendering, Vulkan 1.2/1.3 core
   (timeline semaphores, buffer device address, descriptor indexing, sync2) — DXVK and
   VKD3D-Proton require these, so no DX11/DX12 game can start yet.



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
- **Phase D-B stopped after DB4** (DB2, DB3, DB4 each < 10%). Phase D-B total: baseline
  46.4 → ~35-36 ms (DB1 static shadow caching was the only big win). Remaining profile
  (callgrind, per frame): tile raster + G-buffer resolve ~55%, lighting ~12%, triangle
  setup ~11%, shadow lookups ~6%, TAA ~7%, vertex ~6%, tone map ~4%.
- Phase E next: compute pipelines, then a SPIR-V JIT (the dominant performance blocker).
