#!/usr/bin/env bash
# Clones the pinned upstream termux-app and applies patches/<UPSTREAM_TAG>/*.patch on top.
# Usage: scripts/apply-patches.sh [output-dir]      (default: build/src)
# Exit 0 = applied cleanly. Exit 3 = a patch did not apply (the failing patch is printed, so the
# CI can open an issue); any other non-zero = something else is wrong.
. "$(dirname "$0")/lib.sh"
load_lock

OUT=${1:-$ROOT/build/src}
PATCH_DIR="$ROOT/patches/$UPSTREAM_TAG"
[ -d "$PATCH_DIR" ] || die "no patch series for $UPSTREAM_TAG (expected $PATCH_DIR)"
ls "$PATCH_DIR"/*.patch >/dev/null 2>&1 || die "$PATCH_DIR contains no .patch files"

rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"
echo "==> Cloning $UPSTREAM_REPO @ $UPSTREAM_TAG"
git clone --quiet --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_REPO" "$OUT"
ACTUAL=$(git -C "$OUT" rev-parse HEAD)
[ "$ACTUAL" = "$UPSTREAM_SHA" ] || die "tag $UPSTREAM_TAG is $ACTUAL, upstream.lock pins $UPSTREAM_SHA - refusing to build"

echo "==> Applying patches/$UPSTREAM_TAG"
cd "$OUT" || exit 1
for p in "$PATCH_DIR"/*.patch; do
  if git am --3way --quiet "$p" 2>"$ROOT/build/am.err"; then
    echo "    ok   $(basename "$p")"
  else
    echo "    FAIL $(basename "$p")" >&2
    cat "$ROOT/build/am.err" >&2
    git am --abort >/dev/null 2>&1 || true
    echo "$(basename "$p")" > "$ROOT/build/failed-patch.txt"
    exit 3
  fi
done
echo "==> Patched tree: $(git rev-parse 'HEAD^{tree}')"
