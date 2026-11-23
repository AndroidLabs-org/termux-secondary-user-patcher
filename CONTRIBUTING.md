# Contributing

This repository holds patches against official Termux, not a fork. Change a behaviour by editing a
patch, not by committing to a copy of Termux.

## How the pieces fit
- `upstream.lock` pins the Termux tag and commit. `patches/<tag>/` is the series applied on top.
- `scripts/apply-patches.sh` shows whether the series still applies; `scripts/build.sh` builds it.
- Toolchain for the v0.118.3 line: JDK 11, SDK platform 30, build-tools 30.0.3, NDK 22.1.7171670.

## Changing a patch
1. `scripts/apply-patches.sh`, then work in `build/src` (a normal git checkout).
2. Commit your change there, then `scripts/export-patches.sh build/src <tag>` to regenerate `patches/`.
3. Build and test on an emulator (user 0) and, for anything touching the mapping, on a rooted device
   in a secondary user. Say what you tested in the pull request.

## Ground rules
- Anything that changes behaviour, the root helper, or what is mounted needs a clear explanation
  and a test; small and reviewable beats clever.
- Do not add network code or permissions.
- Report vulnerabilities privately, see `SECURITY.md`.
