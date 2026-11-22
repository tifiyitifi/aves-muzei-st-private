param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

& (Join-Path $PSScriptRoot 'check-feature-rules.ps1') -Feature 'meta_settings' -Root $Root
exit $LASTEXITCODE
