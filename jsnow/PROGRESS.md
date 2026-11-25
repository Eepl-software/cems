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

## Decisions log
- A1: `--fast` = half resolution + reuse (best trade-off found in session 1).
  `--bench-fast` benchmarks baseline and fast only.

## Done
- Session 1: tiled AVX2 rasterizer, half/checker/reuse tricks, benchmark harness.
- A1: `--fast`.

## Next
- A2 textures (2048², mips, bilinear, SIMD sampling).
