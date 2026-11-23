#!/usr/bin/env bash
# Builds one Termux plugin (widget, api, tasker, boot, ...) from its official repo, pinned in
# upstream.lock, applying patches/plugins/<name>/*.patch if that directory exists.
# Usage: scripts/build-plugin.sh <name>        Output: out/unsigned/<name>*.apk
# Needs in upstream.lock: PLUGIN_<NAME>_REPO, PLUGIN_<NAME>_TAG, PLUGIN_<NAME>_SHA (NAME uppercased).
. "$(dirname "$0")/lib.sh"
load_lock
NAME=${1:?plugin name}; KEY=$(echo "$NAME" | tr 'a-z-' 'A-Z_')
REPO=$(lock_get "PLUGIN_${KEY}_REPO"); TAG=$(lock_get "PLUGIN_${KEY}_TAG"); SHA=$(lock_get "PLUGIN_${KEY}_SHA")
[ -n "$REPO" ] && [ -n "$TAG" ] && [ -n "$SHA" ] || die "PLUGIN_${KEY}_REPO/_TAG/_SHA missing in $LOCK"

DIR="$ROOT/build/plugin-$NAME"; rm -rf "$DIR"
git clone --quiet --depth 1 --branch "$TAG" "$REPO" "$DIR"
[ "$(git -C "$DIR" rev-parse HEAD)" = "$SHA" ] || die "plugin $NAME: tag $TAG does not match pinned $SHA"
if ls "$ROOT/patches/plugins/$NAME"/*.patch >/dev/null 2>&1; then
  (cd "$DIR" && git am --3way --quiet "$ROOT/patches/plugins/$NAME"/*.patch)
fi
cd "$DIR" || exit 1
# Plugins share sharedUserId com.termux with the app, so they must be signed with the same key:
# this only builds them; scripts/sign.sh signs everything in out/unsigned.
./gradlew --no-daemon assembleRelease
mkdir -p "$ROOT/out/unsigned"
find . -path '*/build/outputs/apk/release/*.apk' -exec cp {} "$ROOT/out/unsigned/termux-$NAME-$TAG.apk" \;
