#Requires -Version 7.0

<#
.SYNOPSIS
Update the Strata submodule and its engine to a tag, a commit or HEAD.

.DESCRIPTION
Checks out the requested Strata version in vendor/strata, installs the
ready-made engine of the matching GitHub release and runs Strata's own
"setup.py --update" for the Python packages and setup's model configs.

Everything that can fail (the version, a running server, the download and
its checksum) is checked before anything is changed. Nothing is committed,
and the server is neither started nor stopped.

.PARAMETER version
A Strata tag (v0.2.4.2), a commit, or HEAD (or main) for the newest commit
on upstream's main.
Defaults to the newest tag without a suffix such as "-beta".

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\update_strata.ps1

.EXAMPLE
.\update_strata.ps1 -version v0.2.4.2

.EXAMPLE
.\update_strata.ps1 -version HEAD
#>

Param (
    [String]
    $version,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$ErrorActionPreference = "Stop"

# Invoke-WebRequest redraws its progress bar per chunk, which slows a
# 500 MB download down several times over.
$ProgressPreference = "SilentlyContinue"

$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

$strataPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "vendor\strata"))
$enginePath = Join-Path $strataPath "engine"
$incomingPath = Join-Path $enginePath ".incoming"
$previousPath = Join-Path $enginePath ".previous"
$python = Join-Path $strataPath ".venv\Scripts\python.exe"

# Git for Windows puts its own tar on the PATH, and GNU tar reads "D:\..." as
# a remote host. The one Windows ships handles drive letters and .tar.gz.
$tar = Join-Path $env:SystemRoot "System32\tar.exe"

function Invoke-StrataGit {
    $output = git -C $strataPath @args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') failed with exit code ${LASTEXITCODE}."
    }
    $output
}

function Read-EngineVersion {
    Param ([String] $path)
    (Get-Content -Raw -Path (Join-Path $path "BUILD.json") | ConvertFrom-Json).version
}

function Test-Download {
    Param ([String] $path, $asset)
    (Test-Path -Path $path) -and
    (Get-Item -Path $path).Length -eq $asset.size -and
    "sha256:$((Get-FileHash -Path $path -Algorithm SHA256).Hash)" -eq $asset.digest
}

if (-not (Test-Path -Path (Join-Path $strataPath ".git"))) {
    throw "vendor/strata is not checked out. Follow README.md -> New machine first."
}

if (-not (Test-Path -Path $python)) {
    throw "vendor/strata/.venv is missing. Follow README.md -> New machine first."
}

$componentPath = Join-Path $enginePath "engine-component.json"

if (-not (Test-Path -Path $componentPath)) {
    throw "No engine is installed in vendor/strata/engine. Follow README.md -> New machine first."
}

# The server is several processes. The .venv python.exe is only a launcher:
# the interpreter it starts runs from the system Python, with a relative
# "serve\server.py" on its command line, so the executable path alone misses
# it. Shells whose command line names the folder hold no files open.
$shells = @("pwsh.exe", "powershell.exe", "cmd.exe", "conhost.exe", "OpenConsole.exe", "WindowsTerminal.exe")

$blockers = Get-CimInstance -ClassName Win32_Process | Where-Object {
    $_.ProcessId -ne $PID -and (
        ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($strataPath, [StringComparison]::OrdinalIgnoreCase)) -or
        ($_.Name -notin $shells -and $_.CommandLine -and (
            $_.CommandLine.IndexOf($strataPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.CommandLine -match 'serve[\\/]server\.py'))
    )
}

if ($blockers) {
    $list = ($blockers | ForEach-Object { "  PID $($_.ProcessId)  $($_.Name)  $($_.CommandLine)" }) -join "`n"
    throw "Strata is running:`n${list}`nStop the server and re-run. Other clients depend on it, so this script does not stop it."
}

if (Invoke-StrataGit status --porcelain --untracked-files=no) {
    throw "vendor/strata has local changes. Upstream's code is never edited here: check them with 'git -C vendor\strata status'."
}

Write-Host "[Git] Fetching Strata's tags and main..." -ForegroundColor "Yellow"

# Without --force the fetch stops at upstream's rewritten older tags.
Invoke-StrataGit fetch --tags --force origin

if (!$version) {
    $version = Invoke-StrataGit tag --list "v*" --sort=-v:refname |
        Where-Object { $_ -match '^v\d+(\.\d+)*$' } |
        Select-Object -First 1
}

