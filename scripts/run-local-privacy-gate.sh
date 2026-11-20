#!/bin/sh
# Runs the local privacy gate on this machine.
#
# The deny list that scripts/check-local-paths.ps1 reads is gitignored, so CI
# cannot run the check: the only place it can run is a hook on this machine.
# The hooks stay fail-open: a clone without PowerShell still commits, but says
# so instead of claiming the change was checked.
#
# Arguments are passed through to the checker (-Message, -Pushed, -Range ...).

root=$(git rev-parse --show-toplevel) || exit 0
cd "$root" || exit 0

if command -v powershell >/dev/null 2>&1; then
    PS=powershell
elif command -v pwsh >/dev/null 2>&1; then
    PS=pwsh
else
    echo "check-local-paths: no PowerShell found, the change was not checked" >&2
    exit 0
fi

# -ExecutionPolicy is only meaningful on Windows. PowerShell Core on Unix
# rejects it, so only pass it where the shell is a Windows one.
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        exec "$PS" -NoProfile -ExecutionPolicy Bypass -File scripts/check-local-paths.ps1 "$@"
        ;;
    *)
        exec "$PS" -NoProfile -File scripts/check-local-paths.ps1 "$@"
        ;;
esac
