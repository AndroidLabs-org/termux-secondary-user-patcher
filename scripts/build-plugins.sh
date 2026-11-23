#!/usr/bin/env bash
# Builds the official Termux plugins from source so you can sign them with the same key as the app.
# Plugins share sharedUserId com.termux with the app, so a plugin only installs next to this build if
# both are signed with the same key. Release builds of this project ship no plugins; this is the
# route for signing your own set. Pins are in plugins.lock.
#
# Usage:   scripts/build-plugins.sh [name ...]       (default: every plugin in plugins.lock)
# Output:  out/unsigned/termux-<name>-<tag>.apk      then sign everything with scripts/sign.sh
# Needs:   ANDROID_HOME   SDK with platform 30 and 35, build-tools, NDK $NDK_VERSION
#          JAVA_HOME_11   JDK 11, builds termux-shared (same toolchain as the app)
#          JAVA_HOME_17   JDK 17, builds the plugins
# Order:   scripts/build.sh first (it empties out/unsigned), then this script, then scripts/sign.sh.
UPSTREAM_LOCK=$(cd "$(dirname "$0")/.." && pwd)/plugins.lock
export UPSTREAM_LOCK
. "$(dirname "$0")/lib.sh"
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK directory}"
: "${JAVA_HOME_11:?set JAVA_HOME_11 to a JDK 11}" "${JAVA_HOME_17:?set JAVA_HOME_17 to a JDK 17}"
NDK_VERSION=${NDK_VERSION:-25.1.8937393}

NAMES=${*:-$(lock_get PLUGINS)}
[ -n "$NAMES" ] || die "no plugins to build"
WORK="$ROOT/build/plugins"; M2="$WORK/m2"; mkdir -p "$WORK" "$M2" "$ROOT/out/unsigned"

# fetch_pinned REPO REF SHA DIR: shallow checkout that refuses a ref which moved.
fetch_pinned() {
  rm -rf "$4"; mkdir -p "$4"
  git -C "$4" init --quiet
  git -C "$4" remote add origin "$1"
  git -C "$4" fetch --quiet --depth 1 origin "$2"
  git -C "$4" checkout --quiet FETCH_HEAD
  [ "$(git -C "$4" rev-parse HEAD)" = "$3" ] || die "$1 $2 does not match pinned $3"
}

# --- 1. termux-shared (and its two sibling libraries) into a private Maven repository ------------
SHARED_SHA=$(lock_get SHARED_SHA); SHARED_VERSION=$(lock_get SHARED_VERSION)
[ -n "$SHARED_SHA" ] && [ -n "$SHARED_VERSION" ] || die "SHARED_SHA/SHARED_VERSION missing in plugins.lock"
if [ ! -f "$M2/.built-$SHARED_SHA" ]; then
  echo "==> Building termux-shared at $SHARED_VERSION"
  SRC="$WORK/termux-app"
  fetch_pinned "$(lock_get SHARED_REPO)" "$SHARED_SHA" "$SHARED_SHA" "$SRC"
  cd "$SRC" || exit 1
  export ANDROID_HOME JAVA_HOME="$JAVA_HOME_11" JITPACK_NDK_VERSION="$NDK_VERSION"
  # On Apple silicon, NDK r22 ships no host tools; Linux is unaffected (see scripts/build.sh).
  if [ "$(uname -sm)" = "Darwin arm64" ]; then PATH="$ROOT/scripts/host-shim:$PATH"; fi
  # Plugins ask for com.termux:terminal-emulator/terminal-view:0.118.0 (as published by termux-app)
  # and for com.termux.termux-app:termux-shared:<commit>, so publish both spellings.
  ./gradlew --no-daemon -q -Dmaven.repo.local="$M2" \
    :terminal-emulator:publishToMavenLocal :terminal-view:publishToMavenLocal
  for f in termux-shared/build.gradle terminal-view/build.gradle; do
    sed -i.bak "s/groupId = 'com.termux'/groupId = 'com.termux.termux-app'/; s/version = '0.118.0'/version = '$SHARED_VERSION'/" "$f"
    rm -f "$f.bak"
  done
  ./gradlew --no-daemon -q -Dmaven.repo.local="$M2" \
    :terminal-view:publishToMavenLocal :termux-shared:publishToMavenLocal
  touch "$M2/.built-$SHARED_SHA"
  cd "$ROOT" || exit 1
fi

# Gradle init script: look in the private repository, and use the renamed terminal-view everywhere
# (Termux:Float depends on it directly and would otherwise get two copies of the same classes).
cat > "$WORK/plugins.init.gradle" <<EOF
allprojects {
  repositories { mavenLocal() }
  configurations.all {
    resolutionStrategy.dependencySubstitution {
      substitute module('com.termux:terminal-view') using module('com.termux.termux-app:terminal-view:$SHARED_VERSION')
    }
  }
}
EOF

# --- 2. the plugins ------------------------------------------------------------------------------
# Word splitting is intended: NAMES is a space-separated list.
# shellcheck disable=SC2086
for name in $NAMES; do
  key=$(echo "$name" | tr 'a-z-' 'A-Z_')
  repo=$(lock_get "PLUGIN_${key}_REPO"); tag=$(lock_get "PLUGIN_${key}_TAG"); sha=$(lock_get "PLUGIN_${key}_SHA")
  [ -n "$repo" ] && [ -n "$tag" ] && [ -n "$sha" ] || die "PLUGIN_${key}_REPO/_TAG/_SHA missing in plugins.lock"
  echo "==> Building Termux:$name $tag"
  dir="$WORK/plugin-$name"
  fetch_pinned "$repo" "refs/tags/$tag" "$sha" "$dir"
  (
    cd "$dir" || exit 1
    # The plugin's release build is signed with a public test key; scripts/sign.sh replaces it.
    ANDROID_HOME="$ANDROID_HOME" JAVA_HOME="$JAVA_HOME_17" \
      ./gradlew --no-daemon -q -Dorg.gradle.jvmargs=-Xmx3g -Dmaven.repo.local="$M2" \
        -I "$WORK/plugins.init.gradle" assembleRelease
  )
  apk=$(find "$dir" -path '*/build/outputs/apk/release/*.apk' | head -1)
  [ -n "$apk" ] || die "no release APK produced for $name"
  cp "$apk" "$ROOT/out/unsigned/termux-$name-$tag.apk"
done
ls -l "$ROOT/out/unsigned"
