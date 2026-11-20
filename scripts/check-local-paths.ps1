# Checks that local, private material is not about to be committed.
#
# The repository is shared and may be published; the machine it is built on is
# not. Three shapes must never reach a tracked file or a commit message:
#
#   1. a local path        a drive letter with a separator, a UNC share, a home
#                          directory or a leading `~/`
#   2. local data          a signing or settings file, a database, an APK, a
#                          log, or anything under `.ai_tmp/` except the tracked
#                          shared tooling in `.ai_tmp/_common/`
#   3. a private term      a real folder or media title; the list is
#                          `.ai_tmp/local_text/deny-list.txt`
#
# Modes:
#
#   (default)   check what is staged, file names included. If nothing is
#               staged, check the working diff of tracked files. A staged binary
#               file is named in a warning: its bytes are never read, only its
#               name is checked.
#   -All        audit every tracked file. A path that is already committed is a
#               warning, not a failure, so the mode stays usable as an audit.
#   -Pushed     check the commits that are about to leave the machine. The
#               pre-push hook passes the exact `<remote sha>..<local sha>`
#               range git reported, so only what this push publishes is read;
#               without a range the branch upstream (or the default branch) is
#               used. Unlike -All, a path here is a failure: it belongs to this
#               push.
#   -Message    check the message git just wrote. It is found with
#               `git rev-parse --git-path COMMIT_EDITMSG`, because a linked
#               worktree keeps it under the main repository's .git, not beside
#               the sources.
#
# The stand-in roots are a deliberate trade-off. The repository quotes tool
# paths (Flutter, the Android SDK, Windows) and its tests use a small set of
# fixture roots, so those roots are accepted. A real name below one of them is
# not detectable here; the deny list covers it. The upstream maintainer's
# documented home directory is accepted in the same spirit, but only as a path
# prefix, never as a deny-list term: short names collide with ordinary prose.
#
# The script is deliberately plain ASCII: Windows PowerShell 5.1 reads a .ps1
# without a byte-order mark in the system code page, so a pattern written with a
# literal non-ASCII character silently becomes a different pattern there, and the
# check then passes on everything. Samples are assembled at run time for the
# same reason, and the self-test below fails loudly if a pattern ever stops
# matching what it is supposed to.
#
# Exit code 1 means something it must not. Exit code 2 means the check itself is
# broken (a pattern or a filter no longer answers its sample).

param(
    [switch]$All,
    [switch]$Pushed,
    [switch]$Message,
    [string]$Range = "",
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

# Git writes paths and diff text as UTF-8; 5.1 reads native output with the
# console encoding, so name the encoding instead of hoping for the default.
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
    # No console attached; git output is then decoded with the default.
}

# -Root exists for the test suite, which runs the script against a throwaway
# repository. The hooks never pass it.
if (-not $Root) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$root = [System.IO.Path]::GetFullPath($Root)
$denyList = Join-Path $root ".ai_tmp/local_text/deny-list.txt"

# A drive letter followed by a separator, a UNC share, a home directory or a
# leading `~/`. A bare drive letter in prose is not matched. A drive letter that
# is preceded by a backslash is an escaped regex sequence, not a path.
#
# The roots in $publicRoot name a tool or a documented stand-in. Anything else
# after a drive letter is local.
$publicRoot = '(Program Files|Windows|work|library|comics|videos|inbox|batch|clips)'
# The rest of the stand-in roots are a path spelled inside a test string, not a
# place on a disk, so the form is pinned to a forward slash. The same words
# written with backslashes - the way a real scratch folder is spelled - are
# still local.
$fixtureRoot = '(tmp|temp|out|another)'
# Fixture roots accepted only inside a test file or the test driver.
$testRoot = '(phone|tmp|temp|out|another|src|work)'
$pathPattern = ('(?<![\\])\b[A-Za-z]:[\\/][^\s"''`)>]+' +
    '|\\\\[A-Za-z0-9][A-Za-z0-9._$-]{1,}[\\/][^\s"''`)>]*' +
    '|(^|[\s"''(])~[\\/][^\s"''`)>]+' +
    '|(?<![\w./-])/(Users|home)/[A-Za-z0-9._-]+')

# Files whose very presence in a commit is the leak. The shared tooling under
# `.ai_tmp/_common/` is tracked, so it is excluded.
$dataPattern = ('(^|/)(key|local)\.properties$' +
    '|(^|/)deny-list\.txt$' +
    '|\.(apk|aab|jks|db|sqlite|db-wal|db-shm|log)$' +
    '|^\.ai_tmp/(?!_common/)')

