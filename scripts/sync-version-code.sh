#!/usr/bin/env sh
# Keep each pubspec's build number (`version: X.Y.Z+N`) in lockstep with the
# Android versionCode in `android/version.properties`.
#
# Single source of truth is `android/version.properties` (auto-incremented by
# `.githooks/pre-commit`). This rewrites ONLY the `+N` part, preserving X.Y.Z,
# across the root pubspec and every flavor manifest. Idempotent: a no-op when
# already in sync.
#
# Usage: sh scripts/sync-version-code.sh
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
props="$root/android/version.properties"

[ -f "$props" ] || { echo "[sync-version] missing $props" >&2; exit 1; }

code=$(sed -n 's/^versionCode=\([0-9][0-9]*\).*/\1/p' "$props")
code=${code:-0}

for pub in "$root/pubspec.yaml" "$root"/flavors/pubspec_*.yaml; do
  [ -f "$pub" ] || continue
  cur=$(sed -n 's/^version:[[:space:]]*//p' "$pub" | head -n1)
  [ -n "$cur" ] || { echo "[sync-version] no 'version:' line in $pub" >&2; exit 1; }
  base=${cur%%+*}
  target="$base+$code"
  [ "$cur" = "$target" ] && continue
  tmp="$pub.tmp"
  sed "s|^version:.*|version: $target|" "$pub" > "$tmp"
  mv "$tmp" "$pub"
  echo "[sync-version] $(basename "$pub"): $cur -> $target"
done
