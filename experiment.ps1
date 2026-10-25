#Requires -Version 7.0

<#
.SYNOPSIS
Measure a tier with a longer context and with parallel requests.

.DESCRIPTION
Takes the server port over: unloads and stops the running server, then starts
one throwaway config per arm (the tier file plus the arm's changes), measures it
with benchmark.ps1 and tools/needle_bench.py, and stops it again. At the end,
also after an error or Ctrl+C, it starts the tier again in a new window, the way
README.md -> Usage does, if a server was running at the start.

The configs, the server and engine logs, the results and summary.md go to
.tmp/bench/experiment-<date>/. The tier files are not changed. The arms bind
127.0.0.1, so other devices do not reach the server during the run.

Arms:
  baseline   the tier as it is
  512k       --max-context 524288, YaRN factor 2; needles at 128K and 480K
  parallel2  "parallel": 2 and --batch-mtp; 2 requests at once
  combo512k  512k and parallel2
  combo1m    --max-context 1048576, YaRN factor 4, and parallel2; a needle at 960K

.PARAMETER tier
The tier file in presets/ without .json. It must be the one the running server
uses, because the script starts it again at the end.

.PARAMETER arms
The arms to run, in the order above.

.PARAMETER port
The server port.

.PARAMETER check
Builds and checks the configs, then stops. The running server is not touched.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\experiment.ps1 -tier qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM -check

.EXAMPLE
.\experiment.ps1 -tier qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM

.EXAMPLE
.\experiment.ps1 -tier qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM -arms baseline,512k
#>

[CmdletBinding(PositionalBinding = $false)]
Param (
    [String]
    $tier,

    [ValidateSet("baseline", "512k", "parallel2", "combo512k", "combo1m")]
    [String[]]
    $arms = @("baseline", "512k", "parallel2", "combo512k", "combo1m"),

    [Int]
    $port = 8083,

    [switch]
    $check,

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
$benchmarkScript = Join-Path $PSScriptRoot "benchmark.ps1"
$needleScript = Join-Path $strataPath "tools\needle_bench.py"
$url = "http://127.0.0.1:${port}"
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

$armOrder = @("baseline", "512k", "parallel2", "combo512k", "combo1m")

$armSettings = @{
    "baseline"  = @{ context = 0;       scale = 0; parallel = 0; needles = $null;       depths = $null }
    "512k"      = @{ context = 524288;  scale = 2; parallel = 0; needles = "128k,480k"; depths = "10,50,90" }
    "parallel2" = @{ context = 0;       scale = 0; parallel = 2; needles = $null;       depths = $null }
    "combo512k" = @{ context = 524288;  scale = 2; parallel = 2; needles = $null;       depths = $null }
    "combo1m"   = @{ context = 1048576; scale = 4; parallel = 2; needles = "960k";      depths = "50" }
}

function Set-Argument {
    Param ([System.Collections.Generic.List[String]] $list, [String] $name, [String] $value)

    $index = $list.IndexOf($name)

    if ($index -lt 0) {
        $list.Add($name)

        if ($value) {
            $list.Add($value)
        }

        return
    }

    if ($value) {
        $list[$index + 1] = $value
    }
}

function Resolve-StrataPath {
    Param ([String] $path)

    if ([System.IO.Path]::IsPathRooted($path)) {
        return $path
    }

    Join-Path $strataPath $path
}

function New-ArmConfig {
    Param ([String] $arm, [String] $armPath)

    $settings = $armSettings[$arm]
    $config = Get-Content -Raw -Path $tierPath | ConvertFrom-Json
    $argumentList = [System.Collections.Generic.List[String]]::new([String[]] $config.args)

    if ($settings.context) {
        Set-Argument -list $argumentList -name "--max-context" -value "$($settings.context)"
        Set-Argument -list $argumentList -name "--rope-scaling" -value "yarn"
        Set-Argument -list $argumentList -name "--rope-scale" -value "$($settings.scale)"
    }

    if ($settings.parallel) {
        Set-Argument -list $argumentList -name "--batch-mtp" -value ""
        $config | Add-Member -NotePropertyName "parallel" -NotePropertyValue $settings.parallel -Force
    }

    $config.args = $argumentList.ToArray()
    $config | Add-Member -NotePropertyName "host" -NotePropertyValue "127.0.0.1" -Force
    $config | Add-Member -NotePropertyName "log" -NotePropertyValue (Join-Path $armPath "engine.log") -Force

    $configPath = Join-Path $armPath "config.json"
    $config | ConvertTo-Json -Depth 100 | Set-Content -Path $configPath -Encoding "utf8"
    $configPath
}

function Test-ArmConfig {
    Param ([String] $configPath)

    $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    $paths = @($config.exe) + @($config.args | Where-Object { $_ -match "\\" })

    if ($config.tokenizer) {
        $paths += $config.tokenizer
    }

    if ($config.vision) {
        $paths += @($config.vision.exe, $config.vision.mmproj, $config.vision.model) | Where-Object { $_ }
    }

    $missing = $paths | Where-Object { -not (Test-Path -Path (Resolve-StrataPath $_)) }

    if ($missing) {
        throw "${configPath} names paths that do not exist: $($missing -join ', ')"
    }
}

function Get-PortOwner {
    Get-NetTCPConnection -LocalPort $port -State "Listen" -ErrorAction "SilentlyContinue" |
        Select-Object -First 1 -ExpandProperty "OwningProcess"
}

function Stop-Server {
    $owner = Get-PortOwner

    if (!$owner) {
        return
    }

    Write-Host "Unloading the server on port ${port} (it finishes a running request first)..." -ForegroundColor "DarkYellow"

    try {
        Invoke-RestMethod -Method "Post" -Uri "${url}/unload?wait=1" -ContentType "application/json" -Body "{}" -TimeoutSec 330 |
            Out-Null
    } catch {
        Write-Host "Unload failed ($($_.Exception.Message)), stopping it anyway." -ForegroundColor "DarkYellow"
    }

    # /T: the server's engine and vision processes hold the VRAM.
    taskkill /PID $owner /T /F 2>&1 | Out-Null

    $deadline = (Get-Date).AddSeconds(30)

    while ((Get-PortOwner) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }

    if (Get-PortOwner) {
        throw "Port ${port} is still taken after stopping process ${owner}."
    }
}

function Start-ArmServer {
    Param ([String] $configPath, [String] $armPath)

    $serverArguments = @("-u", "serve\server.py", "--engine", "strata", "--config", "`"${configPath}`"", "--port", "${port}")

    Start-Process -FilePath $python -ArgumentList $serverArguments -WorkingDirectory $strataPath -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $armPath "server.log") -RedirectStandardError (Join-Path $armPath "server.err.log")
}

function Wait-Server {
    Param ($process, [Int] $timeoutInSeconds = 600)

    $deadline = (Get-Date).AddSeconds($timeoutInSeconds)

    while ((Get-Date) -lt $deadline) {
        if ($process -and $process.HasExited) {
            return $null
        }

        try {
            $health = Invoke-RestMethod -Uri "${url}/health" -TimeoutSec 5

            if ($health.loaded) {
                return $health
            }
        } catch {
        }

        Start-Sleep -Seconds 5
    }

    $null
}

function Invoke-Smoke {
    $body = @{
        model                = "strata"
        max_tokens           = 8
        temperature          = 0
        chat_template_kwargs = @{ enable_thinking = $false }
        messages             = @(@{ role = "user"; content = "Reply with OK." })
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Method "Post" -Uri "${url}/v1/chat/completions" -ContentType "application/json" -Body $body -TimeoutSec 600 |
        Out-Null
}

function Format-Value {
    Param ($value, [String] $format)

    if ($null -eq $value) {
        return "-"
    }

    ([double]$value).ToString($format, $invariant)
}

function Format-MarkdownTable {
    Param ($rows)

    $names = @($rows[0].Keys)
    $widths = @{}

    foreach ($name in $names) {
        $widths[$name] = (@($name) + @($rows | ForEach-Object { "$($_[$name])" }) | Measure-Object -Property "Length" -Maximum).Maximum
    }

    $lines = @("| " + (($names | ForEach-Object { $_.PadRight($widths[$_]) }) -join " | ") + " |")
    $lines += "| " + (($names | ForEach-Object { "-" * $widths[$_] }) -join " | ") + " |"

    foreach ($row in $rows) {
        $lines += "| " + (($names | ForEach-Object { "$($row[$_])".PadRight($widths[$_]) }) -join " | ") + " |"
    }

    $lines -join "`n"
}

function Invoke-Arm {
    Param ([String] $arm, [String] $configPath)

    $settings = $armSettings[$arm]
    $armPath = Split-Path -Path $configPath -Parent
    $armStopwatch = [System.Diagnostics.Stopwatch]::startNew()

    $row = [ordered]@{
        "Arm"                = $arm
        "Context"            = "-"
        "Slots"              = "-"
        "Chat decode tok/s"  = "-"
        "16K prompt tok/s"   = "-"
        "Agent decode tok/s" = "-"
        "2 clients tok/s"    = "-"
        "2 clients TTFT s"   = "-"
        "Needles"            = "-"
        "Minutes"            = "-"
        "Status"             = "ok"
    }

    Write-Host "Arm ${arm}: starting..." -ForegroundColor "Yellow"

    try {
        $process = Start-ArmServer -configPath $configPath -armPath $armPath
        $health = Wait-Server -process $process

        if (!$health) {
            throw "the server did not load, see server.log and engine.log"
        }

        Invoke-Smoke

        $row["Context"] = $health.max_context
        $row["Slots"] = (Invoke-RestMethod -Uri "${url}/v1/status" -TimeoutSec 10).concurrency.serving

        $benchArguments = if ($settings.parallel) { @("--clients", "$($settings.parallel)") } else { @() }
        $benchPath = Join-Path $armPath "bench"

        # Out-Host: their output would otherwise become this function's return value.
        & $benchmarkScript -url $url -out $benchPath -arguments $benchArguments | Out-Host

        $resultsPath = Get-ChildItem -Path $benchPath -Filter "results.json" -Recurse -File |
            Sort-Object -Property "LastWriteTime" -Descending |
            Select-Object -First 1 -ExpandProperty "FullName"

        $results = (Get-Content -Raw -Path $resultsPath | ConvertFrom-Json).results

        $row["Chat decode tok/s"] = Format-Value -value $results.chat.decode_tps.median -format "0.0"
        $row["16K prompt tok/s"] = Format-Value -value $results.prompts."16K".prompt_tps.median -format "0"
        $row["Agent decode tok/s"] = Format-Value -value $results.agent.turn_decode_tps.median -format "0.0"

        if ($settings.parallel) {
            $row["2 clients tok/s"] = Format-Value -value $results.clients.total_tps.median -format "0.0"
            $row["2 clients TTFT s"] = Format-Value -value $results.clients.ttft_p50_s -format "0.0"
        }

        if ($settings.needles) {
            $needlePath = Join-Path $armPath "needles.json"

            & $python $needleScript --url $url --lengths $settings.needles --depths $settings.depths --out $needlePath | Out-Host

            if (Test-Path -Path $needlePath) {
                $needles = @(Get-Content -Raw -Path $needlePath | ConvertFrom-Json)
                $done = @($needles | Where-Object { $_.PSObject.Properties.Name -contains "found" })
                $row["Needles"] = "$(@($done | Where-Object { $_.found }).Count) of $($done.Count)"
            } else {
                $row["Needles"] = "failed"
            }
        }
    } catch {
        $row["Status"] = "failed: $($_.Exception.Message -replace '[\r\n|]+', ' ')"
        Write-Host "Arm ${arm} failed: $($_.Exception.Message)" -ForegroundColor "Red"
    } finally {
        Stop-Server
    }

    $row["Minutes"] = Format-Value -value $armStopwatch.Elapsed.TotalMinutes -format "0"
    $row
}

if (!$tier) {
    throw "Name the tier: -tier <file name in presets/ without .json>."
}

$tierPath = Join-Path $PSScriptRoot "presets\${tier}.json"

if (-not (Test-Path -Path $tierPath)) {
    throw "No tier file '${tierPath}'."
}

if (-not (Test-Path -Path $python)) {
    throw "vendor/strata/.venv is missing. Follow README.md -> New machine first."
}

$owner = Get-PortOwner
$wasRunning = [bool]$owner

if ($wasRunning) {
    $commandLine = (Get-CimInstance -ClassName "Win32_Process" -Filter "ProcessId = ${owner}").CommandLine

    if ($commandLine -notlike "*${tier}.json*") {
        throw "The server on port ${port} does not run tier '${tier}', so the script could not restore it: ${commandLine}"
    }
}

$runPath = Join-Path $PSScriptRoot ".tmp\bench\experiment-$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
$selected = @($armOrder | Where-Object { $arms -contains $_ })
$configs = [ordered]@{}

foreach ($arm in $selected) {
    $armPath = Join-Path $runPath $arm
    New-Item -Path $armPath -ItemType "directory" -Force | Out-Null
    $configs[$arm] = New-ArmConfig -arm $arm -armPath $armPath
    Test-ArmConfig -configPath $configs[$arm]
}

Write-Host "Configs: ${runPath}" -ForegroundColor "DarkYellow"
Write-Host "Arms: $($selected -join ', ')" -ForegroundColor "DarkYellow"

if ($check) {
    Write-Host "The configs are fine. The server was not touched." -ForegroundColor "Yellow"
    exit
}

$strataVersion = git -C $strataPath describe --tags --always
$engineVersion = (Get-Content -Raw -Path (Join-Path $strataPath "engine\BUILD.json") | ConvertFrom-Json).version

Write-Host "The server on port ${port} stops in 10 seconds and is down for about an hour. Ctrl+C cancels." -ForegroundColor "Yellow"
Start-Sleep -Seconds 10

$rows = [System.Collections.Generic.List[object]]::new()

try {
    Stop-Server

    foreach ($arm in $selected) {
        $rows.Add((Invoke-Arm -arm $arm -configPath $configs[$arm]))
    }
} finally {
    Stop-Server

    if ($rows.Count) {
        $table = Format-MarkdownTable -rows $rows
        $summary = "# Experiment ${tier}`n`nStrata ${strataVersion}, engine ${engineVersion}, $(Get-Date -Format 'yyyy-MM-dd HH:mm').`n`n${table}`n"
        Set-Content -Path (Join-Path $runPath "summary.md") -Value $summary -Encoding "utf8"
        Write-Host $table
    }

    if ($wasRunning) {
        Write-Host "Starting tier ${tier} again in a new window..." -ForegroundColor "Yellow"

        $command = ".\.venv\Scripts\python.exe serve\server.py --engine strata --config ..\..\presets\${tier}.json --port ${port}"
        Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList "-NoExit -wd `"${strataPath}`" -c `"${command}`""

        if (Wait-Server -process $null) {
            Write-Host "Tier ${tier} is serving again." -ForegroundColor "Yellow"
        } else {
            Write-Host "Tier ${tier} did not answer within 10 minutes: check its window." -ForegroundColor "Red"
        }
    }
}

$stopwatch.Stop()
$durationInMinutes = [Math]::Floor($stopwatch.Elapsed.TotalMinutes)

Write-Host "Finished the experiment in ${durationInMinutes} minutes: $(Join-Path $runPath 'summary.md')" -ForegroundColor "Yellow"