# Text files worth reading in audit mode. Generated code is included because a
# pasted path can survive a generated comment; a false positive there is still
# a path in a tracked file.
$textFilePattern = '\.(md|txt|json|ps1|psm1|sh|dart|kt|java|kts|gradle|properties|arb|xml|yml|yaml|toml|csv|html|css|py)$'

$deny = @()
$denyMissing = -not (Test-Path -LiteralPath $denyList)
if (-not $denyMissing) {
    $deny = Get-Content -Path $denyList -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
}

# The machine's own profile and this checkout are local even when their root
# happens to be on the stand-in list. A generic placeholder account is skipped
# so the fixtures keep working.
$machinePrefixes = New-Object System.Collections.Generic.List[string]
foreach ($candidate in @($env:USERPROFILE, $env:HOME)) {
    if (-not $candidate) { continue }
    $full = [System.IO.Path]::GetFullPath($candidate).TrimEnd([char[]]'\/')
    $name = Split-Path -Leaf $full
    if ($name -in @('%USERNAME%', '<username>', 'u', 'user', 'me', 'someone')) { continue }
    if ($full.Length -ge 4 -and -not $machinePrefixes.Contains($full)) { $machinePrefixes.Add($full) }
}
$rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd([char[]]'\/')
# A checkout that lives under a documented stand-in root must not treat its own
# fixtures as the machine path.
if ($rootFull -notmatch '^[A-Za-z]:[\\/](work|library|comics|videos|inbox|batch|clips)([\\/]|$)') {
    if ($rootFull.Length -ge 4 -and -not $machinePrefixes.Contains($rootFull)) { $machinePrefixes.Add($rootFull) }
}

# A test file or the test driver may use the wider stand-in roots.
function Test-FileName {
    param([string]$Name)
    return ($Name -match '(^|/)(test|test_driver)/') -or ($Name -match '_test\.dart$')
}

# A drive path under a public root names a tool or a documented stand-in. The
# match keeps the whole path, so the root can be compared as a word.
function Find-LocalPath {
    param([string]$Text, [switch]$InTest)

    foreach ($match in [regex]::Matches($Text, $pathPattern)) {
        $value = $match.Value.Trim([char[]]' "''(,.;:')
        # A drive path written with escaped separators is the same stand-in;
        # compare the collapsed form.
        $normalized = $value
        if ($normalized -match '^[A-Za-z]:') {
            $normalized = $normalized -replace '([\\/])\1+', '$1'
        }
        # A JSON escape is not a path.
        if ($normalized -match '^[A-Za-z]:[\\/](n|r|t)(?=[\[\]{}",])') { continue }
        # An interpolated test path names no machine.
        if ($normalized -match '^[A-Za-z]:[\\/]\$\{') { continue }
        # A bare drive root is a fixture, not a file path.
        if ($InTest -and $normalized -match '^[A-Za-z]:[\\/]?$') { continue }
        # A test fixture for UNC handling is allowed; a real share is not.
        if ($InTest -and $normalized -match '^[\\/]{2,}server[\\/]+share([\\/]|$)') { continue }
        # A user profile is never a stand-in, even in a test. Only the generic
        # placeholders pass.
        if ($normalized -match '^[A-Za-z]:[\\/]Users([\\/]|$)') {
            if ($normalized -match '^[A-Za-z]:[\\/]Users[\\/](%USERNAME%|USERNAME|<[^>\s]*|u|user|me)([\\/]|$)') {
                continue
            }
            return $value
        }
        if ($InTest -and $normalized -match ('^[A-Za-z]:[\\/](' + $testRoot + ')([\\/]|$|[^\w])')) { continue }
        if ($normalized -match ('^[A-Za-z]:[\\/](' + $publicRoot + ')([\\/]|$|[^\w])')) { continue }
        if ($normalized -match ('^[A-Za-z]:/(' + $fixtureRoot + ')(/|$|[^\w])')) { continue }
        # The upstream maintainer's documented home is public; this is a path
        # prefix, not a deny-list term.
        if ($normalized -match '^/(Users|home)/(tibo|u|user)(/|$)') { continue }
        # "Program Files" has a space, so the path pattern stops before it.
        if ($Text.Substring($match.Index) -match '^[A-Za-z]:[\\/]Program Files([\\/]|$|[^\w])') { continue }
        if ($value) { return $value }
    }
    return $null
}

