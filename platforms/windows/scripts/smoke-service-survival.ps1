<#
.SYNOPSIS
    App-quit survival smoke test for managed services (design notes, section 6.5).

.DESCRIPTION
    Phase 1 launches a real managed service through the production manager in one
    test process and lets that process exit, simulating quitting Port Manager
    without stopping the child. The script then proves the child is still alive,
    still listening and still writing output seconds later.

    Phase 2 reloads the profile in a fresh process, reconciles against a real
    Windows port scan and requires the survivor to be reported as a Conflict
    this app does not own.

    This test is opt-in: normal `dotnet test` runs skip both phases because the
    `PORTKILLER_SURVIVAL_SMOKE` variable is not set.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smoke-service-survival.ps1
#>
#requires -Version 5.1
param(
    [int]$Port = 0,
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$solution = Join-Path $repoRoot "platforms/windows/PortKiller.sln"

if ($Port -eq 0) {
    $Port = Get-Random -Minimum 41000 -Maximum 55000
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("portkiller-survival-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

$info = Join-Path $work "info.txt"
$settings = Join-Path $work "settings.json"
$spamScript = Join-Path $work "spam_server.ps1"

@'
param([int]$Port)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
$i = 0
while ($true) {
    $i++
    Write-Output "stdout tick $i"
    [Console]::Error.WriteLine("stderr tick $i")
    Start-Sleep -Milliseconds 200
}
'@ | Set-Content -Path $spamScript -Encoding UTF8

function Test-Listening {
    param([int]$CheckPort)
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $client.Connect("127.0.0.1", $CheckPort)
        $client.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Get-SurvivorPid {
    if (-not (Test-Path $info)) { return 0 }
    $line = Get-Content $info | Where-Object { $_ -like "pid=*" } | Select-Object -First 1
    if (-not $line) { return 0 }
    return [int]($line -replace "^pid=", "")
}

try {
    Write-Host "==> phase 1: launch through the production manager, then let that process exit"
    $env:PORTKILLER_SURVIVAL_SMOKE = "launch"
    $env:PORTKILLER_SURVIVAL_PORT = "$Port"
    $env:PORTKILLER_SURVIVAL_SCRIPT = $spamScript
    $env:PORTKILLER_SURVIVAL_INFO = $info
    $env:PORTKILLER_SURVIVAL_SETTINGS = $settings

    & dotnet test $solution -c $Configuration --filter "FullyQualifiedName~ManagedServiceSurvivalSmokeTests.LaunchServiceThenLetThisProcessExit" -v minimal
    if ($LASTEXITCODE -ne 0) { throw "phase 1 dotnet test failed" }

    $childPid = Get-SurvivorPid
    if ($childPid -eq 0) { throw "phase 1 did not record the child PID" }

    $stdoutLog = (Get-Content $info | Where-Object { $_ -like "stdout=*" } | Select-Object -First 1) -replace "^stdout=", ""

    Start-Sleep -Seconds 3
    if (-not (Get-Process -Id $childPid -ErrorAction SilentlyContinue)) { throw "child $childPid died after app exit" }
    if (-not (Test-Listening -CheckPort $Port)) { throw "child stopped listening within 3s" }

    $before = (Get-Item $stdoutLog).Length
    Start-Sleep -Seconds 3
    $after = (Get-Item $stdoutLog).Length
    if ($after -le $before) { throw "child stopped writing stdout after app exit ($before -> $after bytes)" }

    Write-Host "==> child alive, listening and writing after app exit (stdout $before -> $after bytes)"

    Write-Host "==> phase 2: relaunch must detect the survivor as Conflict"
    $env:PORTKILLER_SURVIVAL_SMOKE = "relaunch"

    & dotnet test $solution -c $Configuration --filter "FullyQualifiedName~ManagedServiceSurvivalSmokeTests.RelaunchDetectsSurvivingServiceAsConflict" -v minimal
    if ($LASTEXITCODE -ne 0) { throw "phase 2 dotnet test failed" }

    Write-Host "==> PASS: child outlived Port Manager, kept listening/writing, and is a Conflict on relaunch"
}
finally {
    Remove-Item Env:PORTKILLER_SURVIVAL_SMOKE -ErrorAction SilentlyContinue
    Remove-Item Env:PORTKILLER_SURVIVAL_PORT -ErrorAction SilentlyContinue
    Remove-Item Env:PORTKILLER_SURVIVAL_SCRIPT -ErrorAction SilentlyContinue
    Remove-Item Env:PORTKILLER_SURVIVAL_INFO -ErrorAction SilentlyContinue
    Remove-Item Env:PORTKILLER_SURVIVAL_SETTINGS -ErrorAction SilentlyContinue

    $survivor = Get-SurvivorPid
    if ($survivor -ne 0) {
        Stop-Process -Id $survivor -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
