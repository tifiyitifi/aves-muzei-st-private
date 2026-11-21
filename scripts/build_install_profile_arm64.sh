#!/usr/bin/env sh
# Build and install the arm64 custom-flavor profile APK for a connected device.
# The committed root pubspec is the custom flavor, so no flavor swap is needed.
set -eu

if [ ! -d "scripts" ]; then
    cd ..
fi

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT INT TERM

./flutterw gen-l10n

# `--split-per-abi` gives the APK an ABI filter so the version code offset is applied;
# `--target-platform` keeps only the device's native libraries in the artifact.
set +e
./flutterw build apk --profile -t lib/main_custom.dart --flavor custom \
    --split-per-abi --target-platform android-arm64 > "$LOG" 2>&1
build_status=$?
set -e
cat "$LOG"
if [ "$build_status" -ne 0 ]; then
    echo "build failed with status $build_status" >&2
    exit "$build_status"
fi
grep -q "output versionCodeOverride=" "$LOG" || {
    echo "ABI version code offset was not applied; refusing to install" >&2
    exit 1
}

APK="build/app/outputs/flutter-apk/app-arm64-v8a-custom-profile.apk"
[ -f "$APK" ] || {
    echo "APK not found: $APK" >&2
    exit 1
}

# No `-d`: a downgrade must fail loudly instead of silently replacing a newer build.
adb install -r "$APK"
adb shell dumpsys package deckers.thibault.aves.custom.profile | grep -E "versionCode|versionName"
