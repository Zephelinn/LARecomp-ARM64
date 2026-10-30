# LARecomp on Android (arm64-v8a)

Status: playable. Menus, free roam and races run on an AYN Odin 3 (Snapdragon 8 Elite, Adreno 830) at 30-40 fps
while driving, with a controller. Known issues: red and green lines on car body edges facing the sun (also seen on
PC), and no touch controls.

## How it fits together

| piece | Android |
| --- | --- |
| CPU | the same generated C++ as on PC, compiled for arm64; vector code goes through SIMDe to NEON |
| window, input, audio | SDL3 (Android video driver, AAudio, game controllers), statically linked into the SDK runtime |
| GPU | the SDK's Xenos plugin (`librexgpu-xenos*.so`, Xenia's GPU emulation) on Vulkan, `VK_KHR_android_surface` |
| app | SDL3's `SDLActivity`; `libmain.so` is LARecomp, its entry point `SDL_main` (the SDK's `windowed_app_main_sdl.cpp`) |
| not built | the Native Graphics Runtime and the probe (`src/native_gfx`, `src/native_probe`: D3D12 only, off by default on PC too; `src/native_gfx/native_gfx_off.cpp` stands in), the Plume renderer (`LARECOMP_GPU`, off outside Windows), file dialogs |

## Files on the device

The app's files directory, `/sdcard/Android/data/org.larecomp.android/files`, is the runtime's executable folder
and user folder:

| path | what |
| --- | --- |
| `game/` | `default.xex` and the `xarchive_*.rpf` archives (found by the usual walk: `game/` next to the executable) |
| `log.txt` | stdout and stderr of the current start, including the crash report of a fatal signal; `log.prev.txt` is the previous start's |
| `logs/larecomp_NNN.log` | LARecomp's own log |
| `args.txt` | optional, one per line: `--<setting>=<value>` (e.g. `--log_level=debug`) or `NAME=value` environment variables |
| `larecomp.toml` | the settings the pause menu saves |
| `larecomp/cache/` | translated shaders and the driver pipeline cache (`vulkan_pipeline_cache.bin`) |

There is no ISO install wizard on Android: extract the ISO on a PC and copy the files to `game/`.

## Changes in this fork (tagged `// android:`)

