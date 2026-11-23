#!/usr/bin/env bash
# Runs the unit tests of the patched tree under JaCoCo and prints coverage for the classes this
# patch series adds or changes. Output: out/coverage/ (html, xml, csv, summary.txt).
# Same toolchain as scripts/build.sh. Does not modify upstream's build files (see jacoco.init.gradle).
. "$(dirname "$0")/lib.sh"
load_lock
: "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK directory}"

mkdir -p "$ROOT/build"
"$ROOT/scripts/apply-patches.sh" "$ROOT/build/src"
# Our tests live outside patches/ and are copied into this scratch tree only: they are never part of
# the series, the release build or the APK.
mkdir -p "$ROOT/build/src/app/src/test/java"
cp -R "$ROOT/tests/java/." "$ROOT/build/src/app/src/test/java/"
cd "$ROOT/build/src" || exit 1
if [ "$(uname -sm)" = "Darwin arm64" ]; then PATH="$ROOT/scripts/host-shim:$PATH"; fi
export TERMUX_APP_VERSION_NAME="$VERSION_NAME"

./gradlew --no-daemon :app:downloadBootstraps
# --continue: a failing upstream test must not hide the coverage numbers.
STATUS=0
./gradlew --no-daemon --continue -I "$ROOT/scripts/jacoco.init.gradle" \
  :app:testDebugUnitTest :app:stupJacocoReport || STATUS=$?

OUT="$ROOT/out/coverage"; rm -rf "$OUT"; mkdir -p "$OUT"
REPORT="app/build/reports/jacoco/stupJacocoReport"
[ -d "$REPORT" ] && cp -R "$REPORT"/. "$OUT"/
CSV=$(find "$OUT" -maxdepth 2 -name '*.csv' | head -1)
{
  echo "Coverage of classes added or changed by patches/${UPSTREAM_TAG} (JaCoCo, unit tests only)"
  if [ -n "$CSV" ]; then
    python3 - "$CSV" <<'PY'
import csv, sys
NEW = ("SecondaryUserPrefixManager", "SecondaryUserSetupActivity")
TOUCHED = ("RunCommandService", "TermuxActivity", "TermuxService", "TermuxInstaller", "TermuxApplication")
rows = list(csv.DictReader(open(sys.argv[1])))
def pct(c, m): return 100.0 * c / (c + m) if c + m else 0.0
def show(label, names):
    sel = [r for r in rows if r["CLASS"].split("$")[0] in names]
    lc = sum(int(r["LINE_COVERED"]) for r in sel); lm = sum(int(r["LINE_MISSED"]) for r in sel)
    bc = sum(int(r["BRANCH_COVERED"]) for r in sel); bm = sum(int(r["BRANCH_MISSED"]) for r in sel)
    print("%-8s lines %5.1f%% (%d/%d)  branches %5.1f%% (%d/%d)" % (label, pct(lc, lm), lc, lc + lm, pct(bc, bm), bc, bc + bm))
    for n in names:
        s = [r for r in sel if r["CLASS"].split("$")[0] == n]
        if s:
            c = sum(int(r["LINE_COVERED"]) for r in s); m = sum(int(r["LINE_MISSED"]) for r in s)
            print("   %-30s %5.1f%% (%d/%d lines)" % (n, pct(c, m), c, c + m))
    return lc, lm
nc, nm = show("NEW", NEW)
show("TOUCHED", TOUCHED)
print("NEW_CODE_COVERAGE: %.1f%%" % pct(nc, nm))
PY
  else
    echo "no JaCoCo csv was produced (tests did not run or no execution data)"
  fi
} | tee "$OUT/summary.txt"
exit "$STATUS"
