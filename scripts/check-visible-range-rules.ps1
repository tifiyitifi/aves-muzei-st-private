param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

& (Join-Path $PSScriptRoot 'check-feature-rules.ps1') -Feature 'visible_range' -Root $Root
exit $LASTEXITCODE
