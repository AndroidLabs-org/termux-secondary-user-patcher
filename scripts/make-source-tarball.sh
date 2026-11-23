#!/usr/bin/env bash
# GPLv3: the complete corresponding source of a release = patched upstream tree + this repo's
# patches and build scripts. Output: out/signed/Termux-Secondary-User-<version>-source.tar.gz
. "$(dirname "$0")/lib.sh"
load_lock
[ -d "$ROOT/build/src/.git" ] || die "run scripts/build.sh first"
OUT="$ROOT/out/signed/Termux-Secondary-User-${VERSION_NAME}-source.tar.gz"
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
NAME="termux-secondary-user-${VERSION_NAME}-source"
mkdir -p "$STAGE/$NAME/termux-app-patched" "$STAGE/$NAME/patcher"
git -C "$ROOT/build/src" archive --format=tar HEAD | tar -x -C "$STAGE/$NAME/termux-app-patched"
# The repo's own files, minus the internal paths that are never published.
(cd "$ROOT" && git ls-files -z | grep -zv '^\(\.gitlab\|docs/internal\)' | xargs -0 tar -c) | tar -x -C "$STAGE/$NAME/patcher"
mkdir -p "$ROOT/out/signed"
tar -czf "$OUT" -C "$STAGE" "$NAME"
echo "$OUT"
