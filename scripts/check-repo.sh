#!/usr/bin/env bash
# Repo hygiene gate (CI and by hand). Fails on anything that must never be published.
. "$(dirname "$0")/lib.sh"
cd "$ROOT" || exit 1; FAILED=0
bad() { echo "FAIL $*"; FAILED=1; }

# 1. Signing material and key passwords.
git ls-files | grep -Ei '\.(jks|keystore|p12|pfx)$|keystore\.properties$' && bad "signing material is tracked"
git grep -nIE 'storePassword|keyPassword|BEGIN (RSA |EC )?PRIVATE KEY' -- . ':!scripts/check-repo.sh' ':!docs/internal' ':!scripts/sign.sh' && bad "a secret-looking string is tracked"

# 2. Patch series: org identity, UTC date, no POC naming that would reach users.
for f in $(git ls-files 'patches/*.patch'); do
  [ "$(sed -n 's/^From: //p' "$f" | head -1)" = "$GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>" ] || bad "$f: author is not the org identity (use scripts/export-patches.sh)"
  sed -n 's/^Date: //p' "$f" | head -1 | grep -q '+0000$' || bad "$f: Date header is not UTC"
  grep -qiE '^\+.*(secondaryuser\.poc|POC[12])' "$f" && bad "$f: adds POC naming to shipped code/strings"
done

# 3. upstream.lock is consistent with the patch directory.
load_lock
[ -d "patches/$UPSTREAM_TAG" ] || bad "no patches/$UPSTREAM_TAG for the pinned upstream tag"

# 4. Every release tag in the changelog has release notes.
[ -f "release-notes/$RELEASE_TAG.md" ] || echo "note: release-notes/$RELEASE_TAG.md not written yet (required before tagging)"
exit "$FAILED"
