#!/usr/bin/env bash
# Behaviour tests for the root helper script, without a device.
#
# The script calls its tools by absolute path (/system/bin/stat, /proc/..., /data/...). Here those
# paths are redirected to a throw-away fixture directory holding fake tools, so every safety check
# and every exit code can be driven on purpose. Each case runs the real script text extracted from
# the Java source of the patched tree.
#
# Usage: tests/root-helper/run-tests.sh <SecondaryUserPrefixManager.java>
set -u
JAVA=${1:?path to SecondaryUserPrefixManager.java}
HERE=$(cd "$(dirname "$0")" && pwd)
USER_ID=10; APP_UID=1010193; APP_PID=4242
PASS=0; FAILN=0
HOST_PATH=$PATH

SCRIPT_TEXT=$(python3 "$HERE/extract-script.py" "$JAVA" "$USER_ID" "$APP_UID" "$APP_PID") || { echo "cannot extract script"; exit 2; }
[ -n "$SCRIPT_TEXT" ] || { echo "empty script"; exit 2; }

# ---- fixture -------------------------------------------------------------------------------
fx_new() {
  FX=$(mktemp -d) || exit 2
  FD=$FX/data; FP=$FX/proc; FB=$FX/bin; ST=$FX/stat
  mkdir -p "$FD/user/$USER_ID/com.termux/files" "$FD/data/com.termux" "$FP/self/ns" "$FP/1/ns" \
           "$FP/$APP_PID/ns" "$FP/1/root/data/data/com.termux" "$FB" "$ST"
  SRC="$FD/user/$USER_ID/com.termux/files"; TGT="$FD/data/com.termux/files"; ITGT="$FP/1/root/data/data/com.termux/files"
  echo "mnt:[222]" > "$FP/self/ns/mnt"; echo "mnt:[222]" > "$FP/$APP_PID/ns/mnt"; echo "mnt:[111]" > "$FP/1/ns/mnt"
  echo "20 1 0:20 / /data rw,nosuid master:5 - ext4 /dev/block/dm-1 rw" > "$FP/self/mountinfo"
  echo "20 1 0:20 / /data rw,nosuid shared:1 - ext4 /dev/block/dm-1 rw" > "$FP/1/mountinfo"
  st_set "$SRC" u "$APP_UID"; st_set "$SRC" di "64:100"
  ln -s "$(command -v grep)" "$FB/grep"; ln -s "$(command -v tail)" "$FB/tail"
  cat > "$FB/id" <<'EOS'
#!/bin/sh
echo "${FX_ID:-0}"
EOS
  cat > "$FB/readlink" <<'EOS'
#!/bin/sh
[ -f "$1" ] && cat "$1"
EOS
  cat > "$FB/stat" <<'EOS'
#!/bin/sh
fmt=$2; key=$(printf %s "$3" | tr / '|'); f="$FX/stat/$key"
case "$fmt" in %u) f="$f.u";; %d:%i) f="$f.di";; *) exit 1;; esac
[ -f "$f" ] && cat "$f"
EOS
  cat > "$FB/umount" <<'EOS'
#!/bin/sh
echo "umount $*" >> "$FX/calls"
EOS
  cat > "$FB/mount" <<'EOS'
#!/bin/sh
echo "mount $*" >> "$FX/calls"
[ -n "$MOUNT_FAIL" ] && exit 1
src="$FX/data/user/10/com.termux/files"; tgt="$FX/data/data/com.termux/files"; itgt="$FX/proc/1/root/data/data/com.termux/files"
k() { printf %s "$1" | tr / '|'; }
if [ -z "$MOUNT_NO_ENTRY" ]; then
  if [ -n "$MOUNT_SHARED" ]; then s=" shared:9"; else s=""; fi
  echo "300 20 0:20 /user/10 /data/data rw$s - ext4 /dev/block/dm-1 rw" >> "$FX/proc/self/mountinfo"
fi
case "$MAPPED_STAT_FAIL" in
  id) ;;
  *) if [ -n "$MAPPED_ID_MISMATCH" ]; then echo "99:999" > "$FX/stat/$(k "$tgt").di"; else cp "$FX/stat/$(k "$src").di" "$FX/stat/$(k "$tgt").di"; fi ;;
esac
case "$MAPPED_STAT_FAIL" in
  uid) ;;
  *) if [ -n "$MAPPED_UID_MISMATCH" ]; then echo 12345 > "$FX/stat/$(k "$tgt").u"; else cp "$FX/stat/$(k "$src").u" "$FX/stat/$(k "$tgt").u"; fi ;;
