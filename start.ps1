#Requires -Version 7.0

<#
.SYNOPSIS
Start the Strata server with a tier file.

.DESCRIPTION
Runs vendor\strata\serve\server.py with a tier file from presets\ on the given
port, in this window, until it is stopped with Ctrl+C. The server starts in
vendor\strata, where the tier file's relative paths resolve.

Checks first that Strata is set up, that every path the tier file names exists
and that no other server (such as Basalt) listens on the port. It never stops
another server: stop it yourself, it may have clients.

.PARAMETER tier
The tier file: its name in presets\ (with or without .json) or a path.
Defaults to the only tier file in presets\; when presets\ holds more than
one, offers them as a numbered list to choose from.

.PARAMETER port
The port to listen on.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\start.ps1 -tier qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM

.EXAMPLE
.\start.ps1 -tier qwen3.8-flash-next.unsloth-ud-iq4_xs.16GB_8GB_VRAM_128GB_RAM -port 8084
#>

Param (
    [String]
    $tier,

    [Int]
    $port = 8083,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$ErrorActionPreference = "Stop"

function Select-Tier {
    $tiers = @(Get-ChildItem -Path $presetsPath -Filter "*.json" -File | Sort-Object Name)

    if ($tiers.Count -eq 0) {
        throw "No tier file in presets\: README.md -> Tiers explains how to make one."
    }

    Write-Host ""
    Write-Host "Choose a tier file:" -ForegroundColor "Yellow"
    for ($i = 0; $i -lt $tiers.Count; $i++) {
        Write-Host "  [$($i + 1)] $($tiers[$i].BaseName)"
    }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $answer = Read-Host "Which tier? (number or name, empty to cancel)"

        if (-not $answer -or $answer -eq "q") {
            Write-Host "Aborted: no tier chosen." -ForegroundColor "Red"
            exit 1
        }

        $choice = if ($answer -match '^\d+$') {
            $index = [int]$answer
            if ($index -ge 1 -and $index -le $tiers.Count) { $tiers[$index - 1] }
        } else {
            $name = $answer -replace '\.json$', ''
            @($tiers | Where-Object { $_.BaseName -ieq $name })[0]
        }

        if ($choice) { return $choice }
        Write-Host "Not a tier on the list, try again." -ForegroundColor "Red"
    }

    Write-Host "Aborted: no tier chosen." -ForegroundColor "Red"
    exit 1
}

$presetsPath = Join-Path $PSScriptRoot "presets"
$strataPath = Join-Path $PSScriptRoot "vendor\strata"
$python = Join-Path $strataPath ".venv\Scripts\python.exe"

if (-not (Test-Path -Path $python)) {
    throw "vendor\strata\.venv is missing. Follow README.md -> New machine first."
}

if (!$tier) {
    $tiers = @(Get-ChildItem -Path $presetsPath -Filter "*.json" -File)

    if ($tiers.Count -ne 1) {
        $configPath = (Select-Tier).FullName
    } else {
        $configPath = $tiers[0].FullName
    }
} elseif (Test-Path -Path $tier -PathType "Leaf") {
    $configPath = (Resolve-Path -Path $tier).Path
} else {
    $configPath = Join-Path $presetsPath "$($tier -replace '\.json$', '').json"

    if (-not (Test-Path -Path $configPath)) {
        Write-Host "No tier file '${tier}' in presets\." -ForegroundColor "Red"
        $configPath = (Select-Tier).FullName
    }
}

$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
$paths = @($config.exe) + @($config.args | Where-Object { $_ -match "\\" })

if ($config.tokenizer) {
    $paths += $config.tokenizer
}

if ($config.vision) {
    $paths += @($config.vision.exe, $config.vision.mmproj, $config.vision.model) | Where-Object { $_ }
}

$missing = @($paths | Where-Object {
    $path = if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $strataPath $_ }
    -not (Test-Path -Path $path)
})

if ($missing) {
    $list = ($missing | ForEach-Object { "  $_" }) -join "`n"
    throw "The tier file names paths that do not exist:`n${list}`nThe engine comes from .\update_strata.ps1, the model files from README.md -> New machine."
}

$listener = Get-NetTCPConnection -LocalPort $port -State "Listen" -ErrorAction "SilentlyContinue" | Select-Object -First 1

if ($listener) {
    $owner = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    throw "Port ${port} is taken by PID $($owner.ProcessId) ($($owner.Name)): $($owner.CommandLine)`nStop that server and re-run. It may have clients, so this script does not stop it."
}

Write-Host "Starting Strata..." -ForegroundColor "Yellow"
Write-Host "Version: $(git -C $strataPath describe --tags --always)" -ForegroundColor "DarkYellow"
Write-Host "Tier: $(Split-Path -Path $configPath -LeafBase)" -ForegroundColor "DarkYellow"
Write-Host "Port: ${port}" -ForegroundColor "DarkYellow"

Push-Location -Path $strataPath

try {
    & $python serve\server.py --engine strata --config $configPath --port $port
} finally {
    Pop-Location
}

exit $LASTEXITCODE
