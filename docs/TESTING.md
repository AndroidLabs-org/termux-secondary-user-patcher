# Testing

Release bar: fully working in any secondary user, and unchanged in user 0.

## Automated
- `scripts/test-emulator.sh <apk>`: install + launch in users 0, 10, 11; user 0 makes no `su`
  request; with root, the mapping exists inside the Termux process and init's namespace is
  untouched. Root-dependent checks print SKIP without root.
- `tests/root-helper/run-tests.sh <path to SecondaryUserPrefixManager.java>`: drives each safety
  check and exit code of the root script (no device needed).
- `scripts/check-repo.sh`: repo hygiene gate (no signing material, patch headers, locks).

## Manual gate
Rooting a CI AVD with Magisk is still an open problem, so the root-dependent checks run by hand on
a rooted AVD and on a real rooted device before a release.

Real-device run for 0.118.3-mu1 (Google Pixel 8a, Android 17, Magisk 31.1, 18 Nov 2026, test
build): users 10 and 11 (also at once) with `TERMUX__USER_ID`, `pkg update`, package install and
storage setup; Device Owner Managed and User-Independent modes; user 0 normal with no Termux root
request; mapping present only in the Termux process. Magisk 31.1 has no interactive root prompt,
so root was granted in advance. Not covered: KernelSU, APatch, work profiles, plugins, other
devices and Android versions, and the final release-key build.
