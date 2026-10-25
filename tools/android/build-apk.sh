#!/usr/bin/env bash
# Build the Android app (arm64-v8a): libmain.so with the NDK, then the APK
# with the Android SDK's own tools, without Gradle (the steps are the ones
# Xerenge's scripts/build-android-apk.sh takes; the JDK only compiles SDL's
# activity and runs d8 and apksigner, so any JDK from 17 on will do).
# Run tools/android/fetch-deps.sh once first. docs/android.md has the rest.
#
#   tools/android/build-apk.sh [extra cmake -D options]
#
# Environment:
#   ANDROID_HOME       the SDK (default ~/android-sdk): build-tools, a platform
#   ANDROID_NDK_HOME   the NDK (default: the newest under $ANDROID_HOME/ndk)
#   ANDROID_API        minSdk, as given to fetch-deps.sh (default 33)
#   BO3_ANDROID_DEPS   the deps prefix (default ~/.cache/bo3-android-deps)
#   XBOXRECOMP_DIR     the toolkit checkout (default ../xboxrecomp-android or
#                      ../xboxrecomp next to the repo)
#   BUILD_DIR          default build-android; JOBS
#   BO3_KEYSTORE       the signing key (default ~/.android/bo3-debug.keystore,
#                      made on first use; the same key must sign every build
#                      or Android refuses the update)
#   BO3_ANDROID_TURNIP=0  leave the Turnip driver out of the APK; =mesa: the
#                      Mesa 26.2.4 build of fetch-deps.sh instead of the
#                      prebuilt A725 build (the default, BO-152)
#   DEBUGGABLE=1       mark the app debuggable (run-as, GPU profilers)
#   STRIP=0            keep libmain.so's symbol table and debug info
#   SIGN=0             stop at the aligned, unsigned APK
#                      (out/takedawn-android-arm64-unsigned.apk): a release is
#                      signed in a step of its own (tools/release/build-android.sh)
#   TAKEDAWN_ANDROID_BUILD  0..999, the last three digits of versionCode
#   BO3_ANDROID_GEN2   a second generated-code folder (another release's, made
#                      with BO3_GEN_DIR=... BO3_XBE=... regen.sh): the APK then
#                      holds both programs, libmain_pal.so and libmain_ntsc.so,
#                      and the app runs the one of the disc it finds
#                      (Region.java). Unset: the one libmain.so of before.
#   BO3_ANDROID_PKG_SUFFIX  e.g. .legacy: a second app beside the usual one
#                      (package com.stevencol.takedawn.legacy, its
#                      own data), out/takedawn-android-arm64-legacy.apk; with
#                      ANDROID_API=24 and its own BO3_ANDROID_DEPS and
#                      BUILD_DIR, the Android 7 build
#   BO3_LICENSES_DIR   the release's licence set (tools/release/common.sh
#                      copy_licenses); packed as assets/licenses/ with the
#                      texts of the Android-only parts (tools/android/licenses/,
#                      Mesa's Turnip and libadrenotools). The app's Licences
#                      page (LicensesActivity) shows them.
#   BO3_REQUIRE_LICENSES=1  fail unless that set is there and in the APK
#                      (tools/release/build-android.sh sets it)
# Output: out/takedawn-android-arm64.apk, signed with the development key. An
# APK signed with another key than the installed one is refused as an update:
# a development build and a release do not replace each other.
#
# versionName is VERSION's first line; versionCode is
# major * 10 000 000 + minor * 100 000 + patch * 1 000 + build (0..99), so
# every release is above the one before and a rebuild of one can be told
# apart; a pre-release (x.y.z-beta) is 900 below x.y.z (see below).
#
# The program's code (core/recomp/gen, from regen.sh) is compiled into
# libmain.so. The game data is not in the APK: the first start installs it
# from the player's own disc image (SetupActivity).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_HOME:-$HOME/android-sdk}"
# A Windows path (C:\...) from the environment: the shell's form, for the globs.
command -v cygpath >/dev/null 2>&1 && SDK="$(cygpath -u "$SDK")"
NDK="${ANDROID_NDK_HOME:-$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1)}"
command -v cygpath >/dev/null 2>&1 && [ -n "$NDK" ] && NDK="$(cygpath -m "$NDK")"
API="${ANDROID_API:-33}"
TARGET_API=34
ABI=arm64-v8a
D="${BO3_ANDROID_DEPS:-$HOME/.cache/bo3-android-deps}"
command -v cygpath >/dev/null 2>&1 && D="$(cygpath -m "$D")"
TK="${XBOXRECOMP_DIR:-}"
if [ -z "$TK" ]; then
  for c in "$HERE/../xboxrecomp-android" "$HERE/../xboxrecomp"; do [ -d "$c" ] && TK="$c" && break; done
