# Exercises scripts/check-local-paths.ps1 against throwaway repositories.
#
# The declaration of locale-independent paths is intentional: this file is
# audited by the gate too, so path samples are assembled at run time instead of
# being written literally.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-local-privacy-gate.ps1
#
# Exit code 0 means every case answered as declared; 1 means at least one did
# not, and 2 means the test itself could not run.

$ErrorActionPreference = "Stop"

$checker = Join-Path $PSScriptRoot "check-local-paths.ps1"
if (-not (Test-Path -LiteralPath $checker)) {
    Write-Host "FAIL: missing $checker"
    exit 2
}

$BS = [string][char]92
$FS = [string][char]47
$C = [string][char]67
$D = [string][char]68

$script:failures = 0

function New-TestRepo {
    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("aves-gate-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    & git -C $repo init -q
    & git -C $repo config user.email "test@example.com"
    & git -C $repo config user.name "test"
    & git -C $repo config commit.gpgsign "false"
    & git -C $repo config core.autocrlf "false"
    & git -C $repo config core.hooksPath ".git/hooks"
    return $repo
}

function Remove-TestRepo {
    param([string]$Repo)
    if (Test-Path -LiteralPath $Repo) {
        Remove-Item -LiteralPath $Repo -Recurse -Force
    }
}

function Write-File {
    param([string]$Repo, [string]$RelativePath, [string]$Content)
    $full = Join-Path $Repo $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($full, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-File {
    param([string]$Repo, [string]$RelativePath, [string]$Content)
    Write-File -Repo $Repo -RelativePath $RelativePath -Content $Content
    & git -C $Repo add -- $RelativePath
}

function Invoke-Checker {
    param(
        [string]$Repo,
        [switch]$All,
        [switch]$Pushed,
        [switch]$Message,
        [string]$Range = "",
        [hashtable]$EnvVars = @{}
    )

    $checkArgs = @{}
    if ($All) { $checkArgs['All'] = $true }
    if ($Pushed) { $checkArgs['Pushed'] = $true }
    if ($Message) { $checkArgs['Message'] = $true }
    if ($Range) { $checkArgs['Range'] = $Range }

    $saved = @{}
    foreach ($key in $EnvVars.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, $EnvVars[$key], "Process")
    }
    try {
        $output = (& $checker -Root $Repo @checkArgs 6>&1 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } finally {
        foreach ($key in $EnvVars.Keys) {
            [Environment]::SetEnvironmentVariable($key, $saved[$key], "Process")
        }
    }
    return [pscustomobject]@{ Code = $code; Output = $output }
}

function Assert-Check {
    param([string]$Name, $Result, [int]$ExpectedCode, [string]$ExpectedOutput = "")

    $ok = ($Result.Code -eq $ExpectedCode)
    if ($ok -and $ExpectedOutput) {
        $ok = $Result.Output.Contains($ExpectedOutput)
    }
    if ($ok) {
        Write-Host "ok: $Name"
    } else {
        $script:failures++
        Write-Host "FAIL: $Name (expected $ExpectedCode, got $($Result.Code))"
        Write-Host $Result.Output
    }
}

# A staged stand-in path passes; a missing deny list is only a warning.
$repo = New-TestRepo
try {
    Add-File $repo "note.md" ("clip at " + $C + ":" + $BS + "work" + $BS + "a.mp4")
    $result = Invoke-Checker $repo
    Assert-Check "a stand-in path passes" $result 0 "deny list not found"
} finally { Remove-TestRepo $repo }

# A real path is rejected.
$repo = New-TestRepo
try {
    Add-File $repo "note.md" ("clip at " + $C + ":" + $BS + "Users" + $BS + "someone" + $BS + "a.mp4")
    $result = Invoke-Checker $repo
    Assert-Check "a real path is rejected" $result 1 "local path"
} finally { Remove-TestRepo $repo }

# This machine's profile is caught even under an accepted stand-in root.
$repo = New-TestRepo
try {
    $profile = $C + ":" + $BS + "work" + $BS + "gate-profile"
    Add-File $repo "note.md" ("clip at " + $profile + $BS + "videos" + $BS + "a.mp4")
    $result = Invoke-Checker $repo -EnvVars @{ USERPROFILE = $profile; HOME = $profile }
    Assert-Check "the machine profile is caught" $result 1 "local machine path"
} finally { Remove-TestRepo $repo }

# A deny-list term is rejected; the list itself is local and never staged.
$repo = New-TestRepo
try {
    Write-File -Repo $repo -RelativePath ".ai_tmp/local_text/deny-list.txt" -Content "SecretProject`n"
    Add-File $repo "note.md" "the SecretProject folder"
    $result = Invoke-Checker $repo
    Assert-Check "a deny-list term is rejected" $result 1 "private term"
} finally { Remove-TestRepo $repo }

# A path in the commit message is rejected.
$repo = New-TestRepo
try {
    Write-File -Repo $repo -RelativePath ".git/COMMIT_EDITMSG" -Content ("subject " + $C + ":" + $BS + "Users" + $BS + "someone" + $BS + "a.mp4" + "`n")
    $result = Invoke-Checker $repo -Message
    Assert-Check "a path in the commit message is rejected" $result 1 "the commit message"
} finally { Remove-TestRepo $repo }

# The exact push range is checked.
$repo = New-TestRepo
try {
    Add-File $repo "a.md" "one`n"
    & git -C $repo commit -q -m "one"
    $first = (& git -C $repo rev-parse HEAD).Trim()
    Add-File $repo "b.md" ("two " + $C + ":" + $BS + "Users" + $BS + "someone" + $BS + "b.mp4")
    & git -C $repo commit -q -m "two"
    $second = (& git -C $repo rev-parse HEAD).Trim()
    $result = Invoke-Checker $repo -Pushed -Range "$first..$second"
    Assert-Check "the exact push range is checked" $result 1 "local path"
} finally { Remove-TestRepo $repo }

# A new branch with no upstream still has its earlier commits checked.
$repo = New-TestRepo
try {
    Add-File $repo "base.md" "base`n"
    & git -C $repo commit -q -m "base"
    & git -C $repo checkout -q -b feature
    Add-File $repo "leak.md" ("leak " + $C + ":" + $BS + "Users" + $BS + "someone" + $BS + "a.mp4")
    & git -C $repo commit -q -m "leak"
    Add-File $repo "clean.md" "clean`n"
    & git -C $repo commit -q -m "clean"
    $result = Invoke-Checker $repo -Pushed
    Assert-Check "earlier commits of a new branch are checked" $result 1 "local path"
} finally { Remove-TestRepo $repo }

# -All only warns about a path that is already committed.
$repo = New-TestRepo
try {
    Add-File $repo "a.md" ("one " + $D + ":" + $BS + "personal" + $BS + "a.mp4")
    & git -C $repo commit -q -m "one"
    $result = Invoke-Checker $repo -All
    Assert-Check "an already committed path only warns" $result 0 "audit:"
} finally { Remove-TestRepo $repo }

# A local data file is rejected by name.
$repo = New-TestRepo
try {
    Add-File $repo ".ai_tmp/note.txt" "x`n"
    $result = Invoke-Checker $repo
    Assert-Check "an .ai_tmp file name is rejected" $result 1 "local data in a file name"
} finally { Remove-TestRepo $repo }

# The tracked shared tooling under .ai_tmp/_common is allowed.
$repo = New-TestRepo
try {
    Add-File $repo ".ai_tmp/_common/tool.sh" "#!/bin/sh`n"
    $result = Invoke-Checker $repo
    Assert-Check "the .ai_tmp/_common tooling is allowed" $result 0 "OK: nothing local"
} finally { Remove-TestRepo $repo }

# A signing properties file is local data.
$repo = New-TestRepo
try {
    Add-File $repo "android/key.properties" "storePassword=secret`n"
    $result = Invoke-Checker $repo
    Assert-Check "key.properties is local data" $result 1 "local data in a file name"
} finally { Remove-TestRepo $repo }

# The tracked template with placeholders is not.
$repo = New-TestRepo
try {
    Add-File $repo "android/key_template.properties" "storeFile=<KEYSTORE_PATH>`n"
    $result = Invoke-Checker $repo
    Assert-Check "key_template.properties is allowed" $result 0 "OK: nothing local"
} finally { Remove-TestRepo $repo }

# An angle-bracket user placeholder is allowed.
$repo = New-TestRepo
try {
    Add-File $repo "note.md" ("sdk at " + $C + ":" + $BS + "Users" + $BS + "<username>" + $BS + "AppData")
    $result = Invoke-Checker $repo
    Assert-Check "an angle-bracket user placeholder is allowed" $result 0 "OK: nothing local"
} finally { Remove-TestRepo $repo }

# An escaped regex sequence is not a drive path.
$repo = New-TestRepo
try {
    $escaped = $BS + $BS + "d" + $BS + $BS + "d" + ":" + $BS + "d" + $BS + $BS + "d"
    Add-File $repo "Helper.kt" ("val p = Pattern.compile(`"(" + $escaped + ")`")`n")
    $result = Invoke-Checker $repo
    Assert-Check "an escaped regex sequence is not a path" $result 0 "OK: nothing local"
} finally { Remove-TestRepo $repo }

# A relative Dart import that contains /home/ is not an absolute home.
$repo = New-TestRepo
try {
    Add-File $repo "lib/x.dart" ("import 'package:aves/widgets" + $FS + "home" + $FS + "home_page.dart';`n")
    $result = Invoke-Checker $repo
    Assert-Check "a Dart home import is not a path" $result 0 "OK: nothing local"
} finally { Remove-TestRepo $repo }

# A fixture root is accepted in a test, but not in ordinary source.
$phone = $D + ":" + $BS + "phone" + $BS + "Pictures" + $BS + "a"
$repo = New-TestRepo
try {
    Add-File $repo "test/x_test.dart" ("expect(isPath(r'" + $phone + "'), isTrue);`n")
    $result = Invoke-Checker $repo
    Assert-Check "a fixture root is allowed in a test" $result 0 "OK: nothing local"
} finally { Remove-TestRepo $repo }
$repo = New-TestRepo
try {
    Add-File $repo "lib/x.dart" ("var p = r'" + $phone + "';`n")
    $result = Invoke-Checker $repo
    Assert-Check "a fixture root outside a test is local" $result 1 "local path"
} finally { Remove-TestRepo $repo }

# The upstream maintainer's documented home is public.
$repo = New-TestRepo
try {
    Add-File $repo "doc.md" ("bundle at " + $FS + "home" + $FS + "tibo" + $FS + "Downloads" + $FS + "a.aab")
    $result = Invoke-Checker $repo
    Assert-Check "the documented maintainer home is allowed" $result 0 "OK: nothing local"
} finally { Remove-TestRepo $repo }

# A real Unix home is not.
$repo = New-TestRepo
try {
    Add-File $repo "doc.md" ("clip at " + $FS + "home" + $FS + "someone" + $FS + "a.mp4")
    $result = Invoke-Checker $repo
    Assert-Check "a real Unix home is local" $result 1 "local path"
} finally { Remove-TestRepo $repo }

if ($script:failures -gt 0) {
    Write-Host ("FAIL: {0} case(s) did not answer as declared" -f $script:failures)
    exit 1
}

Write-Host "OK: all local privacy gate cases passed"
exit 0
