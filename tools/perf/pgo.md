# Profile-guided optimisation (Android)

clang lays the code out, inlines and orders branches from what a real run
did. The profile describes the game's own paths, not the phone, so one
taken on any arm64 phone serves every phone.

1. The counting build, in a build folder of its own:

       BUILD_DIR=$PWD/build-android-pgogen \
         tools/android/build-apk.sh -DBO3_RELEASE=ON -DBO3_PGO_GENERATE=ON

   It writes `<the app's files>/pgo.profraw` every 30 s (core/main.c).

2. Install it and play, or let the AI race (a few minutes; menus, a race,
   a crash):

       ADB="adb -s <serial>" SECS=300 tools/perf/android_race_power.sh runs/pgo

3. Pull and merge (the NDK's llvm-profdata, the same clang version as the
   build):

       adb pull /sdcard/Android/data/com.stevencol.takedawn/files/pgo.profraw
       $NDK/toolchains/llvm/prebuilt/<host>/bin/llvm-profdata merge -o tools/perf/takedawn.profdata pgo.profraw

4. The optimised build:

       tools/android/build-apk.sh -DBO3_RELEASE=ON -DBO3_PGO_USE=$PWD/tools/perf/takedawn.profdata

A profile that no longer matches the code (after a regen or a toolkit
change) only loses what it knew about the functions that changed; the build
says so and goes on (-Wno-profile-instr-out-of-date). Take a new one now and
then.
