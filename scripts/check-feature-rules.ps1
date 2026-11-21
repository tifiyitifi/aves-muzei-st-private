# Resolves one feature's rule register against the tests it claims.
#
# A `rules.md` row is only useful if it cannot claim coverage it does not have.
# This check parses every `F:<stem>#<test name>` token, finds the test file under
# `test/`, and confirms a `test('<name>'` or `testWidgets('<name>'` call exists.
# It also resolves every `decisions/NNNN-*.md` link in the feature docs.
#
# `M` (needs a human on a device) and `-:<reason>` (deliberately unfalsified) are
# accepted; the reason must be non-empty. It is not part of `flutter test`: a doc
# edit should not need the test runner.
#
# Called by the per-feature wrappers (`check-media-ops-rules.ps1`, ...), which
# keep the same invocation shape as the older single-feature scripts.

param(
    [Parameter(Mandatory = $true)][string]$Feature,
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

$featureDir = Join-Path $Root "docs/features/$Feature"
$rulesPath = Join-Path $featureDir 'rules.md'
$testRoot = Join-Path $Root 'test'

if (-not (Test-Path -LiteralPath $rulesPath)) {
    Write-Host "FAIL: missing $rulesPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $testRoot)) {
    Write-Host "FAIL: missing $testRoot"
    exit 1
}

$failures = New-Object System.Collections.Generic.List[string]
$resolved = 0
$unfalsified = 0

foreach ($line in Get-Content -LiteralPath $rulesPath) {
    $trimmed = $line.Trim()
    if (-not $trimmed.StartsWith('|')) { continue }
    if ($trimmed -match '^\|\s*ID\s*\|') { continue }
    if ($trimmed -match '^\|\s*-{3,}') { continue }

    $cells = $trimmed.Split('|')
    if ($cells.Count -lt 4) { continue }

    $id = $cells[1].Trim()
    $coverage = $cells[$cells.Count - 2].Trim()
    if ([string]::IsNullOrEmpty($id)) { continue }
    if ([string]::IsNullOrEmpty($coverage)) {
        $failures.Add("row $id has no coverage token")
        continue
    }

    foreach ($rawToken in $coverage.Split(';')) {
        $token = $rawToken.Trim().Trim('`').Trim()
        if ([string]::IsNullOrEmpty($token)) { continue }

        if ($token -eq 'M') {
            $unfalsified++
            continue
        }
        if ($token.StartsWith('-:')) {
            if ($token.Length -le 2) {
                $failures.Add("row $id has an empty unfalsified reason")
            } else {
                $unfalsified++
            }
            continue
        }
        if (-not $token.StartsWith('F:')) {
            $failures.Add("row $id has an unknown token: $token")
            continue
        }

        $body = $token.Substring(2)
        $hash = $body.IndexOf('#')
        if ($hash -lt 1 -or $hash -eq $body.Length - 1) {
            $failures.Add("row $id has a malformed token: $token")
            continue
        }
        $stem = $body.Substring(0, $hash)
        $name = $body.Substring($hash + 1)
        $files = @(Get-ChildItem -LiteralPath $testRoot -Recurse -File -Filter "$stem.dart" -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) {
            $failures.Add("row ${id}: no test file '$stem.dart'")
            continue
        }
        $needles = @("test('$name'", "testWidgets('$name'")
        $found = $false
        foreach ($file in $files) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($needle in $needles) {
                if ($content.Contains($needle)) {
                    $found = $true
                    break
                }
            }
            if ($found) { break }
        }
        if (-not $found) {
            $failures.Add("row ${id}: no test named '$name' in $stem.dart")
            continue
        }
        $resolved++
    }
}

$linkPattern = 'decisions/([0-9]{4}-[a-z0-9-]+\.md)'
foreach ($file in @(Get-ChildItem -LiteralPath $featureDir -Recurse -File -Filter '*.md')) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($link in [regex]::Matches($content, $linkPattern)) {
        $target = Join-Path (Join-Path $featureDir 'decisions') $link.Groups[1].Value
        if (-not (Test-Path -LiteralPath $target)) {
            $failures.Add("$($file.Name): missing decision '$($link.Groups[1].Value)'")
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" }
    Write-Host "FAIL: $($failures.Count) problem(s)"
    exit 1
}

Write-Host "OK: $resolved test token(s), $unfalsified unfalsified row(s), every decision link resolves"
exit 0
