#requires -Version 5.1
<#
    Start-DshSilent.ps1
    Starts the DeepSeek Harness desktop app and immediately hides its main
    window to the system tray, so the logon start is effectively silent.

    Safety rules:
      * If the app is already running, do nothing.
      * A busy port 2119 is only logged, never a reason to skip: the desktop
        app binds its own free port (observed 2119 and 11653 on this machine),
        so it can coexist with a running `dsh web`.
      * Never close the window; only hide it. The tray icon stays and
        restores the window on click.
#>
[CmdletBinding()]
param(
    [string]$ExePath = 'E:\DeepSeek Harness\DeepSeek Harness.exe',
    [int]$Port = 2119,
    [int]$DelaySeconds = 10,
    [int]$WaitSeconds = 180,
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA 'DshAutostart\autostart.log')
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    try {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch { }
}

function Test-LocalPortOpen {
    param([int]$PortNumber)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $PortNumber, $null, $null)
        $finished = $async.AsyncWaitHandle.WaitOne(400)
        return ($finished -and $client.Connected)
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch { }
    }
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class DshSilentWindow
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int command);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    // Hide every visible top-level product window owned by the given processes.
    // Chromium/Electron windows use the Chrome_WidgetWin_1 window class.
    public static int HideProductWindows(int[] processIds)
    {
        if (processIds == null || processIds.Length == 0) return 0;
        HashSet<int> wanted = new HashSet<int>(processIds);
        int hidden = 0;
        EnumWindows(delegate(IntPtr handle, IntPtr state)
        {
            uint owner;
            GetWindowThreadProcessId(handle, out owner);
            if (!wanted.Contains((int)owner)) return true;
            if (!IsWindowVisible(handle)) return true;

            StringBuilder cls = new StringBuilder(256);
            GetClassName(handle, cls, cls.Capacity);
            if (!cls.ToString().StartsWith("Chrome_WidgetWin_1", StringComparison.Ordinal)) return true;

            RECT rect;
            if (!GetWindowRect(handle, out rect)) return true;
            if (rect.Right - rect.Left < 200 || rect.Bottom - rect.Top < 200) return true;

            ShowWindow(handle, 0); // SW_HIDE
            hidden++;
            return true;
        }, IntPtr.Zero);
        return hidden;
    }
}
'@

$exeName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)

Write-Log '--- autostart run ---'

if ($DelaySeconds -gt 0) {
    Start-Sleep -Seconds $DelaySeconds
}

$already = @(Get-Process -Name $exeName -ErrorAction SilentlyContinue)
if ($already.Count -gt 0) {
    $ids = ($already | ForEach-Object { $_.Id }) -join ','
    Write-Log ("skip: {0} is already running (pid {1})" -f $exeName, $ids)
    exit 0
}

if (Test-LocalPortOpen -PortNumber $Port) {
    Write-Log ("note: port {0} is already in use (dsh web?); continuing anyway -- the desktop app picks its own port" -f $Port)
}

if (-not (Test-Path -LiteralPath $ExePath)) {
    Write-Log ("error: executable not found: {0}" -f $ExePath)
    exit 1
}

try {
    $process = Start-Process -FilePath $ExePath `
        -WorkingDirectory (Split-Path -Parent $ExePath) `
        -PassThru -ErrorAction Stop
} catch {
    Write-Log ("error: failed to start: {0}" -f $_.Exception.Message)
    exit 1
}
Write-Log ("started pid {0}" -f $process.Id)

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$hiddenTotal = 0
$lastHide = $null

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200

    if ($process.HasExited) {
        Write-Log ("note: process exited during startup (code {0})" -f $process.ExitCode)
        exit 0
    }

    $ids = @(Get-Process -Name $exeName -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.Id })
    if ($ids.Count -eq 0) { continue }

    $count = [DshSilentWindow]::HideProductWindows($ids)
    if ($count -gt 0) {
        $hiddenTotal += $count
        $lastHide = Get-Date
        Write-Log ("hidden {0} window(s); total {1}" -f $count, $hiddenTotal)
    }

    # After the first hide, keep watching briefly in case the app re-shows it.
    if ($null -ne $lastHide -and ((Get-Date) - $lastHide).TotalSeconds -gt 10) { break }
}

if ($hiddenTotal -eq 0) {
    Write-Log ("warning: no visible product window appeared within {0}s; app left running" -f $WaitSeconds)
} else {
    Write-Log ("done: {0} window(s) hidden; app stays in the system tray" -f $hiddenTotal)
}
exit 0
