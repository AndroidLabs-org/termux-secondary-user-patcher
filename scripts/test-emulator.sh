#!/usr/bin/env bash
# Smoke test on a running emulator/device over adb: user 0 and secondary users 10 and 11.
# Usage: scripts/test-emulator.sh <apk> [serial]
# Root-dependent checks run only when `su` works; otherwise they are reported as SKIP, never as
# a pass. STATUS: written but not yet validated on a rooted AVD - that is the CI spike in
# docs/TESTING.md. Treat a green run of the SKIP-free path as the real signal.
set -uo pipefail
APK=${1:?apk}; ADB="adb ${2:+-s $2}"
FAILS=0; pass() { echo "PASS $*"; }; fail() { echo "FAIL $*"; FAILS=$((FAILS+1)); }; skip() { echo "SKIP $*"; }

$ADB wait-for-device
HAVE_ROOT=0; $ADB shell 'su -c id -u' 2>/dev/null | grep -q '^0' && HAVE_ROOT=1

for u in 0 10 11; do
  if [ "$u" != 0 ]; then
    $ADB shell "pm list users" | grep -q "UserInfo{$u:" || $ADB shell "pm create-user --profileOf 0 --user-type android.os.usertype.full.SECONDARY u$u" >/dev/null 2>&1 \
      || $ADB shell "pm create-user u$u" >/dev/null
    $ADB shell "am start-user -w $u" >/dev/null
  fi
  $ADB install -r -g --user "$u" "$APK" >/dev/null && pass "install in user $u" || { fail "install in user $u"; continue; }
  $ADB shell "am start --user $u -n com.termux/.app.TermuxActivity" >/dev/null
  sleep 20
  pid=$($ADB shell "pidof com.termux" | tr -d '\r' | awk '{print $1}')
  [ -n "$pid" ] && pass "user $u: Termux process is running" || fail "user $u: Termux did not start"
  if [ "$u" = 0 ]; then
    $ADB logcat -d | grep -qi 'su -t' && fail "user 0 requested root" || pass "user 0 made no su request"
  elif [ "$HAVE_ROOT" = 1 ]; then
    $ADB shell "su -c 'grep -c /data/data /proc/1/mountinfo'" >/dev/null && pass "user $u: init namespace readable"
    $ADB shell "su -c 'nsenter -t $pid -m ls /data/data/com.termux/files >/dev/null'" \
      && pass "user $u: /data/data/com.termux is mapped inside the Termux process" || fail "user $u: mapping missing"
  else
    skip "user $u: mapping checks need root"
  fi
done
echo "failures: $FAILS"; exit "$FAILS"
