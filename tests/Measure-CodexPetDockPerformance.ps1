[CmdletBinding()]
param(
  [ValidateRange(5, 300)]
  [int]$DurationSeconds = 30,
  [string]$InstalledRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InstalledRoot)) {
  $InstalledRoot = Join-Path `
    ([Environment]::GetFolderPath('LocalApplicationData')) `
    'Programs\CodexPetDock'
}
$InstalledRoot = [System.IO.Path]::GetFullPath($InstalledRoot)
$mainScript = Join-Path $InstalledRoot 'src\Start-CodexPetQuota.ps1'
if (-not (Test-Path -LiteralPath $mainScript)) {
  throw 'Codex Pet Dock is not installed at: ' + $InstalledRoot
}

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class CodexPetDockPerformanceNative
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(
        EnumWindowsProc callback,
        IntPtr lParam
    );

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(
        IntPtr hWnd,
        out uint processId
    );

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    public static int CountVisibleWindows(uint processId)
    {
        int count = 0;
        EnumWindows((window, parameter) =>
        {
            uint ownerProcessId;
            GetWindowThreadProcessId(window, out ownerProcessId);
            if (
                ownerProcessId == processId &&
                IsWindowVisible(window)
            )
            {
                count++;
            }
            return true;
        }, IntPtr.Zero);
        return count;
    }
}
'@

$escapedScriptPath = [regex]::Escape($mainScript)
$dockProcesses = @(
  Get-CimInstance Win32_Process |
    Where-Object {
      $_.Name -in @('powershell.exe', 'pwsh.exe') -and
      [string]$_.CommandLine -match $escapedScriptPath
    }
)
if ($dockProcesses.Count -ne 1) {
  throw (
    'Expected one installed Codex Pet Dock process; found ' +
    [string]$dockProcesses.Count +
    '.'
  )
}

