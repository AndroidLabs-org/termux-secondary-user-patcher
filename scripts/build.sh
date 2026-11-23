#!/usr/bin/env bash
# Applies the patches and builds the UNSIGNED release APKs.
# Usage: scripts/build.sh            Output: out/unsigned/*.apk
# Needs (the v0.118.3 toolchain, Gradle 7.2 / AGP 4.2.2): JDK 11, ANDROID_HOME with platform 30,
# build-tools 30.0.3 and NDK 22.1.7171670. A newer JDK does not work with this Gradle version.
. "$(dirname "$0")/lib.sh"
load_lock
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK directory}"

mkdir -p "$ROOT/build"
"$ROOT/scripts/apply-patches.sh" "$ROOT/build/src"

cd "$ROOT/build/src" || exit 1
# versionCode is hardcoded in upstream's app/build.gradle; the patch series leaves it alone so a
# new upstream base never conflicts there. Set it here from upstream.lock.
GRADLE=app/build.gradle
[ "$(grep -c '^\( *\)versionCode [0-9]*' "$GRADLE")" = 1 ] || die "expected exactly one versionCode line in $GRADLE"
sed -i.bak "s/^\( *\)versionCode [0-9]*/\1versionCode $VERSION_CODE/" "$GRADLE" && rm -f "$GRADLE.bak"

# NDK r22 ships no Apple Silicon host tools: its ndk-build only fails on `uname -m` = arm64, and the
# x86_64 prebuilts run under Rosetta. Local macOS builds only; Linux (CI) is unaffected.
if [ "$(uname -sm)" = "Darwin arm64" ]; then PATH="$ROOT/scripts/host-shim:$PATH"; fi

export TERMUX_APP_VERSION_NAME="$VERSION_NAME"
export TERMUX_APK_VERSION_TAG="secondary-user-$VERSION_NAME"
export TERMUX_SPLIT_APKS_FOR_RELEASE_BUILDS=1

echo "==> Building $VERSION_NAME (versionCode $VERSION_CODE)"
# The bootstrap download is a separate invocation: native compilation needs the zips to exist.
./gradlew --no-daemon :app:downloadBootstraps
./gradlew --no-daemon :app:assembleRelease

mkdir -p "$ROOT/out/unsigned"; rm -f "$ROOT/out/unsigned"/*.apk
cp app/build/outputs/apk/release/*.apk "$ROOT/out/unsigned/"
ls -l "$ROOT/out/unsigned"

if [ -n "$PLUGINS" ]; then
  for name in $PLUGINS; do "$ROOT/scripts/build-plugin.sh" "$name"; done
fi
