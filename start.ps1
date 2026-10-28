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
one, offers them as a list to choose from with the arrow keys (a typed
number or name when its input is piped).

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

function Select-TierTyped {
    param ([array] $Tiers)

    # A typed number or name: the menu's form when its input is piped or its cursor cannot be drawn.
    for ($i = 0; $i -lt $Tiers.Count; $i++) {
        Write-Host "  [$($i + 1)] $($Tiers[$i].BaseName)"
    }

    Write-Host ""

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $answer = Read-Host "Which tier? (number or name, empty to cancel)"

        if (-not $answer -or $answer -eq "q") {
            Write-Host "Aborted: no tier chosen." -ForegroundColor "Red"
            exit 1
        }

        $choice = if ($answer -match '^\d+$') {
            $index = [int]$answer
            if ($index -ge 1 -and $index -le $Tiers.Count) { $Tiers[$index - 1] }
        } else {
            $name = $answer -replace '\.json$', ''
            @($Tiers | Where-Object { $_.BaseName -ieq $name })[0]
        }

        if ($choice) { return $choice }
        Write-Host "Not a tier on the list, try again." -ForegroundColor "Red"
    }

    Write-Host "Aborted: no tier chosen." -ForegroundColor "Red"
    exit 1
}

function Select-Tier {
    $tiers = @(Get-ChildItem -Path $presetsPath -Filter "*.json" -File | Sort-Object Name)

    if ($tiers.Count -eq 0) {
        throw "No tier file in presets\: README.md -> Tiers explains how to make one."
    }

    Write-Host ""
    Write-Host "Choose a tier file:" -ForegroundColor "Yellow"
    Write-Host ""

    $width = ($tiers | ForEach-Object { $_.BaseName.Length } | Measure-Object -Maximum).Maximum + 2

    # The menu paints over its rows, so it needs a real keyboard and no wrapped lines.
    # Otherwise print the list plain and type the answer.
    $menuWays = -not [Console]::IsInputRedirected -and
                -not [Console]::IsOutputRedirected -and
                $width -lt [Console]::WindowWidth

    if (-not $menuWays) {
        return Select-TierTyped $tiers
    }

    # Cursor menu: arrows move, Enter picks, a digit jumps, q, Esc or Ctrl+C cancels.
    # Anchor on the cursor after the rows are printed: printing them may scroll the window.
    for ($i = 0; $i -lt $tiers.Count; $i++) {
        Write-Host ("  $($tiers[$i].BaseName)".PadRight($width))
    }

    $row0 = [Console]::CursorTop - $tiers.Count

    $paint = {
        param ($i, $on)
        [Console]::SetCursorPosition(0, $row0 + $i)
        $mark = if ($on) { ">" } else { " " }
        $line = ("$mark $($tiers[$i].BaseName)").PadRight($width)
        if ($on) { Write-Host $line -ForegroundColor "Yellow" } else { Write-Host $line }
    }

    $pick = 0
    $shown = -1
    $chosen = $null
    $menuError = $null
    $ctrlCAsInput = [Console]::TreatControlCAsInput

    try {
        # Ctrl+C as a key: a stop request would wait inside ReadKey until the next key press.
        [Console]::TreatControlCAsInput = $true
        [Console]::CursorVisible = $false

        while (-not $chosen) {
            if ($shown -ge 0) { & $paint $shown $false }
            & $paint $pick $true
            $shown = $pick

            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                UpArrow { if ($pick -gt 0) { $pick-- } }
                DownArrow { if ($pick -lt $tiers.Count - 1) { $pick++ } }
                Enter { $chosen = $tiers[$pick] }
                Escape { $chosen = "quit" }
                Default {
                    if ($key.Key -eq "C" -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                        $chosen = "quit"
                    } elseif ($key.KeyChar -in "q", "Q") {
                        $chosen = "quit"
                    } elseif ($key.KeyChar -match '^[1-9]$') {
                        $index = [int][string]$key.KeyChar - 1
                        if ($index -lt $tiers.Count) {
                            $pick = $index
                            $chosen = $tiers[$index]
                        }
                    }
                }
            }
        }
    } catch {
        $menuError = $_
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
        try { [Console]::TreatControlCAsInput = $ctrlCAsInput } catch { }
    }

    if ($menuError) {
        # A terminal that refuses the cursor API: fall back to the typed prompt, with Ctrl+C and the cursor restored.
        Write-Host ""
        Write-Host "Menu unavailable (${menuError}): typing instead." -ForegroundColor "Yellow"
        return Select-TierTyped $tiers
    }

    # The choice stands: keep the picked row, in green, and clear the rest.
    try {
        for ($i = 0; $i -lt $tiers.Count; $i++) {
            [Console]::SetCursorPosition(0, $row0 + $i)
            if ($chosen -ne "quit" -and $i -eq $pick) {
                Write-Host ("> $($tiers[$i].BaseName)".PadRight($width)) -ForegroundColor "Green"
            } else {
                Write-Host (" " * $width)
            }
        }
        [Console]::SetCursorPosition(0, $row0 + $tiers.Count)
    } catch { }
    Write-Host ""

    if ($chosen -eq "quit") {
        Write-Host "Aborted: no tier chosen." -ForegroundColor "Red"
        exit 1
    }

    return $chosen
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
