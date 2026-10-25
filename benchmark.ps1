#Requires -Version 7.0

<#
.SYNOPSIS
Benchmark the running Strata server with Strata's own tools/strata_bench.py.

.DESCRIPTION
Runs the default suite of tools/strata_bench.py against the server that is
already running, writes the results to .tmp/bench/<Strata tag>_engine-<version>/
and prints the four numbers of README.md -> Tiers.

The server is neither started nor stopped: start it as README.md -> Usage says.

.PARAMETER url
The address of the running server.

.PARAMETER out
The folder to write the results to, instead of
.tmp/bench/<Strata tag>_engine-<version>/.

.PARAMETER compare
An earlier results folder to print beside this run, for example
.tmp\bench\v0.2.2_engine-0.1.47. A folder that holds several runs uses the
newest.

.PARAMETER arguments
Passed on to tools/strata_bench.py unchanged, for example --long or
--clients 2. See its --help.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\benchmark.ps1

.EXAMPLE
.\benchmark.ps1 -compare .tmp\bench\v0.2.2_engine-0.1.47

.EXAMPLE
.\benchmark.ps1 --runs 5 --long
#>

# Without this, "--runs 5" binds "--runs" to -url by position.
[CmdletBinding(PositionalBinding = $false)]
Param (
    [String]
    $url = "http://127.0.0.1:8083",

    [String]
    $out,

    [String]
    $compare,

    [Parameter(ValueFromRemainingArguments)]
    [String[]]
    $arguments,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$ErrorActionPreference = "Stop"

$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

$strataPath = Join-Path $PSScriptRoot "vendor\strata"
$python = Join-Path $strataPath ".venv\Scripts\python.exe"
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

function Find-Results {
    Param ([String] $path)

    if ((Test-Path -Path $path -PathType "Leaf") -and (Split-Path -Path $path -Leaf) -eq "results.json") {
        return (Resolve-Path -Path $path).Path
    }

    Get-ChildItem -Path $path -Filter "results.json" -Recurse -File -ErrorAction "SilentlyContinue" |
        Sort-Object -Property "LastWriteTime" -Descending |
        Select-Object -First 1 -ExpandProperty "FullName"
}

function Format-Number {
    Param ($value, [String] $format, [String] $unit)

    if ($null -eq $value) {
        return "skipped"
    }

    "$(([double]$value).ToString($format, $invariant)) ${unit}"
}

if (-not (Test-Path -Path $python)) {
    throw "vendor/strata/.venv is missing. Follow README.md -> New machine first."
}

# Resolved before the working directory moves into vendor/strata.
$compareResults = $null

if ($compare) {
    $compareResults = Find-Results -path $compare

    if (!$compareResults) {
        throw "No results.json found in '${compare}'."
    }
}

try {
    $models = Invoke-RestMethod -Uri "${url}/v1/models" -TimeoutSec 10
} catch {
    throw "No Strata server answers at ${url}. Start it as README.md -> Usage says, wait for 'ready', and re-run."
}

$strataVersion = git -C $strataPath describe --tags --always
$engineVersion = (Get-Content -Raw -Path (Join-Path $strataPath "engine\BUILD.json") | ConvertFrom-Json).version
$outPath = if ($out) {
    [System.IO.Path]::GetFullPath($out, (Get-Location).Path)
} else {
    Join-Path $PSScriptRoot ".tmp\bench\${strataVersion}_engine-${engineVersion}"
}

New-Item -Path $outPath -ItemType "directory" -Force | Out-Null

Write-Host "Benchmarking Strata..." -ForegroundColor "Yellow"
Write-Host "Server: ${url} ($($models.data.id -join ', '))" -ForegroundColor "DarkYellow"
Write-Host "Version: ${strataVersion}, engine ${engineVersion}" -ForegroundColor "DarkYellow"
Write-Host "Results: ${outPath}" -ForegroundColor "DarkYellow"

if ($compareResults) {
    Write-Host "Compare: ${compareResults}" -ForegroundColor "DarkYellow"
}

$startedAt = Get-Date

Push-Location -Path $strataPath

try {
    $benchArguments = @("-u", "tools\strata_bench.py", "--url", $url, "--out", $outPath)

    if ($compareResults) {
        $benchArguments += @("--compare", $compareResults)
    }

    & $python @benchArguments @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "tools/strata_bench.py failed with exit code ${LASTEXITCODE}."
    }

} finally {
    Pop-Location
}

$resultsPath = Get-ChildItem -Path $outPath -Filter "results.json" -Recurse -File |
    Where-Object { $_.LastWriteTime -ge $startedAt } |
    Sort-Object -Property "LastWriteTime" -Descending |
    Select-Object -First 1 -ExpandProperty "FullName"

if (!$resultsPath) {
    throw "tools/strata_bench.py wrote no results.json under ${outPath}."
}

$results = (Get-Content -Raw -Path $resultsPath | ConvertFrom-Json).results

$row = [ordered]@{
    "Strata"          = $strataVersion
    "Chat decode"     = Format-Number -value $results.chat.decode_tps.median -format "0.0" -unit "tok/s"
    "16K prompt"      = Format-Number -value $results.prompts."16K".prompt_tps.median -format "0" -unit "tok/s"
    "Agent decode"    = Format-Number -value $results.agent.turn_decode_tps.median -format "0.0" -unit "tok/s"
    "Agent cache hit" = Format-Number -value $results.agent.hit_pct.median -format "0.0" -unit "%"
}

$stopwatch.Stop()
$durationInSeconds = [Math]::Floor([Decimal]($stopwatch.Elapsed.TotalSeconds))

Write-Host "README.md -> Tiers (medians):" -ForegroundColor "Yellow"
[pscustomobject]$row | Format-Table -AutoSize | Out-Host
Write-Host "Finished the benchmark in ${durationInSeconds} seconds: ${resultsPath}" -ForegroundColor "Yellow"