# Returns @{ Kind = 'path' | 'private'; Message = '...' } or $null.
function Find-Problem {
    param([string]$Where, [string]$Text, [switch]$InTest)

    foreach ($prefix in $machinePrefixes) {
        if ($Text.IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return @{ Kind = 'path'; Message = "local machine path at ${Where}: $prefix" }
        }
    }
    $path = Find-LocalPath -Text $Text -InTest:$InTest
    if ($path -ne $null) {
        return @{ Kind = 'path'; Message = "local path at ${Where}: $path" }
    }
    foreach ($term in $deny) {
        if ($Text.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return @{ Kind = 'private'; Message = "private term at ${Where}: $term" }
        }
    }
    return $null
}

# A file whose name is the leak never reaches Find-Problem: only its content
# does. Returns a message or $null.
function Find-NameProblem {
    param([string]$Name)

    if ($Name -match $dataPattern) { return "local data in a file name: $Name" }
    if ($Name -match $pathPattern) { return "local path in a file name: $Name" }
    foreach ($term in $deny) {
        if ($Name.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return "private term in a file name: $term"
        }
    }
    return $null
}

# Samples are assembled here so that this file contains none of the shapes it
# refuses. Each entry says what the path pattern must answer.
$BS = [string][char]92
$FS = [string][char]47
$C = [string][char]67
$D = [string][char]68
$selfTests = @(
    @{ what = 'a drive letter with a backslash'; text = ($C + ':' + $BS + 'work' + $BS + 'a.mp4'); path = $true },
    @{ what = 'a drive letter with a slash'; text = ($C + ':' + $FS + 'work' + $FS + 'a.mp4'); path = $true },
    @{ what = 'a UNC share'; text = ($BS + $BS + 'server' + $BS + 'share' + $BS + 'a.mp4'); path = $true },
    @{ what = 'a home directory'; text = ($FS + 'home' + $FS + 'someone' + $FS + 'a.mp4'); path = $true },
    @{ what = 'a Mac home directory'; text = ($FS + 'Users' + $FS + 'someone' + $FS + 'a.mp4'); path = $true },
    @{ what = 'a tilde path'; text = ('~' + $FS + 'Videos' + $FS + 'a.mp4'); path = $true },
    @{ what = 'a URL'; text = ('https' + ':' + $FS + $FS + 'example.com' + $FS + 'a'); path = $false },
    @{ what = 'a drive letter in prose'; text = ('the ' + $C + ': drive'); path = $false },
    @{ what = 'a relative path'; text = ('docs' + $FS + 'features' + $FS + 'a.md'); path = $false },
    @{ what = 'a drive path with spaces'; text = ($C + ':' + $BS + 'Users' + $BS + 'someone' + $BS + 'My Videos' + $BS + 'a.mp4'); path = $true },
    @{ what = 'an escaped regex sequence'; text = ($BS + $BS + 'd' + $BS + $BS + 'd' + ':' + $BS + 'd' + $BS + $BS + 'd'); path = $false },
    @{ what = 'an escaped regex with a dotted segment'; text = ($BS + $BS + '.github' + $BS + $BS + '.deckerst.*'); path = $false },
    @{ what = 'an integer division operator'; text = ('a ~' + $FS + ' b'); path = $false },
    @{ what = 'a Dart home import'; text = ('package:aves/widgets' + $FS + 'home' + $FS + 'home_page.dart'); path = $false }
)

foreach ($case in $selfTests) {
    $hitPath = [bool]($case.text -match $pathPattern)
    if ($hitPath -ne $case.path) {
        Write-Host ("FAIL: self-test, {0}: path={1}" -f $case.what, $hitPath)
        Write-Host "FAIL: the check itself is broken; fix the pattern before trusting a green run"
        exit 2
    }
}

