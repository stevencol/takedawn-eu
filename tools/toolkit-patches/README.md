# Toolkit patches

This fork builds on the xboxrecomp toolkit at commit `e3756d1` (branch
`takedawn`, xenophobentx/xboxrecomp). It has no fork of that repository, so
its changes to the toolkit are kept here as patches. They go on a clean
checkout beside this one (`../xboxrecomp`) before a build:

    git -C ../xboxrecomp checkout e3756d1
    git -C ../xboxrecomp apply ../takedawn/tools/toolkit-patches/xboxrecomp-android-perf.patch

then `tools/release/gen.sh` (one patch changes the template the generated
code includes) and the platform's build script.

## xboxrecomp-android-perf.patch

Android, measured with `tools/perf/android_race_power.sh` (an AI race,
2 minutes) on a Poco with a Snapdragon 8 Elite and a Galaxy A34 with a
Dimensity 1080:

- **The guest registers in one thread-local** (`templates/runtime/recomp_cpu_tls.h`).
  The game is a library the activity dlopens, so its TLS is dynamic and every
  register a lifted function touched was a TLS descriptor call: 21 % of the
  guest thread's time. Now a function resolves one block. Android only; the
  names stay (`g_eax` is a macro).
- **The guest's core.** The title's thread took "a core of the next kind",
  which on a 2 big + 6 little chip is a little Cortex-A55. Now it takes the
  other core of the fastest kind when there is one
  (`recomp_android_guest_cpu`); the other threads are left to the scheduler
  when the two pinned threads hold every big core.
- **Thermal cap on the vblank spin** (`android_perf.c`, `kernel_pacing.c`):
  the system's thermal headroom forecast limits the spin before each frame as
  the phone nears throttling (`RECOMP_ANDROID_THERMAL=0`: off).
- **Swapchain at the game's own rows** (480 at the render scale) instead of
  the panel's (`RECOMP_ANDROID_SWAPCHAIN_HEIGHT=0`: the panel's).
- **Smaller ring buffers on Android**, from what a race used; a phone's
  driver commits all of them (172 MB on the A34).
- **A ring use line** in the log every 1800 frames (`[vulkan] rings ...`).
- **The APU's voice records translated once** (`apu_vp.c`), dropped when the
  physical map moves (`xbox_PhysicalMapGen`): the translations were a quarter
  of the APU thread, now about half that.
- The black screen on returning to the app: no surface is made while the
  window is minimised or has no native window (`fb_present_vulkan.c`).

Results with these and the game's own changes (FIFO, no spin, PGO;
frames over 20 ms; the hottest CPU zone): the Poco from 55 fps, 14.9 %
and 75 °C to 60 fps, 1-3 % and 61-67 °C, at 18 % less CPU with the
profile; the A34 from 34.6 fps and 96 % to 59 fps and 4-5 %, the chip at
37-40 °C. The game's memory: the Poco from 294 to 255 MB, the A34 from 536
to 432 MB.
