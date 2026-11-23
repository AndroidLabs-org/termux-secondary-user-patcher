# What the patches change

The series for Termux **v0.118.3** is in `patches/v0.118.3/`: three patches, applied in order on the
official source at the pinned commit (see `upstream.lock`). Apply them with `scripts/build.sh`.

## 0001 Support process-local Termux paths for secondary users
- `SecondaryUserPrefixManager` (new): detects the Android user from the UID, returns at once in
  user 0, runs the root helper (`su -t <pid>`), checks the namespace, binds `/data/user/<N>` onto
  `/data/data` inside the Termux process, verifies inode and owner, and rolls back on failure.
  **This file holds the whole root script** that the README describes.
- `SecondaryUserSetupActivity` (new): first-launch progress and retry screen, and the "setup failed
  safely" screen with diagnostics.
- `TermuxApplication`, `TermuxActivity`, `TermuxInstaller`, `TermuxService`, `RunCommandService`:
  wait for the mapping before touching the hardcoded paths.
- `AndroidManifest.xml`, `strings.xml`: the new activity and its texts.

## 0002 Export actual Android user id to Termux shells
- `TermuxShellUtils`: shells get `TERMUX__USER_ID` with the real Android user, so `am`-based tools
  such as `termux-setup-storage` address the right user.

## 0003 Initialize secondary-user mapping for cold RUN_COMMAND
- `RunCommandService`, `SecondaryUserPrefixManager`: a `RUN_COMMAND` that arrives while the process
  is cold sets the mapping up first, then runs.

No package-name change, no target-SDK change, no global mount, no bootstrap change, no new Android
permission.
