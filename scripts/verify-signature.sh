#!/usr/bin/env bash
# Fails unless every APK in out/signed carries the expected signing certificate.
# Usage: scripts/verify-signature.sh <expected-sha256-hex>
. "$(dirname "$0")/lib.sh"
EXPECTED=$(echo "${1:?expected sha256 fingerprint}" | tr -d ':' | tr 'A-F' 'a-f')
: "${ANDROID_HOME:?}"
APKSIGNER="${SIGN_BUILD_TOOLS:-$ANDROID_HOME/build-tools/36.0.0}/apksigner"
ls "$ROOT/out/signed"/*.apk >/dev/null 2>&1 || die "no signed APKs"
for apk in "$ROOT/out/signed"/*.apk; do
  ACTUAL=$("$APKSIGNER" verify --print-certs "$apk" | sed -n 's/.*certificate SHA-256 digest: //p' | head -1)
  echo "$(basename "$apk"): $ACTUAL"
  [ "$ACTUAL" = "$EXPECTED" ] || die "signing certificate of $(basename "$apk") is not the expected key - refusing to publish"
done
