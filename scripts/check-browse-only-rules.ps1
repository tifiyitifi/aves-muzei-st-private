param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

& (Join-Path $PSScriptRoot 'check-feature-rules.ps1') -Feature 'browse_only' -Root $Root
exit $LASTEXITCODE
