#!/bin/bash
# build-larecomp-android.sh: build LARecomp as libmain.so for Android arm64-v8a against the SDK built by
# build-sdk-android.sh. Runs inside the bo1-x64 container. Low load: JOBS<=3, nice, ionice.
# Codegen runs with the host (linux-amd64) rexglue. Without the game's default.xex (assets/default.xex, see
# larecomp_manifest.toml) set SKIP_CODEGEN=1: the hand-written sources compile, the link is expected to fail.
# Usage: build-larecomp-android.sh [configure|build|all]
set -o pipefail
L=${LARECOMP_ANDROID_ROOT:-/bo1/larecomp}
NDK=${ANDROID_NDK:-/bo1/ndk/ndk-r30/android-ndk-r30}
SRC=$L/LARecomp
SUF=; [ "${BUILD_TYPE:-RelWithDebInfo}" = RelWithDebInfo ] || SUF=-$(echo $BUILD_TYPE | tr A-Z a-z)  # per build type folders
B=$L/build/larecomp-android$SUF
JOBS=${JOBS:-3}
BT=${BUILD_TYPE:-RelWithDebInfo}
step=${1:-all}
mkdir -p $B

if [ "$step" = all ] || [ "$step" = configure ]; then
  [ -f $SRC/generated/rexglue.cmake ] || { echo "no generated/rexglue.cmake (render_rexglue_cmake.py)"; exit 1; }
  # Release: armv8.2-a (every target SoC has it); the NDK's other flags stay
  ARCH=()
  [ "$BT" = Release ] && ARCH=("-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -march=armv8.2-a"
    "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -march=armv8.2-a" "-DREXGLUE_ARM64_MARCH=armv8.2-a")
  nice -n 19 cmake -S $SRC -B $B -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-30 -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=$BT \
    -DCMAKE_PREFIX_PATH=$L/install/sdk-android$SUF -DCMAKE_FIND_ROOT_PATH=$L/install/sdk-android$SUF \
    -DREXGLUE_HOST_TOOL=$L/sdk-host/linux-amd64/bin/rexglue \
    -DREXGLUE_SKIP_CODEGEN=${SKIP_CODEGEN:-0} \
    "${ARCH[@]}" \
    $EXTRA_CMAKE 2>&1 | tee $B/configure.log | grep -E "CMake (Error|Warning)|error|Configuring done|Generating done" | head -40
  [ "${PIPESTATUS[0]}" = 0 ] || { grep -A10 "CMake Error" $B/configure.log | head -40; exit 1; }
fi
if [ "$step" = all ] || [ "$step" = build ]; then
  nice -n 19 ionice -c3 ninja -C $B -j $JOBS -k 0 ${TARGETS:-larecomp} > $B/build.log 2>&1; rc=$?
  echo "ninja exit=$rc errors: $(grep -c 'error:' $B/build.log) failed: $(grep -c '^FAILED' $B/build.log)"
  grep -E 'error:' $B/build.log | sed 's|/bo1/larecomp/||' | sort | uniq -c | sort -rn | head -60
  [ $rc = 0 ] || exit 1
fi