fi
[ -d "$TK" ] || { echo "toolkit checkout not found; set XBOXRECOMP_DIR" >&2; exit 1; }
[ -f "$NDK/build/cmake/android.toolchain.cmake" ] || { echo "NDK not found (ANDROID_NDK_HOME)" >&2; exit 1; }
[ -f "$D/SDL2/lib/libSDL2.so" ] && [ -f "$D/glslang/lib/libglslang.a" ] || "$HERE/tools/android/fetch-deps.sh"
ls "$HERE"/core/recomp/gen/recomp_*.c >/dev/null 2>&1 || { echo "no generated C: run regen.sh first" >&2; exit 1; }
B="${BUILD_DIR:-$HERE/build-android}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"
HOST_TAG="$(ls "$NDK/toolchains/llvm/prebuilt" | head -1)"
SYSROOT="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/sysroot"
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
PLATFORM="$(ls -d "$SDK"/platforms/android-* | sort -V | tail -1)"
JAR="$PLATFORM/android.jar"
# On a Windows host (Git Bash) the native tools want C:/... paths, d8 and
# apksigner are .bat files, and there may be no zip.
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
D8="$BT/d8"; [ -f "$D8" ] || D8="$BT/d8.bat"
APKSIGNER="$BT/apksigner"; [ -f "$APKSIGNER" ] || APKSIGNER="$BT/apksigner.bat"
JAR="$(wp "$JAR")"

# A replacement GPU driver (docs/android.md, "The GPU driver"): libadrenotools
# when fetch-deps.sh built it, and a Turnip driver, unless BO3_ANDROID_TURNIP=0:
# the prebuilt A725 build (turnip-a725/, BO-152) by default, the Mesa release
# fetch-deps.sh built (turnip/) with BO3_ANDROID_TURNIP=mesa.
TD="$D/turnip-a725"
[ "${BO3_ANDROID_TURNIP:-1}" = mesa ] && TD="$D/turnip"
ADRENO=()
[ -f "$D/adrenotools/lib/libadrenotools.a" ] && ADRENO=(-DXBOXRECOMP_ANDROID_ADRENOTOOLS="$D/adrenotools")

# The release a generated-code folder is of: its region_map.h names a build
# (none: NTSC-U).
gen_suffix() {
  if grep -q 'BO3_BUILD_PAL_RETAIL' "$1/region_map.h" 2>/dev/null; then echo _pal; else echo _ntsc; fi
}
GEN1="$HERE/core/recomp/gen"
GEN2="${BO3_ANDROID_GEN2:-}"
SUF1=""; SUF2=""
if [ -n "$GEN2" ]; then
  [ -f "$GEN2/region_map.h" ] || { echo "BO3_ANDROID_GEN2: no region_map.h in $GEN2" >&2; exit 1; }
  SUF1="$(gen_suffix "$GEN1")"; SUF2="$(gen_suffix "$GEN2")"
  [ "$SUF1" != "$SUF2" ] || { echo "both generated trees are of the same release" >&2; exit 1; }
fi