# The public and fixture roots are a filter, not a pattern, so they get their
# own samples.
$filterTests = @(
    @{ what = 'a documented tool root'; text = ($C + ':' + $FS + 'Program Files' + $FS + 'Flutter' + $FS + 'bin'); local = $false },
    @{ what = 'a Windows root'; text = ($C + ':' + $BS + 'Windows' + $BS + 'System32'); local = $false },
    @{ what = 'a stand-in work root'; text = ($C + ':' + $BS + 'work' + $BS + 'a.mp4'); local = $false },
    @{ what = 'a stand-in library root'; text = ($D + ':' + $FS + 'library' + $FS + 'a.cbz'); local = $false },
    @{ what = 'a stand-in comics root'; text = ($C + ':' + $FS + 'comics' + $FS + 'a.cbz'); local = $false },
    @{ what = 'a stand-in videos root'; text = ($C + ':' + $BS + 'videos' + $BS + 'a.mp4'); local = $false },
    @{ what = 'a fixture root with a slash'; text = ($C + ':' + $FS + 'tmp' + $FS + 'a.png'); local = $false },
    @{ what = 'a fixture root on another drive'; text = ($D + ':' + $FS + 'out' + $FS + 'a.png'); local = $false },
    @{ what = 'a user placeholder'; text = ($C + ':' + $BS + 'Users' + $BS + '%USERNAME%' + $BS + 'AppData'); local = $false },
    @{ what = 'an angle-bracket placeholder'; text = ($C + ':' + $BS + 'Users' + $BS + '<username>' + $BS + 'AppData'); local = $false },
    @{ what = 'a documented maintainer home'; text = ($FS + 'home' + $FS + 'tibo' + $FS + 'Downloads' + $FS + 'a.aab'); local = $false },
    @{ what = 'a documented maintainer Mac home'; text = ($FS + 'Users' + $FS + 'tibo' + $FS + 'Desktop'); local = $false },
    @{ what = 'a real user account'; text = ($C + ':' + $BS + 'Users' + $BS + 'someone' + $BS + 'Videos' + $BS + 'a.mp4'); local = $true },
    @{ what = 'a real user account in a test'; text = ($C + ':' + $BS + 'Users' + $BS + 'someone' + $BS + 'Videos' + $BS + 'a.mp4'); local = $true; inTest = $true },
    @{ what = 'a test fixture root in a test'; text = ($D + ':' + $BS + 'phone' + $BS + 'Pictures' + $BS + 'a'); local = $false; inTest = $true },
    @{ what = 'a test fixture root outside a test'; text = ($D + ':' + $BS + 'phone' + $BS + 'Pictures' + $BS + 'a'); local = $true },
    @{ what = 'a real folder whose name is a fixture root'; text = ($D + ':' + $BS + 'tmp' + $BS + 'a.png'); local = $true },
    @{ what = 'a real library root'; text = ($D + ':' + $FS + 'books' + $FS + 'a.cbz'); local = $true },
    @{ what = 'a root that only starts with a public word'; text = ($D + ':' + $BS + 'workd' + $BS + 'a.mp4'); local = $true },
    @{ what = 'a real Unix home'; text = ($FS + 'home' + $FS + 'someone' + $FS + 'a.mp4'); local = $true },
    @{ what = 'a real Mac home'; text = ($FS + 'Users' + $FS + 'someone' + $FS + 'Desktop'); local = $true },
    @{ what = 'a real downloads folder'; text = ('~' + $FS + 'Downloads' + $FS + 'a.mp4'); local = $true }
)

foreach ($case in $filterTests) {
    $hit = Find-LocalPath -Text $case.text -InTest:([bool]$case['inTest'])
    if ([bool]$hit -ne $case.local) {
        Write-Host ("FAIL: self-test, {0}: local={1}" -f $case.what, (-not $case.local))
        Write-Host "FAIL: the check itself is broken; fix the public roots before trusting a green run"
        exit 2
    }
}

$problems = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if ($denyMissing) {
    $warnings.Add("deny list not found at .ai_tmp/local_text/deny-list.txt - private terms are not checked")
}

