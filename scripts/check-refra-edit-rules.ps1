param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

& (Join-Path $PSScriptRoot 'check-feature-rules.ps1') -Feature 'refra_edit' -Root $Root
exit $LASTEXITCODE
