#!/bin/bash
# build-sdk-android.sh: cross-build the ReXGlue SDK runtime for Android arm64-v8a with NDK r30.
# Paths: see documentation/ANDROID.md (Building). Low load: JOBS<=3, nice, ionice.
# Usage: build-sdk-android.sh [configure|build|install] (default: configure + build + install)
set -o pipefail
L=${LARECOMP_ANDROID_ROOT:-/bo1/larecomp}
NDK=${ANDROID_NDK:-/bo1/ndk/ndk-r30/android-ndk-r30}
SRC=$L/sdk
SUF=; [ "${BUILD_TYPE:-RelWithDebInfo}" = RelWithDebInfo ] || SUF=-$(echo $BUILD_TYPE | tr A-Z a-z)  # per build type folders
B=$L/build/sdk-android$SUF
I=$L/install/sdk-android$SUF
JOBS=${JOBS:-3}
BT=${BUILD_TYPE:-RelWithDebInfo}
step=${1:-all}
mkdir -p $B $I

if [ "$step" = all ] || [ "$step" = configure ]; then
  # Release: armv8.2-a (every target SoC has it: inline LSE atomics and more); the NDK's other flags stay
  ARCH=()
  [ "$BT" = Release ] && ARCH=("-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -march=armv8.2-a"
    "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -march=armv8.2-a" "-DREXGLUE_ARM64_MARCH=armv8.2-a")
  nice -n 19 cmake -S $SRC -B $B -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-30 -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=$BT -DCMAKE_INSTALL_PREFIX=$I \
    -DREXGLUE_BUILD_TESTS=OFF -DREXGLUE_ENABLE_TRACY=OFF \
    -DREXGLUE_USE_VULKAN=ON \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF \
    "${ARCH[@]}" \
    $EXTRA_CMAKE 2>&1 | tee $B/configure.log | grep -E "CMake (Error|Warning)|error|Configuring done|Generating done" | head -40
  [ "${PIPESTATUS[0]}" = 0 ] || exit 1
fi
if [ "$step" = all ] || [ "$step" = build ]; then
  nice -n 19 ionice -c3 ninja -C $B -j $JOBS -k 0 ${TARGETS} > $B/build.log 2>&1; rc=$?
  echo "ninja exit=$rc errors: $(grep -c 'error:' $B/build.log) failed: $(grep -c '^FAILED' $B/build.log)"
  grep -E 'error:' $B/build.log | sort | uniq -c | sort -rn | head -40
  [ $rc = 0 ] || exit 1
fi
if [ "$step" = all ] || [ "$step" = install ]; then
  nice -n 19 cmake --install $B > $B/install.log 2>&1 && echo "installed to $I" || { tail -20 $B/install.log; exit 1; }
fi
