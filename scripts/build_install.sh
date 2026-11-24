#!/usr/bin/env sh
# Build a flavor/mode APK split per ABI and install the one matching the connected device.
# The committed root pubspec is the custom flavor, so custom needs no flavor swap.
set -eu

if [ ! -d "scripts" ]; then
    cd ..
fi

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/build_install.sh [debug|profile|release] [options]

Build a flavor/mode APK split per ABI and install the one matching the
connected Android device.

Arguments:
  debug|profile|release   Build mode (default: profile)
Options:
  --flavor FLAVOR         play | izzy | libre | custom (default: custom)
  --serial SERIAL         Target device when several are connected
  --codegen               Run build_runner before the build
  --dry-run               Print the detected target and commands, then exit
  -h, --help              Show this help
EOF
}

MODE=profile
FLAVOR=custom
SERIAL=
DO_CODEGEN=false
DRY_RUN=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        debug|profile|release)
            MODE=$1
            shift
            ;;
        --flavor)
            [ "$#" -ge 2 ] || die "--flavor needs a value"
            FLAVOR=$2
            shift 2
            ;;
        --flavor=*)
            FLAVOR=${1#--flavor=}
            shift
            ;;
        --serial)
            [ "$#" -ge 2 ] || die "--serial needs a value"
            SERIAL=$2
            shift 2
            ;;
        --serial=*)
            SERIAL=${1#--serial=}
            shift
            ;;
        --codegen)
            DO_CODEGEN=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

case "$FLAVOR" in
    play|izzy|libre|custom) ;;
    *) die "unsupported flavor: $FLAVOR" ;;
esac

command -v adb >/dev/null 2>&1 || die "adb not found in PATH"

DEVICE_OUTPUT=$(adb devices | tr -d '\r')
READY=$(printf '%s\n' "$DEVICE_OUTPUT" | awk 'NR > 1 && $2 == "device" { print $1 }')
NOT_READY=$(printf '%s\n' "$DEVICE_OUTPUT" | awk 'NR > 1 && ($2 == "unauthorized" || $2 == "offline") { print $1 " (" $2 ")" }')

if [ -n "$NOT_READY" ]; then
    echo "warning: device(s) not ready: $NOT_READY" >&2
fi

if [ -z "$SERIAL" ]; then
    set -- $READY
    [ "$#" -gt 0 ] || die "no connected device is ready for adb"
    [ "$#" -eq 1 ] || die "several devices are ready: $READY (use --serial SERIAL)"
    SERIAL=$1
else
    printf '%s\n' "$READY" | grep -qx "$SERIAL" || die "device is not ready: $SERIAL"
fi

supported_abi() {
    case "$1" in
        arm64-v8a|armeabi-v7a|x86_64)
            printf '%s' "$1"
            ;;
        *)
            printf ''
            ;;
    esac
}

RAW_ABI=$(adb -s "$SERIAL" shell getprop ro.product.cpu.abi | tr -d '\r')
ABI=$(supported_abi "$RAW_ABI")
if [ -z "$ABI" ]; then
    ABILIST=$(adb -s "$SERIAL" shell getprop ro.product.cpu.abilist | tr -d '\r')
    OLD_IFS=$IFS
    IFS=,
    for candidate in $ABILIST; do
        ABI=$(supported_abi "$candidate")
        [ -z "$ABI" ] || break
    done
    IFS=$OLD_IFS
fi
[ -n "$ABI" ] || die "unsupported device ABI: '$RAW_ABI' (abilist: '${ABILIST:-}')"

# A flavor swap overwrites tracked root files; require it to be applied first.
cmp -s pubspec.yaml "flavors/pubspec_$FLAVOR.yaml" || die "root pubspec is not the $FLAVOR flavor; run scripts/apply_flavor_$FLAVOR.sh first"
cmp -s pubspec.lock "flavors/pubspec_$FLAVOR.lock" || die "root pubspec.lock is not the $FLAVOR flavor; run scripts/apply_flavor_$FLAVOR.sh first"
[ -f "lib/main_$FLAVOR.dart" ] || die "entrypoint not found: lib/main_$FLAVOR.dart"