# The submodule's local main is never pulled, so both names mean upstream's.
if ($version -in @("HEAD", "main")) {
    $version = "HEAD"
    $ref = "origin/main"
} else {
    $ref = $version
}

$commit = git -C $strataPath rev-parse --verify --quiet "${ref}^{commit}"

if ($LASTEXITCODE -ne 0 -or !$commit) {
    throw "Strata has no tag or commit '${version}'."
}

$oldCommit = Invoke-StrataGit rev-parse HEAD
$oldVersion = Invoke-StrataGit describe --tags --always
$newVersion = Invoke-StrataGit describe --tags --always $commit
$baseTag = Invoke-StrataGit describe --tags --abbrev=0 $commit

# A point release (v0.2.4.2) has no release page; its engine is on the base
# release's (v0.2.4). Drop the last number until a release answers.
$repository = [regex]::Match(
    (Invoke-StrataGit remote get-url origin),
    'github\.com[:/](.+?)(\.git)?$'
).Groups[1].Value

$releaseTag = $baseTag

while ($true) {
    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/${repository}/releases/tags/${releaseTag}" `
        -SkipHttpErrorCheck `
        -StatusCodeVariable "status"

    if ($status -eq 200) {
        break
    }

    if ($status -ne 404) {
        throw "GitHub answered ${status} for the release ${releaseTag}: $($release.message)"
    }

    if ($releaseTag -notmatch '^(v\d+(\.\d+)*)\.\d+$') {
        throw "Neither ${baseTag} nor a release it is based on has a release page."
    }

    $releaseTag = $Matches[1]
}

# The engine that is installed names its own variant (cuda13, cuda12, hip-...).
$component = Get-Content -Raw -Path $componentPath | ConvertFrom-Json

$assetPattern = '^strata-engine-(?<version>\d+(\.\d+)+)-{0}-{1}-{2}\.tar\.gz$' -f `
    [regex]::Escape($component.platform),
    [regex]::Escape($component.backend),
    [regex]::Escape($component.variant)

$asset = $release.assets |
    Where-Object { $_.name -match $assetPattern } |
    Sort-Object -Descending -Property { [version]([regex]::Match($_.name, $assetPattern).Groups["version"].Value) } |
    Select-Object -First 1

if (!$asset) {
    throw "The release ${releaseTag} has no engine matching ${assetPattern}."
}

if ($asset.digest -notmatch '^sha256:[0-9a-f]{64}$') {
    throw "GitHub lists no SHA-256 for $($asset.name), so it cannot be verified."
}

$engineVersion = [regex]::Match($asset.name, $assetPattern).Groups["version"].Value
$installedEngine = Read-EngineVersion -path $enginePath
$updateEngine = $installedEngine -ne $engineVersion

Write-Host "Updating Strata..." -ForegroundColor "Yellow"
Write-Host "Version: ${oldVersion} -> ${newVersion}" -ForegroundColor "DarkYellow"
Write-Host "Engine: ${installedEngine} -> ${engineVersion} ($($component.variant), release ${releaseTag})" -ForegroundColor "DarkYellow"
Write-Host "Release notes: $($release.html_url)" -ForegroundColor "DarkYellow"

if ($version -eq "HEAD") {
    Write-Host "HEAD runs with the engine of release ${releaseTag}, which can be older than main expects." -ForegroundColor "DarkYellow"
}

if ($updateEngine) {

    $downloadPath = Join-Path ([System.IO.Path]::GetTempPath()) $asset.name

    if (Test-Download -path $downloadPath -asset $asset) {
        Write-Host "[Engine] Reusing the verified download $($asset.name)." -ForegroundColor "Yellow"
    } else {
        Write-Host "[Engine] Downloading $($asset.name) ($([Math]::Round($asset.size / 1MB)) MB)..." -ForegroundColor "Yellow"

        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath

        if (-not (Test-Download -path $downloadPath -asset $asset)) {
            Remove-Item -Path $downloadPath -Force
            throw "$($asset.name) does not match GitHub's size and SHA-256. The download was deleted."
        }
    }

    Write-Host "[Engine] SHA-256 matches GitHub's $($asset.digest)." -ForegroundColor "Yellow"

    # Unpacked next to engine\ so the swap below is a rename on one drive.
    Remove-Item -Path $incomingPath -Recurse -Force -ErrorAction "SilentlyContinue"
    New-Item -Path $incomingPath -ItemType "directory" | Out-Null

    & $tar -xzf $downloadPath -C $incomingPath

    if ($LASTEXITCODE -ne 0) {
        Remove-Item -Path $incomingPath -Recurse -Force
        throw "Unpacking $($asset.name) failed with exit code ${LASTEXITCODE}."
    }

    if (-not (Test-Path -Path (Join-Path $incomingPath "strata.exe")) -or
        (Read-EngineVersion -path $incomingPath) -ne $engineVersion) {
        Remove-Item -Path $incomingPath -Recurse -Force
        throw "$($asset.name) does not hold engine ${engineVersion} with strata.exe at its top level."
    }
}

# From here on files change. A failure before setup.py puts the old commit and
# the old engine back, so Strata never runs code against an engine it was not
# released with.
$movedFiles = @()
$placedFiles = @()

try {
    Write-Host "[Git] Checking out ${newVersion}..." -ForegroundColor "Yellow"

    Invoke-StrataGit checkout --quiet --detach $commit

    if ($updateEngine) {

        Write-Host "[Engine] Installing ${engineVersion}, keeping ${installedEngine} in engine\.previous..." -ForegroundColor "Yellow"

        # Only the files the new engine replaces move, as in setup.py's
        # install_unpacked, so "setup.py --rollback-engine" can swap them back.
        $newFiles = Get-ChildItem -Path $incomingPath

        Remove-Item -Path $previousPath -Recurse -Force -ErrorAction "SilentlyContinue"
        New-Item -Path $previousPath -ItemType "directory" | Out-Null

        foreach ($file in $newFiles) {
            $target = Join-Path $enginePath $file.Name
            if (Test-Path -Path $target) {
                Move-Item -Path $target -Destination $previousPath
                $movedFiles += $file.Name
            }
        }

        foreach ($file in $newFiles) {
            Move-Item -Path $file.FullName -Destination $enginePath
            $placedFiles += $file.Name
        }

        $reported = & (Join-Path $enginePath "strata.exe") --version

        if ($LASTEXITCODE -ne 0 -or "$reported" -notmatch "\b$([regex]::Escape($engineVersion))\b") {
            throw "engine\strata.exe --version reported '${reported}', not ${engineVersion}."
        }

        Write-Host "[Engine] ${reported}" -ForegroundColor "Yellow"
    }

} catch {
    Write-Host "Putting back ${oldVersion} and engine ${installedEngine}..." -ForegroundColor "Red"

    foreach ($name in $placedFiles) {
        Remove-Item -Path (Join-Path $enginePath $name) -Recurse -Force
    }

    foreach ($name in $movedFiles) {
        Move-Item -Path (Join-Path $previousPath $name) -Destination $enginePath
    }

    git -C $strataPath checkout --quiet --detach $oldCommit

    throw

} finally {
    Remove-Item -Path $incomingPath -Recurse -Force -ErrorAction "SilentlyContinue"
}

if (!$updateEngine) {
    Write-Host "[Engine] ${installedEngine} is already installed." -ForegroundColor "Yellow"
}

Write-Host "[Setup] Updating the Python packages and setup's model configs..." -ForegroundColor "Yellow"

# START-HERE.bat would pause on a failure and hang this script; it only sets
# PYTHONUTF8 and calls setup.py, which never runs git (unlike UPDATE.bat).
$previousUtf8 = $env:PYTHONUTF8
Push-Location -Path $strataPath

try {
    $env:PYTHONUTF8 = "1"

    & $python setup.py --update --yes --no-start

    if ($LASTEXITCODE -ne 0) {
        throw "setup.py --update failed with exit code ${LASTEXITCODE}. Strata and its engine are updated; fix the cause and run '.\.venv\Scripts\python.exe setup.py --update --yes --no-start' in vendor\strata."
    }

} finally {
    Pop-Location
    $env:PYTHONUTF8 = $previousUtf8
}

git -C $PSScriptRoot status --short

$stopwatch.Stop()
$durationInSeconds = [Math]::Floor([Decimal]($stopwatch.Elapsed.TotalSeconds))

Write-Host "Updated Strata ${oldVersion} -> ${newVersion}, engine ${installedEngine} -> ${engineVersion} in ${durationInSeconds} seconds." -ForegroundColor "Yellow"
Write-Host "Next: README.md -> Update Strata, from step 3 (compare setup's config with the tier files, start, benchmark, commit)." -ForegroundColor "Yellow"
