# Audits the feature documentation tree, then resolves the registers a change touched.
#
# `docs/README.md` is the contract the rest of the docs rely on: every slice under
# `lib/features/` is either documented by a `docs/features/<dir>/` or listed with an
# exemption reason. A slice documented as `-` must keep its tests named as behaviour
# sentences, so the exemption is a debt, not a silence. This check also keeps the
# files a shipped register needs (README, spec, rules, one decision) and the
# per-feature wrappers from drifting away from the index.
#
# `-Range a..b` additionally resolves the register of every feature the range
# touched, so a renamed test or a dropped row cannot land while `rules.md` still
# claims it. `-All` resolves every documented register, for a bulk doc pass.
#
# It is not part of `flutter test`: a doc edit should not need the test runner.
# The local hook runs it; CI does not, because `quality-check.yml` has no dev-branch
# trigger.

param(
    [string]$Range,
    [switch]$All,
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

$slicesRoot = Join-Path $Root 'lib/features'
$docsRoot = Join-Path $Root 'docs/features'
$indexPath = Join-Path $Root 'docs/README.md'

foreach ($path in @($slicesRoot, $docsRoot, $indexPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "FAIL: missing $path"
        exit 1
    }
}

$failures = New-Object System.Collections.Generic.List[string]

# --- The index, and the slices it is supposed to cover -------------------------

$slices = @(Get-ChildItem -LiteralPath $slicesRoot -Directory | Select-Object -ExpandProperty Name)
$indexRows = [ordered]@{}

foreach ($line in Get-Content -LiteralPath $indexPath) {
    $trimmed = $line.Trim()
    if (-not $trimmed.StartsWith('|')) { continue }
    if ($trimmed -match '^\|\s*Slice\s*\|') { continue }
    if ($trimmed -match '^\|\s*-{3,}') { continue }

    $cells = $trimmed.Split('|')
    if ($cells.Count -lt 4) { continue }

    $sliceMatch = [regex]::Match($cells[1], '`([^`]+)`')
    if (-not $sliceMatch.Success) { continue }
    $slice = $sliceMatch.Groups[1].Value
    if ($indexRows.Contains($slice)) {
        $failures.Add("docs/README.md lists '$slice' more than once")
        continue
    }
    $indexRows[$slice] = $cells[$cells.Count - 2].Trim()
}

foreach ($slice in $slices) {
    if (-not $indexRows.Contains($slice)) {
        $failures.Add("slice '$slice' has no row in docs/README.md")
    }
}
foreach ($slice in $indexRows.Keys) {
    if ($slices -notcontains $slice) {
        $failures.Add("docs/README.md lists '$slice', but lib/features/$slice does not exist")
    }
}

# --- A documented slice keeps the files a register needs -----------------------

$documented = New-Object System.Collections.Generic.List[string]

foreach ($slice in ($indexRows.Keys | Sort-Object)) {
    $doc = $indexRows[$slice]

    $link = [regex]::Match($doc, '\]\(features/([^)/]+)/README\.md\)')
    if ($link.Success) {
        $name = $link.Groups[1].Value
        $dir = Join-Path $docsRoot $name
        if (-not (Test-Path -LiteralPath $dir)) {
            $failures.Add("'$slice' points at docs/features/$name/, which does not exist")
            continue
        }
        foreach ($required in @('README.md', 'spec.md', 'rules.md')) {
            if (-not (Test-Path -LiteralPath (Join-Path $dir $required))) {
                $failures.Add("docs/features/$name/$required is missing")
            }
        }
        $decisions = @(Get-ChildItem -LiteralPath (Join-Path $dir 'decisions') -File -Filter '*.md' -ErrorAction SilentlyContinue)
        if ($decisions.Count -eq 0) {
            $failures.Add("docs/features/$name/decisions/ has no decision record")
        }
        $documented.Add($name)
        continue
    }

    $exemption = [regex]::Match($doc, '^`-`\s*(\S.*)$')
    if ($exemption.Success -and $exemption.Groups[1].Value.Trim().Length -ge 10) { continue }
    $failures.Add("'$slice' has neither a documentation link nor an exemption reason")
}

foreach ($dir in @(Get-ChildItem -LiteralPath $docsRoot -Directory)) {
    if (-not $documented.Contains($dir.Name)) {
        $failures.Add("docs/features/$($dir.Name)/ is not referenced from docs/README.md")
    }
}

# A register with no data rows passes the per-feature checker trivially, so the
# audit requires at least one.
foreach ($name in ($documented | Sort-Object -Unique)) {
    $rulesPath = Join-Path (Join-Path $docsRoot $name) 'rules.md'
    $rows = @(Get-Content -LiteralPath $rulesPath | Where-Object {
            $trimmed = $_.Trim()
            $trimmed.StartsWith('|') -and $trimmed -notmatch '^\|\s*ID\s*\|' -and $trimmed -notmatch '^\|\s*-{3,}'
        })
    if ($rows.Count -eq 0) {
        $failures.Add("docs/features/$name/rules.md has no rule row")
    }
}

# --- One wrapper per documented register, all of them listed -------------------

$indexContent = Get-Content -LiteralPath $indexPath -Raw
$wrappers = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter 'check-*-rules.ps1' | Where-Object { $_.Name -ne 'check-feature-rules.ps1' })
$covered = New-Object System.Collections.Generic.List[string]
$wrapperByFeature = @{}