if [ "$MODE" = release ]; then
    RELEASE_SIGNED=false
    if [ -f android/key.properties ]; then
        RELEASE_SIGNED=true
    elif [ -n "${AVES_STORE_FILE:-}" ] && [ -n "${AVES_STORE_PASSWORD:-}" ] && [ -n "${AVES_KEY_ALIAS:-}" ] && [ -n "${AVES_KEY_PASSWORD:-}" ]; then
        RELEASE_SIGNED=true
    fi
    [ "$RELEASE_SIGNED" = true ] || die "release needs android/key.properties or AVES_STORE_FILE/AVES_STORE_PASSWORD/AVES_KEY_ALIAS/AVES_KEY_PASSWORD; refusing to build an unsigned APK"
fi

case "$FLAVOR" in
    libre)  BASE_PACKAGE=deckers.thibault.aves.libre ;;
    custom) BASE_PACKAGE=deckers.thibault.aves.custom ;;
    *)      BASE_PACKAGE=deckers.thibault.aves ;;
esac
case "$MODE" in
    debug)   PACKAGE=$BASE_PACKAGE.debug ;;
    profile) PACKAGE=$BASE_PACKAGE.profile ;;
    release) PACKAGE=$BASE_PACKAGE ;;
esac

APK="build/app/outputs/flutter-apk/app-$ABI-$FLAVOR-$MODE.apk"

if [ "$DRY_RUN" = true ]; then
    echo "device: $SERIAL ($RAW_ABI -> $ABI)"
    echo "flavor: $FLAVOR, mode: $MODE, package: $PACKAGE"
    echo "commands:"
    if [ "$DO_CODEGEN" = true ]; then
        echo "  ./flutterw pub run build_runner build --delete-conflicting-outputs"
    fi
    echo "  ./flutterw gen-l10n"
    echo "  ./flutterw build apk --$MODE --flavor $FLAVOR -t lib/main_$FLAVOR.dart --split-per-abi"
    echo "  adb -s $SERIAL install -r $APK"
    echo "  adb -s $SERIAL shell dumpsys package $PACKAGE"
    exit 0
fi

if [ "$DO_CODEGEN" = true ]; then
    ./flutterw pub run build_runner build --delete-conflicting-outputs
fi
./flutterw gen-l10n

LOG=$(mktemp)
INSTALL_LOG=$(mktemp)
trap 'rm -f "$LOG" "$INSTALL_LOG"' EXIT INT TERM

set +e
./flutterw build apk "--$MODE" --flavor "$FLAVOR" -t "lib/main_$FLAVOR.dart" --split-per-abi > "$LOG" 2>&1
BUILD_STATUS=$?
set -e
cat "$LOG"
[ "$BUILD_STATUS" -eq 0 ] || die "build failed with status $BUILD_STATUS"

# The version code offset proves the ABI split was applied for this device.
EXPECTED=$(sed -n "s/.*output versionCodeOverride=\([0-9][0-9]*\) for abi=$ABI.*/\1/p" "$LOG" | head -n 1)
[ -n "$EXPECTED" ] || die "ABI version code offset was not applied for abi=$ABI; refusing to install"

[ -f "$APK" ] || {
    echo "candidate APKs:" >&2
    ls build/app/outputs/flutter-apk/*.apk >&2 2>/dev/null || :
    die "APK not found: $APK"
}

set +e
adb -s "$SERIAL" install -r "$APK" > "$INSTALL_LOG" 2>&1
INSTALL_STATUS=$?
set -e
cat "$INSTALL_LOG"
if [ "$INSTALL_STATUS" -ne 0 ]; then
    if grep -qiE 'INSTALL_FAILED_(UPDATE_INCOMPATIBLE|DOWNGRADE)|signature' "$INSTALL_LOG"; then
        echo "hint: signature conflict or downgrade; 'adb -s $SERIAL uninstall $PACKAGE' clears that app's data" >&2
    fi
    exit "$INSTALL_STATUS"
fi

INFO=$(adb -s "$SERIAL" shell dumpsys package "$PACKAGE" | tr -d '\r')
ACTUAL=$(printf '%s\n' "$INFO" | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
VERSION=$(printf '%s\n' "$INFO" | sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -n 1)
echo "installed $PACKAGE versionName=$VERSION versionCode=$ACTUAL"
[ "$ACTUAL" = "$EXPECTED" ] || die "versionCode mismatch: installed $ACTUAL, build reported $EXPECTED"
