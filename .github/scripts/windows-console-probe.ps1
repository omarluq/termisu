param(
    [Parameter(Mandatory = $true)]
    [string]$ProbePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$probe = (Resolve-Path -LiteralPath $ProbePath).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ConsoleProbeHost {
    [DllImport("kernel32.dll", SetLastError = true)] public static extern uint GetConsoleProcessList([Out] uint[] processes, uint count);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool AllocConsole();
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool FreeConsole();
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int id);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetStdHandle(int id, IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr handle);
}
'@

$allocated = $false
$originalHandles = @{}
$consoleHandles = @()
$process = $null
$started = $false
foreach ($id in -10, -11, -12) {
    $originalHandles[$id] = [ConsoleProbeHost]::GetStdHandle($id)
}

# Attachment does not require a visible console window on headless runners.
$consoleProcessCount = [ConsoleProbeHost]::GetConsoleProcessList([uint32[]]::new(1), 1)
$hostInfo = @{
    os = [Environment]::OSVersion.VersionString
    powershell = $PSVersionTable.PSVersion.ToString()
    initialConsoleProcesses = $consoleProcessCount
    allocatedConsole = $false
    redirectedStdio = $true
}
$hostInfo | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'host.json')

try {
    if ($consoleProcessCount -eq 0) {
        if (-not [ConsoleProbeHost]::AllocConsole()) {
            throw [System.ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $allocated = $true
        foreach ($id in -10, -11, -12) {
            $handle = [ConsoleProbeHost]::GetStdHandle($id)
            if ($handle -ne [IntPtr]::Zero -and $handle -ne [IntPtr]::new(-1) -and
                $handle -notin $originalHandles.Values -and $handle -notin $consoleHandles) {
                $consoleHandles += $handle
            }
        }
        foreach ($id in -10, -11, -12) {
            # Keep the runner's log streams; only the test host allocates a console.
            if (-not [ConsoleProbeHost]::SetStdHandle($id, $originalHandles[$id])) {
                throw [System.ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
        }
    }

    $hostInfo.allocatedConsole = $allocated
    $hostInfo | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'host.json')

    $start = [Diagnostics.ProcessStartInfo]::new($probe)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.ArgumentList.Add('--verbose')
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Could not start the native console probe' }
    $started = $true
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit(30000)
    if ($timedOut) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    $out = $stdout.GetAwaiter().GetResult()
    $err = $stderr.GetAwaiter().GetResult()
    $out | Set-Content (Join-Path $OutputDirectory 'stdout.log')
    $err | Set-Content (Join-Path $OutputDirectory 'stderr.log')
    Write-Host $out
    if ($err) { Write-Host $err }
    if ($timedOut) { throw 'Native console probe timed out after 30 seconds' }
    if ($process.ExitCode -ne 0) { throw "Native console probe exited with $($process.ExitCode)" }
}
catch {
    $_ | Out-String | Set-Content (Join-Path $OutputDirectory 'host-error.log') -ErrorAction SilentlyContinue
    throw
}
finally {
    try {
        if ($null -ne $process) {
            try {
                if ($started -and -not $process.HasExited) {
                    $process.Kill($true)
                    $process.WaitForExit()
                }
            }
            finally {
                $process.Dispose()
            }
        }
    }
    finally {
        if ($allocated) {
            foreach ($id in -10, -11, -12) {
                [ConsoleProbeHost]::SetStdHandle($id, $originalHandles[$id]) | Out-Null
            }
            foreach ($handle in $consoleHandles) {
                [ConsoleProbeHost]::CloseHandle($handle) | Out-Null
            }
            [ConsoleProbeHost]::FreeConsole() | Out-Null
        }
    }
}
