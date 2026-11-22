#!/bin/sh
# Runs the feature-doc gate on this machine.
#
# CI cannot run it: `quality-check.yml` has no dev-branch trigger, and it reads the
# local docs tree, so the pre-push hook is the only place a register is resolved
# before it leaves the machine. Like the privacy gate, this one stays fail-open on
# a clone without PowerShell, but says so instead of claiming it checked anything.
#
# Arguments are passed through to the checker (`-Range a..b`, `-All`).

root=$(git rev-parse --show-toplevel) || exit 0
cd "$root" || exit 0

if command -v powershell >/dev/null 2>&1; then
    PS=powershell
elif command -v pwsh >/dev/null 2>&1; then
    PS=pwsh
else
    echo "check-feature-docs: no PowerShell found, the docs were not checked" >&2
    exit 0
fi

# -ExecutionPolicy is only meaningful on Windows. PowerShell Core on Unix rejects
# it, so only pass it where the shell is a Windows one.
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        exec "$PS" -NoProfile -ExecutionPolicy Bypass -File scripts/check-feature-docs.ps1 "$@"
        ;;
    *)
        exec "$PS" -NoProfile -File scripts/check-feature-docs.ps1 "$@"
        ;;
esac