native_build() {   # build dir, generated-code folder, library suffix
  cmake -S "$(wp "$HERE")" -B "$(wp "$1")" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$(wp "$NDK/build/cmake/android.toolchain.cmake")" \
  -DANDROID_ABI=$ABI -DANDROID_PLATFORM=android-$API -DANDROID_STL=c++_shared \
  -DXBOXRECOMP_DIR="$(wp "$TK")" \
  -DCMAKE_FIND_ROOT_PATH="$(wp "$D/SDL2");$(wp "$D/glslang")" \
  -DCMAKE_PREFIX_PATH="$(wp "$D/SDL2");$(wp "$D/glslang")" \
  -DVulkan_INCLUDE_DIR="$(wp "$SYSROOT/usr/include")" \
  -DVulkan_LIBRARY="$(wp "$SYSROOT/usr/lib/aarch64-linux-android/$API/libvulkan.so")" \
  -DBO3_BIN_DIR="$(wp "$1/lib")" -DBO3_GEN_DIR="$(wp "$2")" \
  ${3:+-DBO3_EXE_SUFFIX="$3"} \
  ${ADRENO[@]+"${ADRENO[@]}"} \
  "${@:4}"
  cmake --build "$1" --target burnout3 -j"$JOBS"
}
echo "== native (NDK $(basename "$NDK"), android-$API, $ABI)"
native_build "$B" "$GEN1" "$SUF1" "$@"
B2="$B-2"
[ -n "$GEN2" ] && native_build "$B2" "$GEN2" "$SUF2" "$@"

OUT="$B/apk"
rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex" "$OUT/pack/lib/$ABI" "$HERE/out"

echo "== resources and manifest ($(basename "$BT"), $(basename "$PLATFORM"))"
"$BT/aapt2" compile --dir "$HERE/adapters/android/res" -o "$OUT/res.zip"
VNAME="$(head -1 "$HERE/VERSION" | tr -d '[:space:]')"
[[ "$VNAME" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.]+)?$ ]] || { echo "VERSION: $VNAME is not major.minor.patch[-pre-release]" >&2; exit 1; }
VBUILD="${TAKEDAWN_ANDROID_BUILD:-0}"
[ "$VBUILD" -ge 0 ] && [ "$VBUILD" -le 99 ] || { echo "TAKEDAWN_ANDROID_BUILD: 0..99" >&2; exit 1; }
VCODE=$(( BASH_REMATCH[1] * 10000000 + BASH_REMATCH[2] * 100000 + BASH_REMATCH[3] * 1000 + VBUILD ))
# A pre-release (0.1.2-beta) is numbered after every build of the release
# before it and before every build of its own release: the patch before's
# code + 100 (0.1.2-beta: 101100 + build; 0.1.1 builds are 101000..101099,
# 0.1.2's 102000..102099). A patch-0 pre-release (0.2.0-beta) takes the
# minor before's last patch slot the same way.
if [ -n "${BASH_REMATCH[4]}" ]; then
    VCODE=$(( VCODE - 900 ))
fi
# The id the native library was built with (cmake/release_info.cmake picks the
# release's manifest): the installer writes it to its marker, and
# StartActivity compares the two, so they must be the same.
REL_H="$B/core/release/bo3_release.h"
MANIFEST_ID="$(sed -n 's/^#define BO3_MANIFEST_ID "\([0-9a-f]*\)".*/\1/p' "$REL_H" 2>/dev/null | head -1)"
[ -n "$MANIFEST_ID" ] || { echo "no BO3_MANIFEST_ID in $REL_H" >&2; exit 1; }
echo "   Takedawn $VNAME, versionCode $VCODE, disc manifest $MANIFEST_ID"
# The libraries and the manifests they were built with, in the order of the
# native builds: libmain alone, or main_pal and main_ntsc (Region.java).
LIBS_JAVA='"main"'; MANIFESTS_JAVA="\"$MANIFEST_ID\""
if [ -n "$GEN2" ]; then
  MANIFEST_ID2="$(sed -n 's/^#define BO3_MANIFEST_ID "\([0-9a-f]*\)".*/\1/p' "$B2/core/release/bo3_release.h" | head -1)"
  [ -n "$MANIFEST_ID2" ] || { echo "no BO3_MANIFEST_ID in the second build" >&2; exit 1; }
  LIBS_JAVA="\"main$SUF1\", \"main$SUF2\""
  MANIFESTS_JAVA="\"$MANIFEST_ID\", \"$MANIFEST_ID2\""
  echo "   and the second release: main$SUF2, disc manifest $MANIFEST_ID2"