esac
[ -n "$MOUNT_LEAK_INIT" ] && cp "$FX/stat/$(k "$src").di" "$FX/stat/$(k "$itgt").di"
[ -n "$MOUNT_CHANGE_INIT" ] && echo "301 20 0:20 /x /data/data rw - ext4 /dev/block/dm-1 rw" >> "$FX/proc/1/mountinfo"
exit 0
EOS
  # The script under test sets PATH=/system/bin:/system/xbin, which does not exist on the host:
  # give the fake tools back the host PATH so they can use tr/cat/cp.
  for t in id readlink stat umount mount; do
    { echo '#!/bin/sh'; echo 'PATH=$HOST_PATH'; tail -n +2 "$FB/$t"; } > "$FB/$t.new" && mv "$FB/$t.new" "$FB/$t"
  done
  chmod +x "$FB/id" "$FB/readlink" "$FB/stat" "$FB/umount" "$FB/mount"
  : > "$FX/calls"
  export FX HOST_PATH
}
st_key() { printf %s "$1" | tr / '|'; }
st_set() { printf '%s\n' "$3" > "${ST:?}/$(st_key "$1").$2"; }
st_del() { rm -f "${ST:?}/$(st_key "$1").$2"; }

# Run the real script against the fixture. Sets RC and OUT.
run_script() {
  printf '%s' "$SCRIPT_TEXT" | sed -e "s#/system/bin/#$FB/#g" -e "s#/proc/#$FP/#g" \
      -e "s#SOURCE_ROOT=/data/user/#SOURCE_ROOT=$FD/user/#" -e "s#TARGET_ROOT=/data/data#TARGET_ROOT=$FD/data#" > "$FX/script.sh"
  OUT=$(sh "$FX/script.sh" 2>&1); RC=$?
}

# expect <name> <exit-code> <slug-or-empty> [umount|no-mount|no-umount]
expect() {
  local name=$1 code=$2 slug=$3 extra=${4:-} ok=1 why=""
  [ "$RC" = "$code" ] || { ok=0; why="exit $RC, wanted $code"; }
  if [ -n "$slug" ]; then printf '%s' "$OUT" | grep -q "$slug" || { ok=0; why="$why; output lacks '$slug'"; }; fi
  case "$extra" in
    umount)    grep -q "^umount $FD/data\$" "$FX/calls" || { ok=0; why="$why; no rollback umount of the target"; } ;;
    no-mount)  ! grep -q "^mount" "$FX/calls" || { ok=0; why="$why; mount was called before the checks passed"; } ;;
    no-umount) ! grep -q "^umount" "$FX/calls" || { ok=0; why="$why; unexpected umount"; } ;;
  esac
  if [ "$ok" = 1 ]; then PASS=$((PASS+1)); echo "PASS  $name"; else FAILN=$((FAILN+1)); echo "FAIL  $name  ($why)"; echo "$OUT" | sed 's/^/        /'; fi
  rm -rf "${FX:?}"
  unset MOUNT_FAIL MOUNT_NO_ENTRY MOUNT_SHARED MOUNT_LEAK_INIT MOUNT_CHANGE_INIT MAPPED_STAT_FAIL MAPPED_ID_MISMATCH MAPPED_UID_MISMATCH FX_ID
}

echo "== static"
if printf '%s' "$SCRIPT_TEXT" | sh -n 2>/dev/null; then PASS=$((PASS+1)); echo "PASS  script parses with sh -n"; else FAILN=$((FAILN+1)); echo "FAIL  script does not parse"; fi
if printf '%s' "$SCRIPT_TEXT" | grep -nE '\$\(\(|`|eval ' >/dev/null; then FAILN=$((FAILN+1)); echo "FAIL  script uses eval/backticks/arithmetic"; else PASS=$((PASS+1)); echo "PASS  no eval, backticks or arithmetic in the script"; fi
BAD=$(printf '%s' "$SCRIPT_TEXT" | grep -vE '^(PATH=|USER_ID=[0-9]+$|APP_UID=[0-9]+$|APP_PID=[0-9]+$)' | grep -nE '(^|[ ;|(])(id|stat|readlink|grep|tail|mount|umount|cat|sh|su|rm|cp|mv|chmod|chown) ' | grep -vE '/system/bin/(id|stat|readlink|grep|tail|mount|umount) ' || true)
if [ -z "$BAD" ]; then PASS=$((PASS+1)); echo "PASS  every external tool is called by absolute /system/bin path"; else FAILN=$((FAILN+1)); echo "FAIL  tool called without absolute path:"; echo "$BAD"; fi
NONINT=$(printf '%s' "$SCRIPT_TEXT" | grep -E '^(USER_ID|APP_UID|APP_PID)=' | grep -vE '^[A-Z_]+=[0-9]+$' || true)
if [ -z "$NONINT" ]; then PASS=$((PASS+1)); echo "PASS  only integers are interpolated"; else FAILN=$((FAILN+1)); echo "FAIL  non-integer value interpolated: $NONINT"; fi

