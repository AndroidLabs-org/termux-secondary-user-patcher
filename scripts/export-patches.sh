#!/usr/bin/env bash
# Exports a patch series from a development clone of termux-app as org-authored, UTC-dated
# format-patch files into patches/<tag>/. Run it in the clone, not in this repo:
#   scripts/export-patches.sh <path-to-termux-app-clone> <base-tag>
# The series is everything between <base-tag> and HEAD. Headers are rewritten to the org identity
# and noon-UTC dates (the repo hygiene check refuses anything else).
. "$(dirname "$0")/lib.sh"
CLONE=${1:?termux-app clone}; BASE=${2:?base tag, e.g. v0.118.3}
DEST="$ROOT/patches/$BASE"; mkdir -p "$DEST"; rm -f "$DEST"/*.patch
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git -C "$CLONE" format-patch --quiet --no-signature --zero-commit -o "$TMP" "$BASE"..HEAD
[ -n "$(ls "$TMP")" ] || die "no commits between $BASE and HEAD"
D=$(date -u +"%a, %d %b %Y 12:00:00 +0000")
for f in "$TMP"/*.patch; do
  # awk, not sed: the same script must run on macOS and on the Linux runners.
  awk -v from="From: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>" -v date="Date: $D" \
    '!f && /^From: /{print from; f=1; next} !d && /^Date: /{print date; d=1; next} {print}' \
    "$f" > "$DEST/$(basename "$f")"
done
ls "$DEST"
