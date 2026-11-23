# Build

Toolchain (for the v0.118.3 line): JDK 11, Android SDK platform 30, build-tools 30.0.3 (36.0.0 for signing), NDK 22.1.7171670. Linux x86_64 is the reference; on Apple silicon see `scripts/host-shim/`.

    export ANDROID_HOME=...
    scripts/build.sh                     # clones the pinned upstream, applies patches, builds -> out/unsigned
    STUP_KEYSTORE=... STUP_STORE_PASSWORD=... STUP_KEY_ALIAS=... STUP_KEY_PASSWORD=... scripts/sign.sh

`upstream.lock` pins the upstream tag and commit; the build refuses a tag that moved.
versionName = `<upstream>-mu<MU>`; versionCode = minor*1e6 + patch*1e4 + MU*10.

## Plugins (optional, for your own signed set)

Release builds ship no plugins. To sign the app and the plugins with one key of your own:

    export JAVA_HOME_11=... JAVA_HOME_17=...      # the app needs JDK 11, the plugins JDK 17
    JAVA_HOME=$JAVA_HOME_11 scripts/build.sh      # empties out/unsigned, so run it first
    scripts/build-plugins.sh [api styling ...]    # pins in plugins.lock; also builds termux-shared
    scripts/sign.sh                               # signs every APK in out/unsigned with your key

`scripts/build-plugins.sh` needs SDK platform 35 as well, and NDK `$NDK_VERSION` (default 25.1.8937393) to
build `termux-shared`. See the README, section Plugins, for which plugins work in a secondary user.
