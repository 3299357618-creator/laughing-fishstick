#requires -Version 5.1
<#
    Install-DshAutostart.ps1
    Installs silent-at-logon startup for the DeepSeek Harness desktop app.

    What it does:
      1. Copies Start-DshSilent.ps1 + Start-DshSilent.vbs to
         %LOCALAPPDATA%\DshAutostart  (a stable install location).
      2. Registers the scheduled task "DSH Silent Autostart" that runs the
         launcher at logon through wscript.exe (no console window).

    Usage:
      powershell -ExecutionPolicy Bypass -File .\Install-DshAutostart.ps1
          -> for the CURRENT user (no admin needed)

      powershell -ExecutionPolicy Bypass -File .\Install-DshAutostart.ps1 -AllUsers
          -> for ALL users (needs admin; the script re-launches itself
             elevated through a UAC prompt when necessary)

      powershell -ExecutionPolicy Bypass -File .\Install-DshAutostart.ps1 -Uninstall
          -> removes the task and the installed copies

    Re-run the install command after editing any script: the installed copy is
    refreshed every time.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers,
    [switch]$Uninstall,
    [string]$TaskName = 'DSH Silent Autostart'
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installDir = Join-Path $env:LOCALAPPDATA 'DshAutostart'
$sourcePs1 = Join-Path $scriptDir 'Start-DshSilent.ps1'
$sourceVbs = Join-Path $scriptDir 'Start-DshSilent.vbs'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- uninstall
if ($Uninstall) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task: $TaskName" -ForegroundColor Green
    } else {
        Write-Host "Task not found: $TaskName" -ForegroundColor Yellow
    }
    if (Test-Path -LiteralPath $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed install folder: $installDir"
    }
    exit 0
}

# ---------------------------------------------------------------- validate
foreach ($file in @($sourcePs1, $sourceVbs)) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Missing required file: $file"
    }
}

# ---------------------------------------------------------------- elevation
if ($AllUsers -and -not (Test-IsAdmin)) {
    Write-Host 'Installing for all users requires administrator rights. Requesting elevation...' -ForegroundColor Yellow
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-AllUsers',
        '-TaskName', $TaskName
    )
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
    exit 0
}

# ---------------------------------------------------------------- install
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -LiteralPath $sourcePs1 -Destination (Join-Path $installDir 'Start-DshSilent.ps1') -Force
Copy-Item -LiteralPath $sourceVbs -Destination (Join-Path $installDir 'Start-DshSilent.vbs') -Force

$launcher = Join-Path $installDir 'Start-DshSilent.vbs'

$action = New-ScheduledTaskAction `
    -Execute 'wscript.exe' `
    -Argument ('//B //Nologo "{0}"' -f $launcher)

if ($AllUsers) {
    # Every interactive user who logs on to this machine.
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -GroupId 'Users' -LogonType Group
    $scopeText = 'all users'
} else {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
    $scopeText = $currentUser
}

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Starts DeepSeek Harness silently at logon and hides it to the system tray.' `
    -Force | Out-Null

Write-Host ''
Write-Host "Installed scheduled task : $TaskName" -ForegroundColor Green
Write-Host "Scope                    : $scopeText"
Write-Host "Launcher                 : $launcher"
Write-Host "Log file                 : $(Join-Path $installDir 'autostart.log')"
Write-Host ''
Write-Host 'Test it now without rebooting:' -ForegroundColor Cyan
Write-Host "    Start-ScheduledTask -TaskName '$TaskName'"
Write-Host 'Uninstall with:' -ForegroundColor Cyan
Write-Host '    powershell -ExecutionPolicy Bypass -File .\Install-DshAutostart.ps1 -Uninstall'
Write-Host ''