foreach ($wrapper in $wrappers) {
    if (-not $indexContent.Contains($wrapper.Name)) {
        $failures.Add("docs/README.md does not list $($wrapper.Name)")
    }

    $content = Get-Content -LiteralPath $wrapper.FullName -Raw
    # Thin wrappers pass `-Feature`; the older self-contained ones spell the dir out.
    $match = [regex]::Match($content, "-Feature\s+'([^']+)'")
    if (-not $match.Success) {
        $match = [regex]::Match($content, "docs/features/([a-z0-9_-]+)")
    }
    if (-not $match.Success) {
        $failures.Add("$($wrapper.Name) does not name the feature it resolves")
        continue
    }

    $name = $match.Groups[1].Value
    if (-not (Test-Path -LiteralPath (Join-Path $docsRoot $name))) {
        $failures.Add("$($wrapper.Name) points at docs/features/$name, which does not exist")
        continue
    }
    # A wrapper carries the feature's own extra guards (`C1`, `C13`, quoted test
    # names), so it resolves the register, not the generic checker.
    $wrapperByFeature[$name] = $wrapper.FullName
    $covered.Add($name)
}

foreach ($name in ($documented | Sort-Object -Unique)) {
    if (-not $covered.Contains($name)) {
        $failures.Add("docs/features/$name/ has no check-*-rules.ps1 wrapper")
    }
}

# --- Registers the change touched ---------------------------------------------

$toResolve = @()
if ($All) {
    $toResolve = @(Get-ChildItem -LiteralPath $docsRoot -Directory | Select-Object -ExpandProperty Name)
} elseif ($Range) {
    $touched = & git -C $Root diff --name-only $Range
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("git diff --name-only $Range failed")
    } else {
        $toResolve = @($touched |
                ForEach-Object { if ($_ -match '^docs/features/([^/]+)/') { $Matches[1] } } |
                Sort-Object -Unique)
    }
}

$resolvedRegisters = 0
foreach ($name in $toResolve) {
    # A removed slice is not a register to resolve; the index audit above catches
    # the stale row it would leave behind.
    if (-not (Test-Path -LiteralPath (Join-Path $docsRoot $name))) { continue }

    $wrapper = $wrapperByFeature[$name]
    if ($wrapper) {
        & $wrapper -Root $Root
    } else {
        & (Join-Path $PSScriptRoot 'check-feature-rules.ps1') -Feature $name -Root $Root
    }
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("the register in docs/features/$name does not resolve")
    } else {
        $resolvedRegisters++
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" }
    Write-Host "FAIL: $($failures.Count) problem(s)"
    exit 1
}

Write-Host "OK: $($slices.Count) slice(s), $($documented.Count) documented slice(s), $($wrappers.Count) wrapper(s), $resolvedRegisters register(s) resolved, every exemption carries a reason"
exit 0
