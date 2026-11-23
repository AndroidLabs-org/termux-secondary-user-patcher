#!/usr/bin/env bash
# Shared helpers. Sourced by the other scripts; not run directly.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LOCK="${UPSTREAM_LOCK:-$ROOT/upstream.lock}"

# Identity used for the throwaway commits `git am` creates in the build tree. Nothing built here
# is pushed anywhere, but a fixed identity keeps the source tarball free of the host's git config.
export GIT_AUTHOR_NAME=AndroidLabs-org GIT_AUTHOR_EMAIL=info@androidlabs.org
export GIT_COMMITTER_NAME=AndroidLabs-org GIT_COMMITTER_EMAIL=info@androidlabs.org
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

die() { echo "ERROR: $*" >&2; exit 1; }

# lock_get KEY: value of KEY in upstream.lock (empty if unset).
lock_get() { sed -n "s/^$1=//p" "$LOCK" | head -1; }

# Variables below are consumed by the scripts that source this file.
# shellcheck disable=SC2034
load_lock() {
  [ -f "$LOCK" ] || die "missing $LOCK"
  UPSTREAM_REPO=$(lock_get UPSTREAM_REPO); UPSTREAM_TAG=$(lock_get UPSTREAM_TAG)
  UPSTREAM_SHA=$(lock_get UPSTREAM_SHA);   MU=$(lock_get MU); PLUGINS=$(lock_get PLUGINS)
  for v in UPSTREAM_REPO UPSTREAM_TAG UPSTREAM_SHA MU; do
    [ -n "${!v}" ] || die "$v is empty in $LOCK"
  done
  case "$UPSTREAM_TAG" in v[0-9]*.[0-9]*.[0-9]*) ;; *) die "UPSTREAM_TAG '$UPSTREAM_TAG' is not vX.Y.Z" ;; esac
  case "$MU" in ''|*[!0-9]*) die "MU must be a positive integer" ;; esac
  UPSTREAM_VERSION=${UPSTREAM_TAG#v}
  VERSION_NAME="${UPSTREAM_VERSION}-mu${MU}"
  RELEASE_TAG="v${VERSION_NAME}"
  # versionCode = minor*1e6 + patch*1e4 + mu*10: monotonic across upstream releases and our own
  # revisions, and far above upstream's own 1002.
  IFS=. read -r _major MINOR PATCH <<EOF2
$UPSTREAM_VERSION
EOF2
  VERSION_CODE=$(( MINOR * 1000000 + PATCH * 10000 + MU * 10 ))
}
