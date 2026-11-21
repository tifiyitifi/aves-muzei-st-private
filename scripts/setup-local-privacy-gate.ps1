# Prepares this clone for the local privacy gate.
#
# The hooks themselves are tracked in .githooks/ and are already active when
# core.hooksPath points there. The one thing that cannot be tracked is the deny
# list: it names this machine and its owner, so it lives under the gitignored
# .ai_tmp/. This script scaffolds it from the tracked example (never overwriting
# a filled-in list), adds the machine account name, and checks the hook path.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-local-privacy-gate.ps1

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$denyDir = Join-Path $root ".ai_tmp/local_text"
$denyFile = Join-Path $denyDir "deny-list.txt"
$example = Join-Path $root "scripts/local-gate-deny-list.example.txt"

if (-not (Test-Path -LiteralPath $denyDir)) {
    New-Item -ItemType Directory -Path $denyDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $denyFile)) {
    if (Test-Path -LiteralPath $example) {
        Copy-Item -LiteralPath $example -Destination $denyFile
        Write-Host "created: $denyFile (add private terms there; it is gitignored)"
    } else {
        Write-Host "warning: missing $example; the deny list was not created"
    }
} else {
    Write-Host "kept: $denyFile"
}

# The account name is the most likely word to survive a pasted path that lost
# its drive letter, but deny-list terms are case-insensitive substrings: a short
# or common account name would block ordinary words in every edited file. Leave
# the choice (and the wording) to the user instead of writing it automatically.
if ((Test-Path -LiteralPath $denyFile) -and $env:USERNAME) {
    Write-Host "note: add your machine account to $denyFile only if it is not a common word (deny-list terms are case-insensitive substrings)"
}

$hooks = git -C $root config --get core.hooksPath 2>$null
if ($hooks -ne ".githooks") {
    Write-Host "warning: core.hooksPath is '$hooks'; run: git config core.hooksPath .githooks"
} else {
    Write-Host "hooks: core.hooksPath = .githooks"
}
