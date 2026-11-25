# JSNOW final report — how close is CPU-only rendering to AAA games?

Machine for every number: cloud VM, **4 physical cores** (no SMT) Intel Xeon @ 2.1 GHz,
AVX2+FMA, GCC 13, 1920x1080 output, 300 frames per run. The VM is shared: identical
binaries vary by ±10-15 % between runs. PSNR is measured against that step's own
full-quality renderer. Session 1 numbers are in `README.md`; the full log, decisions and
per-stage timings are in `PROGRESS.md`.

## 1. Every step

Baseline = full quality at native 1080p. Fast = half resolution + reuse of every other
frame via motion vectors.

| step | what was added | baseline FPS | baseline ms | fast FPS | fast ms | fast PSNR | bottleneck after the step |
|---|---|---:|---:|---:|---:|---:|---|
| S1 | session 1: tiled AVX2 rasterizer, 100k tris, Gouraud/Phong | 171 | 5.85 | – | – | – | pixel shading |
| A1 | `--fast` (half res + reuse) | 186 | 5.38 | 475 | 2.10 | 33.8 | raster ≈ reproject + upscale |
| A2 | 2048² textures, mips, bilinear, SIMD sampling, perspective-correct attributes | 92 | 10.91 | 306 | 3.27 | 32.9 | texture sampling |
| A3 | sun + 3-cascade shadow maps (PCF) | 40.5 | 24.72 | 128 | 7.82 | 33.9 | shadow lookups + shadow passes |
| A4 | 1M triangles, frustum culling, 3 LODs | 22.9 | 43.63 | 71.7 | 13.94 | 33.9 | forward shading of tiny triangles |
| A5 | NEON path (verified under qemu, 70 dB vs AVX2) | 22.4 | 44.57 | 74.7 | 13.38 | 33.9 | raster |
| B1 | per-tile visibility buffer, deferred tile shading | 34.4 | 29.09 | 92.4 | 10.82 | 33.9 | raster 14.3, shadows 11.2 |
| B2 | staggered shadow cascades | 41.0 | 24.36 | 120 | 8.35 | 33.9 | tile shading |
| B3+B4 | lazy attribute setup; coarser shadow casters | 45.5 | 21.95 | 142 | 7.02 | 33.9 | tile shading |
| B5+B6 (+B7) | HW gathers, shadow-lookup skipping (B7: 0 %) — Phase B stopped (3×<10 %) | 52.9 | 18.91 | 154 | 6.48 | 33.9 | tile shading ~2/3 |
| C1 | deferred shading + PBR (GGX) + HDR + ACES tone mapping | 47.4 | 21.08 | 156 | 6.40 | 32.6 | raster+shade |
| C2 | 128 point lights, tiled light culling | 43.1 | 23.18 | 130 | 7.71 | 33.0 | lights ≈ +2.2 ms |
| C3 | transparency (water, glass), sorted, forward-blended | 38.0 | 26.29 | 130 | 7.70 | 32.7 | transparent re-shading ≈ +3 ms |
| C4 | HDR bloom | 31.9 | 31.31 | 107 | 9.35 | 32.6 | bloom ≈ 2.5 ms |
| C5 | TAA | 26.2 | 38.10 | 102 | 9.79 | 31.2 | TAA ≈ 3.5 ms, raster+shade 23 |
| D1 | 5M triangles (320 m terrain, 480 towers) | 20.9 | 47.86 | 63.7 | 15.69 | 29.0 | raster+shade 26.6, shadows 9.7 |
| D2 | meshlets (128-tri clusters, cone culling) | 20.7 | 48.20 | 72.5 | 13.79 | 29.0 | pixel shading (triangles −24 %, time unchanged) |
| D3 | hierarchical-Z occlusion (last-frame depth) | 20.6 | 48.58 | 72.4 | 13.81 | 29.0 | pixel shading (only ~9 % of meshlets hidden in this view) |
| D4 | LOD streaming (64 MB budget, 1 GB/s simulated device) | 21.5 | 46.41 | 71.6 | 13.96 | 29.0 | pixel shading |
| DB1 | static shadow caching | 27.7 | 36.14 | 99.3 | 10.08 | 29.0 | raster+shade 24 |
| DB2-4 | SIMD bloom, `-march=native`, finer light culling — stopped (3×<10 %) | ~28 | ~35-36 | ~100 | ~10 | 29.0 | raster+shade 25, post 5.5 |
| **final** | everything on (re-measured at the end) | **27.1** | **36.86** | **105** | **9.49** | **29.0** | **raster+shade 25.4 (of which shading ≈ 2/3), post 5.5** |

Final run, all six configurations (5M-triangle scene, every feature on):