fi
mkdir -p "$OUT/gen/com/stevencol/takedawn"
cat > "$OUT/gen/com/stevencol/takedawn/BuildInfo.java" <<JAVA
package com.stevencol.takedawn;

/** Made by tools/android/build-apk.sh. */
final class BuildInfo {
    static final String VERSION = "$VNAME";
    /** The disc manifest the native library was built with (the installer's marker names it). */
    static final String MANIFEST_ID = "$MANIFEST_ID";
    /** The native libraries (libmain, or one per release) and each one's disc manifest. */
    static final String[] LIBS = { $LIBS_JAVA };
    static final String[] MANIFESTS = { $MANIFESTS_JAVA };
    /** The second app (BO3_ANDROID_PKG_SUFFIX=.legacy), for devices without Vulkan 1.3. */
    static final boolean LEGACY = $([ "${BO3_ANDROID_PKG_SUFFIX:-}" = .legacy ] && echo true || echo false);
}
JAVA

# The licence texts (assets/licenses/): the release set, then what only this
# APK has. A copy of this program carries them with it.
AL="$OUT/assets/licenses"
mkdir -p "$AL"
if [ -n "${BO3_LICENSES_DIR:-}" ] && [ -d "$BO3_LICENSES_DIR" ]; then
  cp "$BO3_LICENSES_DIR"/* "$AL/"
elif [ "${BO3_REQUIRE_LICENSES:-0}" = 1 ]; then
  echo "BO3_LICENSES_DIR ($BO3_LICENSES_DIR) is not a folder: a release APK carries the licences" >&2; exit 1
else
  echo "   NO release licence set (BO3_LICENSES_DIR): a development build; Licences shows the Android parts only"
fi
if [ ${#ADRENO[@]} -gt 0 ]; then
  cp "$HERE/tools/android/licenses/libadrenotools-BSD-2-Clause.txt" \
     "$HERE/tools/android/licenses/linkernsbypass-BSD-2-Clause.txt" "$AL/"
  if [ "${BO3_ANDROID_TURNIP:-1}" != 0 ] && [ -f "$TD/libvulkan_freedreno.so" ]; then
    cp "$HERE"/tools/android/licenses/Mesa-*.txt "$AL/"
    # Which Mesa, from where, with which change: the source of the driver.
    cp "$TD/SOURCE.txt" "$AL/Mesa-Turnip-SOURCE.txt"
    if [ "$TD" = "$D/turnip" ]; then
      for p in "$HERE"/tools/android/patches/*.patch; do
        [ -f "$p" ] && cp "$p" "$AL/Mesa-Turnip-$(basename "$p" .patch)-patch.txt"
      done
    fi
  fi
fi
if [ "${BO3_REQUIRE_LICENSES:-0}" = 1 ]; then
  for f in THIRD_PARTY.txt SOURCE.txt takedawn-LICENSE.txt xboxrecomp-LGPL-2.1.txt xboxrecomp-NOTICE.txt \
           DearImGui-MIT.txt SDL2-Zlib.txt glslang.txt LLVM-Apache-2.0-with-exceptions.txt \
           libadrenotools-BSD-2-Clause.txt Mesa-license.txt Mesa-MIT.txt Mesa-Turnip-SOURCE.txt; do
    [ -s "$AL/$f" ] || { echo "licence file $f is missing from the APK's assets" >&2; exit 1; }
  done
fi
echo "   $(ls "$AL" | wc -l | tr -d ' ') licence files in assets/licenses"

"$BT/aapt2" link -o "$OUT/base.apk" -I "$JAR" --manifest "$HERE/adapters/android/AndroidManifest.xml" \
  --java "$OUT/gen" ${DEBUGGABLE:+--debug-mode} --version-code "$VCODE" --version-name "$VNAME" \
  --min-sdk-version "$API" --target-sdk-version "$TARGET_API" -A "$OUT/assets" \
  ${BO3_ANDROID_PKG_SUFFIX:+--rename-manifest-package "com.stevencol.takedawn$BO3_ANDROID_PKG_SUFFIX"} \
  "$OUT/res.zip"

echo "== java (SDL's activity, the start and game activities)"
find "$D/SDL2/java" "$HERE/adapters/android/java" "$OUT/gen" -name '*.java' \
  | while read -r f; do wp "$f"; done > "$OUT/sources.txt"
javac -nowarn -Xlint:none -source 17 -target 17 -encoding UTF-8 \
  -classpath "$JAR" -d "$(wp "$OUT/classes")" @"$(wp "$OUT/sources.txt")"
find "$OUT/classes" -name '*.class' | while read -r f; do wp "$f"; done > "$OUT/classes.txt"
[ -s "$OUT/classes.txt" ] || { echo "javac produced nothing" >&2; exit 1; }
"$D8" --release --min-api "$API" --lib "$JAR" --output "$(wp "$OUT/dex")" @"$(wp "$OUT/classes.txt")"

echo "== native libraries"
cp "$B/lib/libmain$SUF1.so" "$D/SDL2/lib/libSDL2.so" \
   "$SYSROOT/usr/lib/aarch64-linux-android/libc++_shared.so" "$OUT/pack/lib/$ABI/"
[ -n "$GEN2" ] && cp "$B2/lib/libmain$SUF2.so" "$OUT/pack/lib/$ABI/"
if [ ${#ADRENO[@]} -gt 0 ]; then
  # libadrenotools opens its hooks from the app's native library directory.
  cp "$D/adrenotools/lib/libhook_impl.so" "$D/adrenotools/lib/libmain_hook.so" \
     "$D/adrenotools/lib/libfile_redirect_hook.so" "$D/adrenotools/lib/libgsl_alloc_hook.so" \
     "$OUT/pack/lib/$ABI/"
  if [ "${BO3_ANDROID_TURNIP:-1}" != 0 ] && [ -f "$TD/libvulkan_freedreno.so" ]; then
    cp "$TD/libvulkan_freedreno.so" "$OUT/pack/lib/$ABI/"
    echo "   with $(head -1 "$TD/SOURCE.txt")"
  fi
fi
if [ "${STRIP:-1}" != 0 ]; then
  # The dynamic symbol table stays: the crash report names sub_XXXXXXXX
  # from it (dladdr).
  # The Turnip driver goes in as it is (the prebuilt one is checked by its
  # sha256; the Mesa build is stripped already).
  for so in "$OUT/pack/lib/$ABI/"*.so; do
    [ "$(basename "$so")" = libvulkan_freedreno.so ] && continue
    "$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/llvm-strip" --strip-unneeded "$so"
  done
fi

echo "== packing"
cp "$OUT/base.apk" "$OUT/unaligned.apk"
cp "$OUT/dex/classes.dex" "$OUT/pack/"
if command -v zip >/dev/null 2>&1; then
  (cd "$OUT/pack" && zip -q -r "$OUT/unaligned.apk" classes.dex lib)
else
  PY=python3; command -v py >/dev/null 2>&1 && PY="py -3"
  (cd "$OUT/pack" && $PY -c '
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "a", zipfile.ZIP_DEFLATED) as z:
    for top in ("classes.dex", "lib"):
        for dp, _, fs in os.walk(top) if os.path.isdir(top) else [("", None, [top])]:
            for f in sorted(fs):
                p = os.path.join(dp, f)
                z.write(p, p.replace(os.sep, "/"))
' "$(wp "$OUT/unaligned.apk")")
fi
"$BT/zipalign" -f 4 "$OUT/unaligned.apk" "$OUT/aligned.apk"

if [ "${SIGN:-1}" = 0 ]; then
  APK="$HERE/out/takedawn-android-arm64-unsigned.apk"
  cp "$OUT/aligned.apk" "$APK"
  ls -l "$APK"
  exit 0
fi
KS="${BO3_KEYSTORE:-$HOME/.android/bo3-debug.keystore}"
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
    -alias bo3 -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=burnout3 debug" >/dev/null
fi
APK="$HERE/out/takedawn-android-arm64${BO3_ANDROID_PKG_SUFFIX:+-${BO3_ANDROID_PKG_SUFFIX#.}}.apk"
"$APKSIGNER" sign --ks "$(wp "$KS")" --ks-pass pass:android --key-pass pass:android \
  --out "$(wp "$APK")" "$(wp "$OUT/aligned.apk")"
ls -l "$APK"