$processId = [int]$dockProcesses[0].ProcessId
$logicalProcessors = [math]::Max(
  1,
  [int](Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
)
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$manifestPath = Join-Path $InstalledRoot 'install-manifest.json'
$installedVersion = if (Test-Path -LiteralPath $manifestPath) {
  [string](
    Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath |
      ConvertFrom-Json
  ).version
} else {
  'unknown'
}

$initialProcess = Get-Process -Id $processId
$initialCpuSeconds = [double]$initialProcess.CPU
$initialCimProcess = Get-CimInstance Win32_Process -Filter (
  'ProcessId=' + [string]$processId
)
$initialReadBytes = [uint64]$initialCimProcess.ReadTransferCount
$initialWriteBytes = [uint64]$initialCimProcess.WriteTransferCount
$visibleWindowsAtStart = (
  [CodexPetDockPerformanceNative]::CountVisibleWindows(
    [uint32]$processId
  )
)

$workingSetSamples = New-Object System.Collections.Generic.List[double]
$privateMemorySamples = New-Object System.Collections.Generic.List[double]
$handleSamples = New-Object System.Collections.Generic.List[int]
$threadSamples = New-Object System.Collections.Generic.List[int]
$childSamples = New-Object System.Collections.Generic.List[int]
$nodeChildSamples = New-Object System.Collections.Generic.List[int]
$observedChildNames = New-Object System.Collections.Generic.HashSet[string]

for ($second = 0; $second -lt $DurationSeconds; $second++) {
  Start-Sleep -Seconds 1
  $sample = Get-Process -Id $processId -ErrorAction Stop
  $workingSetSamples.Add([double]$sample.WorkingSet64)
  $privateMemorySamples.Add([double]$sample.PrivateMemorySize64)
  $handleSamples.Add([int]$sample.HandleCount)
  $threadSamples.Add([int]$sample.Threads.Count)
  $childProcesses = @(
    Get-CimInstance Win32_Process |
      Where-Object { $_.ParentProcessId -eq $processId }
  )
  $childSamples.Add([int]$childProcesses.Count)
  $nodeChildSamples.Add([int]@(
    $childProcesses |
      Where-Object { $_.Name -eq 'node.exe' }
  ).Count)
  foreach ($childProcess in $childProcesses) {
    [void]$observedChildNames.Add([string]$childProcess.Name)
  }
}

$finalProcess = Get-Process -Id $processId
$finalCpuSeconds = [double]$finalProcess.CPU
$finalCimProcess = Get-CimInstance Win32_Process -Filter (
  'ProcessId=' + [string]$processId
)
$finalReadBytes = [uint64]$finalCimProcess.ReadTransferCount
$finalWriteBytes = [uint64]$finalCimProcess.WriteTransferCount
$visibleWindowsAtEnd = (
  [CodexPetDockPerformanceNative]::CountVisibleWindows(
    [uint32]$processId
  )
)
$cpuSeconds = [math]::Max(0, $finalCpuSeconds - $initialCpuSeconds)
$state = if (
  $visibleWindowsAtStart -gt 0 -and
  $visibleWindowsAtEnd -gt 0
) {
  'pet-visible'
} elseif (
  $visibleWindowsAtStart -eq 0 -and
  $visibleWindowsAtEnd -eq 0
) {
  'waiting-no-visible-pet'
} else {
  'state-changed-during-sample'
}

[pscustomobject]@{
  schemaVersion = 1
  measuredAtUtc = [DateTime]::UtcNow.ToString('o')
  installedVersion = $installedVersion
  state = $state
  durationSeconds = $DurationSeconds
  processId = $processId
  system = [ordered]@{
    os = [string]$operatingSystem.Caption
    osVersion = [string]$operatingSystem.Version
    cpu = [string]$processor.Name
    logicalProcessors = $logicalProcessors
  }
  cpu = [ordered]@{
    cpuSeconds = [math]::Round($cpuSeconds, 4)
    averagePercentOfOneLogicalProcessor = [math]::Round(
      ($cpuSeconds / $DurationSeconds) * 100,
      3
    )
    approximatePercentOfWholeMachine = [math]::Round(
      ($cpuSeconds / $DurationSeconds / $logicalProcessors) * 100,
      4
    )
  }
  memory = [ordered]@{
    averageWorkingSetMb = [math]::Round(
      ($workingSetSamples | Measure-Object -Average).Average / 1MB,
      2
    )
    peakWorkingSetMb = [math]::Round(
      ($workingSetSamples | Measure-Object -Maximum).Maximum / 1MB,
      2
    )
    averagePrivateMb = [math]::Round(
      ($privateMemorySamples | Measure-Object -Average).Average / 1MB,
      2
    )
    peakPrivateMb = [math]::Round(
      ($privateMemorySamples | Measure-Object -Maximum).Maximum / 1MB,
      2
    )
  }
  activity = [ordered]@{
    readBytesDelta = [uint64](
      [math]::Max(0, $finalReadBytes - $initialReadBytes)
    )
    writeBytesDelta = [uint64](
      [math]::Max(0, $finalWriteBytes - $initialWriteBytes)
    )
    averageHandles = [math]::Round(
      ($handleSamples | Measure-Object -Average).Average,
      1
    )
    peakHandles = [int](
      ($handleSamples | Measure-Object -Maximum).Maximum
    )
    averageThreads = [math]::Round(
      ($threadSamples | Measure-Object -Average).Average,
      1
    )
    peakThreads = [int](
      ($threadSamples | Measure-Object -Maximum).Maximum
    )
    peakChildProcesses = [int](
      ($childSamples | Measure-Object -Maximum).Maximum
    )
    peakNodeProbeProcesses = [int](
      ($nodeChildSamples | Measure-Object -Maximum).Maximum
    )
    observedChildProcessNames = @($observedChildNames | Sort-Object)
    visibleWindowsAtStart = $visibleWindowsAtStart
    visibleWindowsAtEnd = $visibleWindowsAtEnd
  }
} | ConvertTo-Json -Depth 6