| config | FPS | ms/frame | PSNR vs baseline |
|---|---:|---:|---:|
| baseline | 27.1 | 36.86 | ref |
| half | 53.6 | 18.67 | 33.2 dB |
| checker | 59.1 | 16.92 | 21.9 dB |
| reuse | 40.6 | 24.66 | 31.6 dB |
| half+checker+reuse | 69.9 | 14.30 | 30.6 dB |
| fast (half+reuse) | 105.4 | 9.49 | 29.0 dB |

Phase E — JSNOW as a Vulkan driver (`icd/`, SPIR-V interpreter):

| app | res | FPS | status |
|---|---|---:|---|
| vkcube | 500x500 | 137 | correct |
| Sascha Willems Vulkan examples (31 tested) | 1280x720 | 0.07 – 74 | 30/31 run; 13 at ≥ 2 FPS; only `computeshader` fails (no compute) |
| vkQuake 1.30.1 + LibreQuake map (free data, built locally) | 1280x720 | – | blocked: compute pipelines, multiple subpasses, texel buffers |

## 2. Against a 16.6 ms (60 FPS) budget on this 4-core CPU

| | ms/frame | vs 16.6 ms |
|---|---:|---|
| JSNOW full quality, 1080p | 36.9 | 2.2x over budget |
| JSNOW `--fast` (half res + frame reuse) | 9.5 | fits, at 29 dB PSNR (visible softening, reprojection artefacts) |
| JSNOW `--all` (half + checker + reuse) | 14.3 | fits, 30.6 dB |

This is **not** an AAA frame. What JSNOW's scene has vs a typical AAA frame:

| | JSNOW final scene | AAA frame (GTA V high / RDR2 / UE5) |
|---|---|---|
| triangles after culling | ~250k binned of 5M | 1-10M+ (Nanite: tens of millions of micro-triangles) |
| shading per pixel | ~150 ALU ops, 1 texture, GGX sun + lights | 500-5000 ALU ops, 4-16 textures, layered materials |
| lights / shadows | 128 point lights (no shadows), 1 cached CSM | hundreds of lights, several shadowed, contact shadows |
| effects | bloom, TAA, transparency | GI (Lumen / probes), SSR, SSAO/GTAO, volumetric fog and clouds, DOF, motion blur, particles, hair, skinned characters |
| CPU left for rendering | 100 % of 4 cores | games already need 2-6 cores for simulation, AI, physics, audio, driver |

Rough throughput argument: these 4 AVX2 cores peak at ~270 GFLOPS fp32; an RTX 3060 is
~13 TFLOPS (~50x), and its fixed-function rasterizers, texture units and memory bandwidth
(360 GB/s vs ~50 GB/s measured here) widen the gap. JSNOW recovers ~3-4x with
resolution/temporal tricks. It does not close a 50-500x gap.

## 3. Estimate for a 12-core Apple Silicon Mac

**Not measured.** The NEON path is only verified functionally under emulation.
Assumptions: a 12-core M-series (e.g. 8 performance + 4 efficiency cores) at ~4 GHz. A
P-core runs 4x128-bit FMA pipes, the same FLOPs per cycle as 2x256-bit AVX2, so ~1.9x
this 2.1 GHz Xeon core per cycle-time; an E-core ≈ 0.4 P-core. That's ~17 "VM cores"
vs 4, at ~70 % scaling efficiency (JSNOW scaled 3.5x on 4 cores), and memory bandwidth
of 200-400 GB/s is not a limit.

| | this VM | 12-core Apple Silicon (estimate) |
|---|---:|---:|
| JSNOW full quality, 1080p | 36.9 ms (27 FPS) | ~11-13 ms (~80-90 FPS) |
| JSNOW `--fast` | 9.5 ms (105 FPS) | ~3-4 ms (250+ FPS) |
| JSNOW full quality, 4K (≈ 3.5x pixels) | ~110 ms | ~35-40 ms |

So a big Apple-Silicon CPU could run *this* scene at 60 FPS in full quality at 1080p,
but nothing close to an AAA frame (§2).

## 4. What would still be needed to run GTA V, RDR2 and Black Myth: Wukong

None of the three can start on JSNOW today. The blockers, in order:

1. **API coverage.**
   - **GTA V** is DirectX 11; on Linux it runs through DXVK, which needs Vulkan 1.3-class
     features. **Black Myth: Wukong** is DirectX 12 (Unreal Engine 5) through VKD3D-Proton,
     which needs Vulkan 1.3 plus descriptor indexing, buffer device address, timeline
     semaphores, sync2 and more. **RDR2** has a native Vulkan renderer that relies on the
     same class of features.
   - JSNOW's driver is Vulkan 1.1 without compute, so the first hard gap is the **compute
     model**: workgroups, shared memory, barriers, atomics, storage images/buffers. Then
     multiple subpasses, texel buffers, stencil, depth bias, MSAA, BC1-7 texture
     decompression, dynamic rendering and Vulkan 1.2/1.3 core.
   - UE5 additionally uses mesh/compute-shader rasterization (Nanite) and expects GPU-scale
     compute.
