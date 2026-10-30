#!/bin/bash
# build-apk.sh: package LARecomp for Android as /bo1/larecomp/out/larecomp-debug.apk, without Gradle (as the BO1
# port's build-apk.sh): javac + d8 for SDL3's Java side and LarecompActivity, aapt2 for the manifest, zip for the
# native libraries, zipalign (16 KB) and apksigner with the BO1 port's debug key. Runs inside the bo1-x64 container.
# No game data goes into the package.
set -o pipefail
L=${LARECOMP_ANDROID_ROOT:-/bo1/larecomp}
A=${ANDROID_TOOLS:-/bo1/android}
SDK=$A/sdk; BT=$SDK/build-tools/35.0.0; JAR=$SDK/platforms/android-35/android.jar
NDK=${ANDROID_NDK:-/bo1/ndk/ndk-r30/android-ndk-r30}/toolchains/llvm/prebuilt/linux-x86_64
SRC=${ANDROID_PACKAGING:-$L/LARecomp/android}
SDLJ=$L/sdk/thirdparty/sdl3/android-project/app/src/main/java
SUF=; [ "${BUILD_TYPE:-RelWithDebInfo}" = RelWithDebInfo ] || SUF=-$(echo $BUILD_TYPE | tr A-Z a-z)  # per build type folders
LIBMAIN=${LIBMAIN:-$L/build/larecomp-android$SUF/libmain.so}
SDKLIB=$L/install/sdk-android$SUF/lib
BT_NAME=${BUILD_TYPE:-RelWithDebInfo}
case $BT_NAME in Debug) POST=d;; RelWithDebInfo) POST=rd;; *) POST=;; esac
W=$L/apk-work; OUT=$L/out
rm -rf $W; mkdir -p $W/classes $W/dex $W/gen/org/larecomp/android $W/pkg/lib/arm64-v8a $OUT

# the runtime's library name depends on the build type (CMAKE_<CONFIG>_POSTFIX)
cat > $W/gen/org/larecomp/android/BuildConfigNames.java <<EOF
package org.larecomp.android;
final class BuildConfigNames {
    static final String RUNTIME = "rexruntime$POST";
}
EOF
find $SDLJ $SRC/java $W/gen -name "*.java" > $W/sources.txt
javac -nowarn -source 8 -target 8 -bootclasspath $JAR -d $W/classes @$W/sources.txt 2> $W/javac.log \
  || { grep -v "^warning\|^Note" $W/javac.log | head -20; exit 1; }
$BT/d8 --release --min-api 30 --lib $JAR --output $W/dex $(find $W/classes -name "*.class") > $W/d8.log 2>&1 || { tail -20 $W/d8.log; exit 1; }

mkdir -p $W/assets/licenses
cp $L/sdk/LICENSE $W/assets/licenses/rexglue-sdk.txt
cp $L/sdk/thirdparty/sdl3/LICENSE.txt $W/assets/licenses/sdl3.txt
# launcher icon (make_icon.py; game art, so supplied through ICON_DIR, never in the repository)
ICON_DIR=${ICON_DIR:-$L/icon}
MANIFEST=$SRC/AndroidManifest.xml; RES=""
if [ -f $ICON_DIR/icon-192.png ] && [ -f $ICON_DIR/icon-bg-432.png ] && [ -f $ICON_DIR/icon-fg-432.png ]; then
  mkdir -p $W/res/mipmap-xxxhdpi $W/res/mipmap-anydpi-v26
  cp $ICON_DIR/icon-192.png $W/res/mipmap-xxxhdpi/ic_launcher.png
  cp $ICON_DIR/icon-bg-432.png $W/res/mipmap-xxxhdpi/ic_launcher_background.png
  cp $ICON_DIR/icon-fg-432.png $W/res/mipmap-xxxhdpi/ic_launcher_foreground.png
  cat > $W/res/mipmap-anydpi-v26/ic_launcher.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
EOF
  $BT/aapt2 compile --dir $W/res -o $W/res.zip > $W/aapt2-compile.log 2>&1 || { tail -20 $W/aapt2-compile.log; exit 1; }
  sed 's#<application#<application android:icon="@mipmap/ic_launcher"#' $SRC/AndroidManifest.xml > $W/AndroidManifest.xml
  MANIFEST=$W/AndroidManifest.xml; RES=$W/res.zip
fi
$BT/aapt2 link -o $W/base.apk --manifest $MANIFEST -I $JAR $RES -A $W/assets > $W/aapt2.log 2>&1 || { tail -20 $W/aapt2.log; exit 1; }

# native libraries, stripped (the unstripped copies stay in the build directories for symbols)
for f in $LIBMAIN $SDKLIB/librexruntime$POST.so $SDKLIB/librexgpu-xenos$POST.so \
         $NDK/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so; do
  [ -f $f ] || { echo "missing $f"; exit 1; }
  $NDK/bin/llvm-strip --strip-unneeded -o $W/pkg/lib/arm64-v8a/$(basename $f) $f || exit 1
done
cp $W/dex/classes.dex $W/pkg/
(cd $W/pkg && zip -q -r ../base.apk classes.dex lib) || exit 1

$BT/zipalign -f -P 16 4 $W/base.apk $W/aligned.apk || exit 1
NAME=${APK_NAME:-larecomp$SUF}; [ -z "$SUF" ] && NAME=${APK_NAME:-larecomp-debug}
if [ -n "$RELEASE_KEYSTORE" ]; then
  # release signing: your own keystore, alias RELEASE_ALIAS (never in the repository; updates need the same key)
  $BT/apksigner sign --ks $RELEASE_KEYSTORE --ks-key-alias ${RELEASE_ALIAS:-release} --ks-pass file:$RELEASE_PASS_FILE \
    --out $OUT/$NAME.apk $W/aligned.apk || exit 1
else
  $BT/apksigner sign --ks $A/debug.keystore --ks-pass pass:android --key-pass pass:android --out $OUT/$NAME.apk $W/aligned.apk || exit 1
fi
$BT/aapt2 dump badging $OUT/$NAME.apk | grep -E "^package|sdkVersion|native-code|launchable"
unzip -l $OUT/$NAME.apk | grep -E "\.so|dex"
ls -la $OUT/$NAME.apk