- `CMakeLists.txt`: `libmain.so` (shared library) on Android; the native_gfx/probe sources only on Windows.
- `src/native_gfx/native_gfx_off.cpp`: the entry points the app calls when native_gfx is not built.
- `src/larecomp_app.h`: the D3D12 headers only on Windows.
- `src/isoinstaller`, `src/saveporter`: no GTK dialog on Android (the macOS branch).
- `src/crash_handler.cpp`, `src/spdlog/crash_handler.cpp`: `ExeDir()` is the files directory.
- `src/mc_engine/hooks/timing_log.cpp`, `music/custom_music.cpp`, `modloader/modloader.cpp`,
  `modloader/modsbrowser/mod_download.cpp`: POSIX equivalents (`localtime_r`, `std::thread`, `<netinet/in.h>`,
  libc++'s 128-bit file-clock count).
- `src/larecomp_app.h`: Android defaults (dynamic rendering, MSAA, submission per frame, frame-end page reset off;
  see Performance work).
- `src/mc_engine/hooks/frame_timing.cpp`: the fence wait naps instead of spinning on Android.
- `src/mc_engine/wheel/wheel_input.cpp`: no wheel thread (it would take the controllers from the game's SDL).
- `src/mc_engine/ui/gamepad.cpp`: the menu pad layer only reads the shared SDL (disabling its gamepad events left
  the game without a controller).
- `src/mc_engine/pause_menu.cpp`: values of settings this build does not register are quoted
  (`graphics_backend = auto` made the whole `larecomp.toml` fail to load).
- `android/`: the APK manifest, the activity, the build scripts and the ReXGlue SDK patch.

The SDK needs its own Android changes (`android/rexglue-sdk-0.10.0-android.patch`): CMake for Android, the
ANativeWindow surface, `SDL_main`, an AArch64 fiber switch (bionic has no `swapcontext`), no robust mutexes,
`clock_cast` fallbacks, the files directory as executable/user folder, the GPU plugin loaded by name, and a crash
report for faults no handler claims (the POSIX handler used to return into the faulting instruction forever).

## Performance work (measured on an AYN Odin 3, Snapdragon 8 Elite, Adreno 830)

The first build ran 3D scenes at 5 to 9 fps. Profiles (`simpleperf`, the app is `profileable`) showed:

| finding | change | where |
| --- | --- | --- |
| Every guest write to a GPU-watched page parsed all of `/proc/self/maps` (thousands of lines in an app) to recheck protection: 80% of the guest render thread | skip that recheck on Linux; the access-violation callback decides from the heap's own state | SDK `mmio_handler.cpp` |
| Qualcomm's driver allocates on every `vkCmdBeginRendering`: 26% of the command processor | `vulkan_dynamic_rendering=false` on Android (measured 5 to 11 fps) | `larecomp_app.h` |
| Texture/sampler descriptor sets rewritten on every draw | reused when unchanged (`vulkan_reuse_texture_descriptors`) | SDK `command_processor.cpp` |
| A command pool reset per guest primary buffer | one submission per frame on Android | `larecomp_app.h` |
| 4x MSAA multiplies the render target load/store traffic of a tiled GPU | `disable_msaa=true` on Android | `larecomp_app.h` |
| Shader registers as one function-local array, which mobile compilers keep in scratch memory | one variable per register when the shader has no dynamic addressing (`spirv_registers_as_variables`) | SDK `spirv_translator.cpp` |
| Busy threads: the fence wait (no yield outside Windows), the timer queue (yield loop that read a `/sys` file per spin), the identity worker (wait deadline never advanced) | naps, a condition variable, a moving deadline | `frame_timing.cpp`, SDK `timer_queue.cpp`, `identity_client.cpp` |
| Allocator returning memory to the kernel per draw | `mallopt(M_DECAY_TIME, 1)` | SDK `main_android.cpp` |
| Build | Release, `-O3`, `-march=armv8.2-a` | build scripts |
| About 1,000 guest memory uploads per frame each ended the open render pass (`VulkanSharedMemory::UploadRanges`), so a frame was ~1,250 render passes; each pass costs a tile load and store on Adreno. Measured with `vulkan_gpu_profile`: 58 ms of GPU time per frame, 42 ms of it in guest passes | uploads that no earlier draw of the open pass reads are recorded before that pass (`vulkan_hoist_shared_memory_uploads`), with one barrier pair per pass. Measured while driving: 1,250 -> 130 passes per frame, GPU 58 -> 34.5 ms per frame, 17 -> 29-30 fps | SDK `shared_memory.cpp`, `deferred_command_buffer.cpp` |
| Texture loads (~90 per frame) ended the open render pass for their dispatches and copies, and again for the transition to sampling | a draw's texture requests run before the open pass with their barriers (`vulkan_hoist_texture_loads`); given up (moved back after a real pass end) when an upload in it overlaps what earlier draws of the pass read; not done in passes with memexport draws. Measured: guest passes per frame 128 -> 62, GPU 34.5 -> 29.5 ms per frame | SDK `command_processor.cpp`, `deferred_command_buffer.cpp`, `shared_memory.cpp` |
| No driver pipeline cache: every launch compiled every pipeline again in Adreno's compiler, and new pipelines while driving were 100+ ms hitches | `VkPipelineCache` saved to `larecomp/cache/vulkan_pipeline_cache.bin` (8 MB after a minute of driving) by the shader storage thread every 10 s after new pipelines and at shutdown, checked against the device and driver (`vulkan_pipeline_cache_file`). Measured on the second launch: 100+ ms frames in a minute of driving 39 -> 4, 50+ ms frames 43 -> 21 | SDK `pipeline_cache.cpp` |
| Render passes began with the whole EDRAM-sized render target (1280x2048 for 720p) as the render area | render area = bounds of the pass's scissors and clear rects (`vulkan_trim_render_area`); no measurable change on its own | SDK `deferred_command_buffer.cpp` |

GPU profiling: `--vulkan_gpu_profile=true` in `args.txt` writes `gpuprof:` lines to `log.txt` every 3 seconds: GPU
milliseconds per submission split into guest render passes, render target cache passes (EDRAM transfers), dispatches
and the rest; the heaviest passes; and the call sites that ended render passes (library offsets of
`librexgpu-xenos.so`, for `llvm-symbolizer`). It uses timestamp queries only. Qualcomm's own Perfetto render stage
producer (`debug.graphics.gpu.profiler.perfetto 1`) crashed the game in `vulkan.adreno.so` when a trace started.

Overrides, one per line in `args.txt`: `MCLA_VK_DYNAMIC_RENDERING=1`, `MCLA_MSAA=1`, `MCLA_VK_SUBMIT_EACH_BUFFER=1`,
`--vulkan_reuse_texture_descriptors=false`, `--spirv_registers_as_variables=false`,
`--vulkan_hoist_shared_memory_uploads=false`, `--vulkan_hoist_texture_loads=false`, `--vulkan_trim_render_area=false`,
`--vulkan_pipeline_cache_file=false`. Even frame pacing below 60 fps: FPS LIMIT 30 in the pause menu (or
`--fps_limit=30`); measured: every frame 33.3 ms in seconds without hitches, against 25/36 ms alternation uncapped.
Thermals matter: the chip reached thermal status 3 within a minute of these tests; the Odin's fan/performance
mode changes results.

## Building

Linux x86-64 host, NDK r30, Android SDK build-tools 35 and platform 35 (`android.jar`), JDK 17, the prebuilt
linux-amd64 ReXGlue SDK 0.10.0 (for `rexglue codegen`) and your own `default.xex`. The scripts in `android/scripts/`
work in one folder, `LARECOMP_ANDROID_ROOT` (default `/bo1/larecomp`):

| path | what |
| --- | --- |
| `sdk/` | `github.com/rexglue/rexglue-sdk` at v0.10.0 with `android/rexglue-sdk-0.10.0-android.patch` applied (`git apply`) |
| `LARecomp/` | this repository |
| `sdk-host/` | the prebuilt linux-amd64 ReXGlue SDK; `REXGLUE_HOST_TOOL` points at its `rexglue` for codegen |
| `icon/` | optional launcher icon layers (`icon-192.png`, `icon-bg-432.png`, `icon-fg-432.png`; `ICON_DIR`) |

`ANDROID_NDK` is the NDK folder; `ANDROID_TOOLS` holds the Android SDK (`sdk/`) and a `debug.keystore`.

```
BUILD_TYPE=Release android/scripts/build-sdk-android.sh             # SDK runtime + GPU plugin
BUILD_TYPE=Release android/scripts/build-larecomp-android.sh all    # codegen + libmain.so
BUILD_TYPE=Release android/scripts/build-apk.sh                     # out/larecomp-release.apk
```

`RELEASE_KEYSTORE` and `RELEASE_PASS_FILE` sign with a release key instead of the debug key.
`android/scripts/xiso_extract.py <iso> <folder>` extracts the game files from the disc image.

## Not done

- Touch controls and an in-app import of the game files.
- The red and green car-edge highlights (see Status).
