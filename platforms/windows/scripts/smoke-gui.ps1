<#
.SYNOPSIS
    Automated GUI smoke test for the Local Services panel using the published
    x64 artifact.

.DESCRIPTION
    Publishes PortKiller for win-x64, launches the real WPF application and
    drives it with UI Automation: Local Services navigation, Add Service,
    Start (lifecycle), noisy output (threading), Stop, Edit while stopped,
    Conflict detection against an external occupant, Delete (profile only) and
    final cleanup. Screenshots and UI Automation tree dumps are written to the
    artifact directory.
#>
param(
    [string]$Configuration = "Release",
    [int]$Port = 0
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$project = Join-Path $repoRoot "platforms/windows/PortKiller/PortKiller.csproj"
$publishDir = Join-Path $repoRoot "artifacts/gui-smoke"
$evidenceDir = Join-Path $repoRoot "artifacts/gui-smoke-evidence"

Remove-Item -Recurse -Force $publishDir, $evidenceDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $evidenceDir | Out-Null

$log = Join-Path $evidenceDir "gui-smoke.log"
function Log([string]$message) {
    $line = "$(Get-Date -Format o) $message"
    Write-Host $line
    Add-Content -Path $log -Value $line
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class GuiSmokeNative {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$UIA = [System.Windows.Automation.AutomationElement]
$Desktop = [System.Windows.Automation.AutomationElement]::RootElement
$TrueCondition = [System.Windows.Automation.Condition]::TrueCondition

function New-IdCondition([string]$id) { New-Object System.Windows.Automation.PropertyCondition($UIA::AutomationIdProperty, $id) }
function New-NameCondition([string]$name) { New-Object System.Windows.Automation.PropertyCondition($UIA::NameProperty, $name) }
function New-PidCondition([int]$processId) { New-Object System.Windows.Automation.PropertyCondition($UIA::ProcessIdProperty, $processId) }

function Wait-Element($root, $condition, [int]$timeoutSeconds, [string]$label) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    do {
        $found = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($found) { return $found }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for $label"
}

function Wait-Window([int]$processId, [int]$timeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    do {
        $found = $Desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, (New-PidCondition $processId))
        if ($found) { return $found }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for a window of process $processId"
}

function Wait-TopLevel([string]$name, [int]$timeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    do {
        $found = $Desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, (New-NameCondition $name))
        if ($found) { return $found }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for the '$name' window"
}

function Get-AncestorWindow($element) {
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $current = $element
    while ($current) {
        if ($current.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) { return $current }
        $current = $walker.GetParent($current)
    }
    return $element
}

function Dump-Desktop([string]$name) {
    $path = Join-Path $evidenceDir "desktop-$name.txt"
    $elements = $Desktop.FindAll([System.Windows.Automation.TreeScope]::Children, $TrueCondition)
    $lines = foreach ($element in $elements) {
        try {
            $info = $element.Current
            "pid={0} | {1} | id={2} | name={3}" -f $info.ProcessId, $info.ControlType.ProgrammaticName, $info.AutomationId, $info.Name
        } catch { }
    }
    Set-Content -Path $path -Value $lines
    Log "desktop dump: $path ($($lines.Count) windows)"
}

function Invoke-Element($element, [string]$label) {
    Log "invoke: $label"
    $pattern = $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
    Start-Sleep -Milliseconds 500
}

function Set-ElementText($root, [string]$automationId, [string]$text) {
    $element = Wait-Element $root (New-IdCondition $automationId) 10 "text box $automationId"
    $pattern = $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $pattern.SetValue($text)
    Log "set $automationId = $text"
}

function Dump-Tree($root, [string]$name) {
    $path = Join-Path $evidenceDir "tree-$name.txt"
    $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $TrueCondition)
    $lines = foreach ($element in $elements) {
        try {
            $info = $element.Current
            "{0} | id={1} | name={2} | rect={3}" -f $info.ControlType.ProgrammaticName, $info.AutomationId, $info.Name, $info.BoundingRectangle
        } catch { }
    }
    Set-Content -Path $path -Value $lines
    Log "tree dump: $path ($($lines.Count) elements)"
}

function Save-Screenshot($root, [string]$name) {
    try {
        $hwnd = [IntPtr]$root.Current.NativeWindowHandle
        if ($hwnd -eq [IntPtr]::Zero) { return }
        $rect = New-Object GuiSmokeNative+RECT
        [void][GuiSmokeNative]::GetWindowRect($hwnd, [ref]$rect)
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        if ($width -le 0 -or $height -le 0) { return }
        $bitmap = New-Object System.Drawing.Bitmap($width, $height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $hdc = $graphics.GetHdc()
        [void][GuiSmokeNative]::PrintWindow($hwnd, $hdc, 2)
        $graphics.ReleaseHdc($hdc)
        $graphics.Dispose()
        $path = Join-Path $evidenceDir "shot-$name.png"
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        Log "screenshot: $path"
    } catch {
        Log "screenshot failed: $_"
    }
}

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $chosen = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()
    return $chosen
}

function Test-Port([int]$checkPort, [int]$timeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    do {
        try {
            $client = [System.Net.Sockets.TcpClient]::new()
            $client.Connect("127.0.0.1", $checkPort)
            $client.Close()
            return $true
        } catch {
            Start-Sleep -Milliseconds 300
        }
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Test-PortClosed([int]$checkPort, [int]$timeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    do {
        try {
            $client = [System.Net.Sockets.TcpClient]::new()
            $client.Connect("127.0.0.1", $checkPort)
            $client.Close()
            Start-Sleep -Milliseconds 300
        } catch {
            return $true
        }
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Find-TextContaining($root, [string]$needle) {
    $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $TrueCondition)
    foreach ($element in $elements) {
        try { if ($element.Current.Name -like "*$needle*") { return $element } } catch { }
    }
    return $null
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("portkiller-gui-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$spamScript = Join-Path $work "gui_spam.ps1"
$externalScript = Join-Path $work "gui_occupant.ps1"
$appProcess = $null
$occupantProcess = $null

@'
param([int]$Port)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
$i = 0
while ($true) {
    $i++
    Write-Output "stdout tick $i"
    [Console]::Error.WriteLine("stderr tick $i")
    Start-Sleep -Milliseconds 100
}
'@ | Set-Content -Path $spamScript -Encoding UTF8

@'
param([int]$Port)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
while ($true) { Start-Sleep -Seconds 1 }
'@ | Set-Content -Path $externalScript -Encoding UTF8

try {
    if ($Port -eq 0) { $Port = Get-FreePort }
    Log "using port $Port"

    Log "publishing $project"
    & dotnet publish $project -c $Configuration -r win-x64 --self-contained false -o $publishDir | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

    $exe = Join-Path $publishDir "PortKiller.exe"
    if (-not (Test-Path $exe)) { throw "published exe not found: $exe" }

    Log "launching $exe"
    $appProcess = Start-Process -FilePath $exe -PassThru
    Start-Sleep -Seconds 2

    $mainWindow = Wait-Window $appProcess.Id 40
    [void][GuiSmokeNative]::ShowWindow([IntPtr]$mainWindow.Current.NativeWindowHandle, 9)
    [void][GuiSmokeNative]::SetForegroundWindow([IntPtr]$mainWindow.Current.NativeWindowHandle)
    Log "main window: $($mainWindow.Current.Name)"
    Dump-Tree $mainWindow "00-main"
    Save-Screenshot $mainWindow "00-main"

    Invoke-Element (Wait-Element $mainWindow (New-IdCondition "NavLocalServices") 15 "Local Services nav") "Local Services nav"
    Start-Sleep -Seconds 2
    Dump-Tree $mainWindow "01-local-services"
    Save-Screenshot $mainWindow "01-local-services"

    Invoke-Element (Wait-Element $mainWindow (New-NameCondition "Add Service") 15 "Add Service button") "Add Service"
    Start-Sleep -Seconds 2
    Dump-Desktop "02a-after-add"

    $nameBox = Wait-Element $Desktop (New-IdCondition "NameBox") 25 "editor NameBox"
    $editor = Get-AncestorWindow $nameBox
    Log "editor window: $($editor.Current.Name)"
    Dump-Tree $editor "02-editor"

    Set-ElementText $editor "NameBox" "GUI Smoke"
    Set-ElementText $editor "PortBox" "$Port"
    Set-ElementText $editor "HostBox" "localhost"
    Set-ElementText $editor "DirectoryBox" $work
    $command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $spamScript + '" {port}'
    Set-ElementText $editor "CommandBox" $command
    Invoke-Element (Wait-Element $editor (New-NameCondition "Save") 10 "editor Save button") "editor Save"
    Start-Sleep -Seconds 1
    Dump-Tree $mainWindow "03-after-add"

    Invoke-Element (Wait-Element $mainWindow (New-NameCondition "Start") 15 "Start button") "Start"
    if (-not (Test-Port $Port 45)) { throw "service did not listen on port $Port after Start" }
    Log "service is listening on $Port"
    Start-Sleep -Seconds 8
    if ($appProcess.HasExited) { throw "app exited while the service was running" }
    $running = Find-TextContaining $mainWindow "Running"
    Log "threading soak survived while running; status element: $($running.Current.Name)"
    Dump-Tree $mainWindow "04-running"
    Save-Screenshot $mainWindow "04-running"

    Invoke-Element (Wait-Element $mainWindow (New-NameCondition "Stop") 15 "Stop button") "Stop"
    if (-not (Test-PortClosed $Port 30)) { throw "service still listening after Stop" }
    Log "service stopped"

    Invoke-Element (Wait-Element $mainWindow (New-NameCondition "Edit") 15 "Edit button") "Edit"
    $nameBox2 = Wait-Element $Desktop (New-IdCondition "NameBox") 25 "editor NameBox (stopped edit)"
    $editor2 = Get-AncestorWindow $nameBox2
    Set-ElementText $editor2 "NameBox" "GUI Smoke Edited"
    Invoke-Element (Wait-Element $editor2 (New-NameCondition "Save") 10 "editor Save button") "editor Save (stopped edit)"
    Start-Sleep -Seconds 1
    if (Test-Port $Port 2) { throw "saving an edit restarted the service" }
    Log "stopped edit saved without restarting the service"
    Dump-Tree $mainWindow "05-after-edit"

    Log "starting an external occupant on port $Port"
    $occupantProcess = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $externalScript, "$Port") -PassThru
    if (-not (Test-Port $Port 20)) { throw "external occupant did not start" }

    Invoke-Element (Wait-Element $mainWindow (New-NameCondition "Start") 15 "Start button (conflict)") "Start (conflict)"
    Start-Sleep -Seconds 3
    $conflict = Find-TextContaining $mainWindow "Conflict"
    if (-not $conflict) { throw "conflict was not reported after starting against an occupied port" }
    Log "conflict reported: $($conflict.Current.Name)"
    Dump-Tree $mainWindow "06-conflict"
    Save-Screenshot $mainWindow "06-conflict"

    Invoke-Element (Wait-Element $mainWindow (New-NameCondition "Delete") 15 "Delete button") "Delete"
    $dialog = Wait-TopLevel "Delete service" 15
    Invoke-Element (Wait-Element $dialog (New-NameCondition "OK") 10 "delete confirmation OK button") "delete confirmation OK"
    Start-Sleep -Seconds 2
    if ($occupantProcess.HasExited) { throw "deleting a conflict profile killed the occupant" }
    Log "conflict profile deleted; external occupant still alive"
    Dump-Tree $mainWindow "07-after-delete"
    Save-Screenshot $mainWindow "07-after-delete"

    Log "PASS: GUI smoke completed lifecycle, threading, edit, conflict and delete"
}
finally {
    if ($occupantProcess -and -not $occupantProcess.HasExited) { Stop-Process -Id $occupantProcess.Id -Force -ErrorAction SilentlyContinue }
    if ($appProcess -and -not $appProcess.HasExited) { Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
