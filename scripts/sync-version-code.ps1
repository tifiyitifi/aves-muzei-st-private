#Requires -Version 7
<#
.SYNOPSIS
  Sync every pubspec's build number (+N) to the Android versionCode.

.DESCRIPTION
  Windows twin of scripts/sync-version-code.sh. The single source of truth is
  android/version.properties; this rewrites ONLY the `+N` part of
  `version: X.Y.Z+N`, preserving X.Y.Z, in the root pubspec and every flavor
  manifest. Idempotent: a no-op when already in sync.

.EXAMPLE
  pwsh -NoProfile -File scripts/sync-version-code.ps1
#>
$ErrorActionPreference = 'Stop'

$root = (git rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }

$props = Join-Path $root 'android/version.properties'
if (-not (Test-Path -LiteralPath $props)) { throw "[sync-version] missing $props" }

$m = Select-String -LiteralPath $props -Pattern '^versionCode=(\d+)' | Select-Object -First 1
$code = if ($m) { $m.Matches[0].Groups[1].Value } else { '0' }

$files = @((Join-Path $root 'pubspec.yaml'))
$flavorDir = Join-Path $root 'flavors'
if (Test-Path -LiteralPath $flavorDir) {
    $files += Get-ChildItem -LiteralPath $flavorDir -Filter 'pubspec_*.yaml' | ForEach-Object { $_.FullName }
}

foreach ($pub in $files) {
    if (-not (Test-Path -LiteralPath $pub)) { continue }
    $raw = Get-Content -LiteralPath $pub -Raw
    $v = [regex]::Match($raw, '(?m)^version:[ \t]*([^\r\n]+)')
    if (-not $v.Success) { throw "[sync-version] no 'version:' line in $pub" }
    $cur = $v.Groups[1].Value.Trim()
    $base = ($cur -split '\+')[0]
    $target = "$base+$code"
    if ($cur -eq $target) { continue }
    $newRaw = $raw.Substring(0, $v.Index) + "version: $target" + $raw.Substring($v.Index + $v.Length)
    # WriteAllText keeps LF (no BOM); Set-Content would normalize line endings.
    [System.IO.File]::WriteAllText($pub, $newRaw)
    Write-Host "[sync-version] $(Split-Path -Leaf $pub): $cur -> $target"
}
