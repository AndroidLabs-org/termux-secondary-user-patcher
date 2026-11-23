#!/usr/bin/env bash
# zipalign (16 KiB pages) + apksigner (v1/v2/v3) for every APK in out/unsigned -> out/signed.
# Usage: STUP_KEYSTORE=/path/release.jks STUP_STORE_PASSWORD=... STUP_KEY_ALIAS=... \
#        STUP_KEY_PASSWORD=... scripts/sign.sh
# Signing uses its own build-tools (>= 35 for zipalign -P 16): SIGN_BUILD_TOOLS, default
# $ANDROID_HOME/build-tools/36.0.0. Passwords go to apksigner through environment variables (env: pass source), never argv.
. "$(dirname "$0")/lib.sh"
load_lock
: "${ANDROID_HOME:?}" "${STUP_KEYSTORE:?}" "${STUP_STORE_PASSWORD:?}" "${STUP_KEY_ALIAS:?}" "${STUP_KEY_PASSWORD:?}"
export STUP_STORE_PASSWORD STUP_KEY_PASSWORD
BT="${SIGN_BUILD_TOOLS:-$ANDROID_HOME/build-tools/36.0.0}"
[ -x "$BT/apksigner" ] || die "no apksigner in $BT (set SIGN_BUILD_TOOLS to a build-tools >= 35 directory)"

mkdir -p "$ROOT/out/signed"; rm -f "$ROOT/out/signed"/*.apk
ls "$ROOT/out/unsigned"/*.apk >/dev/null 2>&1 || die "nothing to sign in out/unsigned"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
for apk in "$ROOT/out/unsigned"/*.apk; do
  base=$(basename "$apk" .apk)
  # Stable, Obtainium-friendly name: Termux-Secondary-User-<version>-<abi>.apk
  abi=${base#termux-app_secondary-user-${VERSION_NAME}_}   # Gradle output name = termux-app_<tag>_<abi>
  case "$base" in termux-app_*) final="Termux-Secondary-User-${VERSION_NAME}-${abi}.apk" ;; *) final="$base.apk" ;; esac
  "$BT/zipalign" -f -P 16 4 "$apk" "$TMP/aligned.apk"
  "$BT/apksigner" sign --ks "$STUP_KEYSTORE" --ks-key-alias "$STUP_KEY_ALIAS" \
    --ks-pass env:STUP_STORE_PASSWORD --key-pass env:STUP_KEY_PASSWORD \
    --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
    --out "$ROOT/out/signed/$final" "$TMP/aligned.apk"
  "$BT/zipalign" -c -P 16 -v 4 "$ROOT/out/signed/$final" >/dev/null
  "$BT/apksigner" verify "$ROOT/out/signed/$final"
  echo "signed $final"
done