if ($Message) {
    # `git rev-parse --git-path` is the only reliable way to find this: in a
    # linked worktree the file lives under the main repository's .git, not
    # beside the sources.
    $gitPath = git -C $root rev-parse --git-path COMMIT_EDITMSG 2>$null
    if (-not $gitPath) {
        Write-Host "OK: no commit message to check"
        exit 0
    }
    $path = $gitPath
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $path = Join-Path $root $path
    }
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "OK: no commit message to check"
        exit 0
    }
    $number = 0
    foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        $number++
        $problem = Find-Problem -Where "the commit message:${number}" -Text $line
        if ($problem -ne $null) { $problems.Add($problem.Message) }
    }
    Write-Host ("message: {0} line(s) of the commit message" -f $number)
} elseif ($All) {
    $tracked = @(git -C $root -c core.quotepath=false ls-files)
    foreach ($file in $tracked) {
        $nameProblem = Find-NameProblem -Name $file
        if ($nameProblem -ne $null) { $problems.Add($nameProblem) }
        if ($file -notmatch $textFilePattern) { continue }
        $full = Join-Path $root $file
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $number = 0
        $inTest = Test-FileName -Name $file
        foreach ($line in (Get-Content -LiteralPath $full -Encoding UTF8)) {
            $number++
            $problem = Find-Problem -Where "${file}:${number}" -Text $line -InTest:$inTest
            if ($problem -eq $null) { continue }
            if ($problem.Kind -eq 'path') { $warnings.Add($problem.Message) }
            else { $problems.Add($problem.Message) }
        }
    }
    Write-Host ("audit: {0} tracked files, {1} warning(s)" -f $tracked.Count, $warnings.Count)
} else {
    $scope = ""
    if ($Pushed) {
        if ($Range) {
            # The hook passes shas reported by git, never a branch expression.
            if ($Range -notmatch '^[0-9a-fA-F]{4,40}\.\.[0-9a-fA-F]{4,40}$') {
                Write-Host "FAIL: invalid push range"
                exit 2
            }
            $scope = $Range
        } else {
            # A branch has no remote range yet (new branch, or no upstream).
            # Compare it with its upstream merge base or the closest default
            # branch, never only with the last commit: a path in an earlier
            # commit of a new branch must be caught too. With no base at all,
            # the whole branch is checked.
            $scope = "4b825dc642cb6eb9a060e54bf8d69288fbee4904..HEAD"
            $hasParent = $false
            try {
                $hasParent = [bool](git -C $root rev-parse --verify "HEAD~1" 2>$null)
            } catch {
                $hasParent = $false
            }
            if ($hasParent) {
                $current = $null
                try {
                    $current = git -C $root symbolic-ref --short HEAD 2>$null
                } catch {
                    $current = $null
                }
                $base = $null
                $upstream = $null
                try {
                    $upstream = git -C $root rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null
                } catch {
                    $upstream = $null
                }
                if ($upstream -and $upstream -notmatch '^\s*$') {
                    try {
                        $base = git -C $root merge-base $upstream HEAD 2>$null
                    } catch {
                        $base = $null
                    }
                }
                if (-not $base -or $base -match '^\s*$') {
                    foreach ($candidate in @("origin/HEAD", "origin/main", "origin/develop", "upstream/main", "upstream/develop", "main", "develop")) {
                        # Comparing the default branch with itself is empty;
                        # only another branch narrows the range.
                        if ($current -and $candidate -eq $current) { continue }
                        try {
                            $candidateBase = git -C $root merge-base $candidate HEAD 2>$null
                        } catch {
                            $candidateBase = $null
                        }
                        if ($candidateBase -and $candidateBase -notmatch '^\s*$') {
                            $base = $candidateBase
                            break
                        }
                    }
                }
                if ($base -and $base -notmatch '^\s*$') { $scope = "$base..HEAD" }
            }
        }
        Write-Host ("push: checking {0}" -f $scope)
        $staged = @(git -C $root -c core.quotepath=false diff --name-only --diff-filter=ACMR $scope)
        $diff = git -C $root -c core.quotepath=false diff -U0 --no-color $scope
    } else {
        $staged = @(git -C $root -c core.quotepath=false diff --cached --name-only --diff-filter=ACMR)
        if ($staged.Count -gt 0) {
            $diff = git -C $root -c core.quotepath=false diff --cached -U0 --no-color
            $scope = "cached"
        } else {
            $diff = git -C $root -c core.quotepath=false diff -U0 --no-color
            $scope = "worktree"
        }
    }

    foreach ($name in $staged) {
        $nameProblem = Find-NameProblem -Name $name
        if ($nameProblem -ne $null) { $problems.Add($nameProblem) }
    }

    $file = ""
    $number = 0
    foreach ($line in ($diff -split "`n")) {
        if ($line -match '^\+\+\+ b/(.+?)\s*$') {
            $file = $Matches[1]
            $number = 0
            continue
        }
        if ($line -match '^@@ .* \+(\d+)') {
            $number = [int]$Matches[1]
            continue
        }
        if ($line -notmatch '^\+' -or $line -match '^\+\+\+') { continue }
        $inTest = Test-FileName -Name $file
        $problem = Find-Problem -Where "${file}:${number}" -Text $line.Substring(1) -InTest:$inTest
        if ($problem -ne $null) { $problems.Add($problem.Message) }
        $number++
    }

    # git prints no `+` line for a binary file, so its bytes were never read:
    # the name was checked, the content was not. Say so instead of letting the
    # run look complete.
    if ($staged.Count -gt 0) {
        $numstat = if ($Pushed) {
            git -C $root -c core.quotepath=false diff --numstat $scope
        } elseif ($scope -eq "cached") {
            git -C $root -c core.quotepath=false diff --cached --numstat
        } else {
            git -C $root -c core.quotepath=false diff --numstat
        }
        foreach ($line in $numstat) {
            if ($line -match "^-\t-\t(.+)$") {
                $warnings.Add("binary file not scanned: $($Matches[1])")
            }
        }
    }
}

foreach ($warning in $warnings) { Write-Host "warning: $warning" }

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) { Write-Host "FAIL: $problem" }
    Write-Host ("FAIL: {0} local or private item(s) would be committed" -f $problems.Count)
    exit 1
}

Write-Host "OK: nothing local in the change"
exit 0