echo "== happy path"
fx_new; run_script; expect "maps the user's data and verifies it" 0 "mapping=verified" no-umount
fx_new; run_script
if grep -q "^mount -o bind $FD/user/$USER_ID $FD/data\$" "$FX/calls"; then PASS=$((PASS+1)); echo "PASS  binds exactly /data/user/<N> onto /data/data"; else FAILN=$((FAILN+1)); echo "FAIL  unexpected mount arguments: $(cat "$FX/calls")"; fi
rm -rf "${FX:?}"
fx_new; st_set "$TGT" di "64:100"; st_set "$TGT" u "$APP_UID"; echo "300 20 0:20 /user/10 /data/data rw master:7 - ext4 /dev/b rw" >> "$FP/self/mountinfo"
run_script; expect "already mapped in this namespace: succeeds without mounting again" 0 "mapping=already-present" no-mount

echo "== refuses before changing anything"
fx_new; export FX_ID=10193; run_script; expect "not root" 20 "not-root" no-mount
fx_new; rm -rf "${SRC:?}"; run_script; expect "source files directory missing" 21 "source-files-missing" no-mount
fx_new; st_del "$SRC" u; run_script; expect "cannot stat the source owner" 22 "source-stat-failed" no-mount
fx_new; st_set "$SRC" u 99999; run_script; expect "source owned by another uid" 23 "source-owner-mismatch" no-mount
fx_new; rm -f "${FP:?}/self/ns/mnt"; run_script; expect "own namespace unreadable" 24 "self-namespace-unreadable" no-mount
fx_new; rm -f "${FP:?}/$APP_PID/ns/mnt"; run_script; expect "app namespace unreadable" 25 "app-namespace-unreadable" no-mount
fx_new; rm -f "${FP:?}/1/ns/mnt"; run_script; expect "init namespace unreadable" 26 "init-namespace-unreadable" no-mount
fx_new; echo "mnt:[333]" > "$FP/self/ns/mnt"; run_script; expect "su did not enter the app namespace (Isolated mode)" 27 "su-did-not-enter-app-namespace" no-mount
fx_new; echo "mnt:[111]" > "$FP/self/ns/mnt"; echo "mnt:[111]" > "$FP/$APP_PID/ns/mnt"; run_script; expect "app shares init's namespace" 28 "app-shares-init-namespace" no-mount
fx_new; : > "$FP/self/mountinfo"; run_script; expect "/data mount not found" 29 "data-mount-not-found" no-mount
fx_new; echo "20 1 0:20 / /data rw shared:5 - ext4 /dev/b rw" > "$FP/self/mountinfo"; run_script; expect "/data is a shared mount" 30 "data-mount-is-shared" no-mount
fx_new; echo "300 20 0:20 /x /data/data rw shared:8 - ext4 /dev/b rw" >> "$FP/self/mountinfo"; run_script; expect "/data/data was already shared" 43 "target-was-shared" no-mount
fx_new; st_del "$SRC" di; run_script; expect "cannot read the source identity" 31 "source-identity-failed" no-mount
echo "== already-mapped checks"
fx_new; st_set "$TGT" di "64:100"; run_script; expect "identity matches but there is no mount entry" 40 "existing-target-mount-not-found" no-mount
fx_new; st_set "$TGT" di "64:100"; echo "300 20 0:20 /user/10 /data/data rw shared:7 - ext4 /dev/b rw" >> "$FP/self/mountinfo"; run_script; expect "existing mapping is a shared mount (stopped earlier as target-was-shared; the later check 41 is unreachable, same grep)" 43 "target-was-shared" no-mount
fx_new; st_set "$TGT" di "64:100"; st_set "$ITGT" di "64:100"; echo "300 20 0:20 /user/10 /data/data rw master:7 - ext4 /dev/b rw" >> "$FP/self/mountinfo"; run_script; expect "existing mapping is visible in init" 42 "mapping-visible-in-init-namespace" no-mount
echo "== rolls back when a check after the mount fails"
fx_new; export MOUNT_FAIL=1; run_script; expect "bind mount itself fails" 32 "bind-mount-failed" no-umount
fx_new; export MOUNT_NO_ENTRY=1; run_script; expect "mount left no entry" 33 "target-mount-not-found" umount
fx_new; export MOUNT_SHARED=1; run_script; expect "new mount is shared" 34 "target-mount-is-shared" umount
fx_new; export MOUNT_CHANGE_INIT=1; run_script; expect "init's mount view changed" 35 "init-namespace-changed" umount
fx_new; export MOUNT_LEAK_INIT=1; run_script; expect "mapping became visible in init" 42 "mapping-visible-in-init-namespace" umount
fx_new; export MAPPED_STAT_FAIL=id; run_script; expect "cannot read the mapped identity" 36 "mapped-identity-failed" umount
fx_new; export MAPPED_STAT_FAIL=uid; run_script; expect "cannot read the mapped owner" 37 "mapped-owner-stat-failed" umount
fx_new; export MAPPED_ID_MISMATCH=1; run_script; expect "mapped directory is a different inode" 38 "mapped-identity-mismatch" umount
fx_new; export MAPPED_UID_MISMATCH=1; run_script; expect "mapped directory has the wrong owner" 39 "mapped-owner-mismatch" umount

echo
echo "root helper tests: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
