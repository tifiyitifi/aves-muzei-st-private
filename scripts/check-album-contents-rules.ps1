param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

& (Join-Path $PSScriptRoot 'check-feature-rules.ps1') -Feature 'album_contents_transfer' -Root $Root
exit $LASTEXITCODE