2. **A shader JIT.** The SPIR-V interpreter costs ~100-1000x a native kernel; for example,
   a simple PBR sample runs at 0.5 FPS. Real games need SPIR-V/DXIL → LLVM (or a custom
   emitter) → native AVX2/AVX-512/NEON code with SIMD-across-pixels and SIMD-across-vertices.
   That's the SwiftShader / lavapipe approach. Even those mature drivers run modern games
   at single-digit FPS on 16-core desktops.
3. **Raw throughput.**
   - GTA V (2013-era) at low settings and 720p is plausibly within reach of a JIT driver on
     a 12-16 core CPU at 20-30 FPS with JSNOW's half-res + reuse tricks; this is an
     estimate, not a measurement.
   - RDR2 needs roughly 5-10x more shading and memory work per frame.
   - Wukong (UE5 Nanite + Lumen GI + virtual shadow maps) needs ~10-30 GPU-TFLOPS-class
     work per frame at 1080p60, which is 50-100x what a 12-core CPU delivers.
4. **CPU budget sharing.** The game's own simulation already uses several cores; a CPU
   renderer competes with it for the same cores and memory bandwidth.

**Honest bottom line:** for engines that JSNOW controls itself (Phases A-D), the CPU is
close: 27 FPS at full quality, 105 FPS with the tricks, on 4 cores. Running unmodified
AAA games through a CPU Vulkan driver is out of reach for RDR2 and Wukong on any current
CPU. GTA V-class games would need compute support, Vulkan 1.3, a JIT shader compiler and a
12+ core CPU just to reach low-settings playability. The most valuable next steps are, in
order: compute pipelines, a SPIR-V JIT, then the Vulkan 1.3 feature set DXVK needs.

## 5. Session 3 (Phase F): vkQuake on CPU only

Same machine (4 cores, Xeon 2.1 GHz, AVX2). Game: vkQuake 1.30.1 + LibreQuake (free data,
maps compiled locally; fullbright because `light` needs Embree). Benchmark: vkQuake's
`timedemo demo1` (2917 frames, level "Dismal Shores"), driver = JSNOW Vulkan ICD with the
new SPIR-V → native SIMD compiler. `fast` = the game runs at half width and half height
and the driver upscales each frame bilinearly to the full size (cost included).

| resolution | mode | FPS | ms/frame | bottleneck (driver stats) |
|---|---|---:|---:|---|
| 1280x720 | normal | **15.0** | 66.7 | raster+fragment ~40 ms, compute post-processing ~9 ms |
| 1280x720 | fast | **24.2** | 41.3 | raster+fragment 15.7, compute 10.4 |
| 1920x1080 | normal | **8.1** | 123.3 | raster+fragment 88.5, compute 10.9 |
| 1920x1080 | fast | **15.9** | 62.9 | raster+fragment 25.8, compute 10.7 |

What it took (all in `icd/`): compute pipelines with real workgroup shared memory and
barriers (batches run as fibers), multiple subpasses and input attachments, texel
buffers, stencil, depth bias; a SPIR-V compiler that emits C++ over JSNOW's 8-lane SIMD
layer (`src/simd.hpp`, so the same generator targets AVX2 and NEON), builds it with the
system compiler and caches the shared object; then removing the driver overhead that the
compiler exposed (per-draw allocations, per-instance passes, scalar sampling and
addressing). It also fixed a long-standing bug: D24 depth buffers cleared to 1.0 were
stored as 0.

Vulkan examples: see `docs_vk_examples_interp.md` (interpreter), `docs_vk_examples_jit.md`
(first JIT) and `docs_vk_examples_final.md` (end of Phase F); the table is in PROGRESS.md.

**Next bottleneck:** fixed-function per-block work in the rasterizer (depth/stencil,
blending, varyings — the generated shader itself is only ~6 % of a frame), then vkQuake's
compute post-processing (~10 ms, scalar image load/store helpers), then shader compile
latency (0.3-1 s per shader through the system compiler).

**Next three things blocking GTA V through DXVK:**
1. Vulkan 1.3 and DXVK's required features (timeline semaphores, sync2, dynamic rendering,
   extended dynamic state, robustness2, transform feedback, depth-clip, descriptor
   indexing, and D3D11 FL11 device features). JSNOW is Vulkan 1.1.
2. Pipeline stages and formats GTA V uses: geometry + tessellation shaders, stream output,
   real MSAA, BC1-7 texture decompression, sRGB targets, cube/3D/array textures, gather.
3. Throughput and compile latency: ~10-30x vkQuake's per-pixel work and thousands of
   pipelines → estimated 1-3 FPS at 720p on this VM even with everything implemented;
   needs in-process codegen (LLVM ORC or direct emitter), a fused per-block pipeline,
   and many more cores.
