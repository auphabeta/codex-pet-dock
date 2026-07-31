[CmdletBinding()]
param(
  [string]$InstallRoot,
  [switch]$ValidateOnly,
  [switch]$SelectedRootOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
  $InstallRoot = Join-Path `
    ([Environment]::GetFolderPath('LocalApplicationData')) `
    'Programs\CodexPetDock'
}

function Get-SafeInstallRoot {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (
    -not [System.IO.Path]::IsPathRooted($Path) -or
    $Path.StartsWith('\\', [System.StringComparison]::Ordinal) -or
    $Path.IndexOfAny([char[]]@('*', '?')) -ge 0
  ) {
    throw 'The install path must be an absolute path on a local drive.'
  }

  $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $driveRoot = [System.IO.Path]::GetPathRoot($resolvedPath).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  if (
    [string]::IsNullOrWhiteSpace($resolvedPath) -or
    [string]::IsNullOrWhiteSpace($driveRoot) -or
    $resolvedPath.Equals(
      $driveRoot,
      [System.StringComparison]::OrdinalIgnoreCase
    )
  ) {
    throw 'The drive root cannot be used as the install directory.'
  }

  return $resolvedPath
}

$resolvedInstallRoot = Get-SafeInstallRoot -Path $InstallRoot
if ($ValidateOnly) {
  Write-Output $resolvedInstallRoot
  exit 0
}

$managedInstallRoots = New-Object `
  'System.Collections.Generic.HashSet[string]' `
  ([System.StringComparer]::OrdinalIgnoreCase)
[void]$managedInstallRoots.Add($resolvedInstallRoot)

if (-not $SelectedRootOnly) {
  $defaultInstallRoot = Join-Path `
    ([Environment]::GetFolderPath('LocalApplicationData')) `
    'Programs\CodexPetDock'
  [void]$managedInstallRoots.Add(
    (Get-SafeInstallRoot -Path $defaultInstallRoot)
  )

  $uninstallRegistryRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
      '{5C836C8E-D328-4A2D-A271-30FBB9D39D01}_is1',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' +
      'CodexPetDock'
  )
  foreach ($registryRoot in $uninstallRegistryRoots) {
    $registeredInstallRoot = [string](
      Get-ItemProperty `
        -LiteralPath $registryRoot `
        -Name InstallLocation `
        -ErrorAction SilentlyContinue
    ).InstallLocation
    if ([string]::IsNullOrWhiteSpace($registeredInstallRoot)) {
      continue
    }
    try {
      [void]$managedInstallRoots.Add(
        (Get-SafeInstallRoot -Path $registeredInstallRoot)
      )
    } catch {
      # Ignore stale or malformed legacy registration; the selected path was
      # already validated and remains the authoritative install destination.
    }
  }
}

$managedScriptPaths = @(
  foreach ($managedInstallRoot in $managedInstallRoots) {
    Join-Path $managedInstallRoot 'src\Start-CodexPetQuota.ps1'
    Join-Path $managedInstallRoot 'src\Start-CodexPetThemeCreator.ps1'
  }
)
$managedProbePaths = @(
  foreach ($managedInstallRoot in $managedInstallRoots) {
    Join-Path $managedInstallRoot 'src\native\CodexPetProbe.exe'
  }
)

function Get-ManagedProcesses {
  @(
    Get-CimInstance -ClassName Win32_Process |
      Where-Object {
        $candidateProcess = $_
        $candidateCommandLine = [string]$candidateProcess.CommandLine
        $matchesProductScript = @(
          $managedScriptPaths |
            Where-Object {
              $candidateCommandLine -match [regex]::Escape($_)
            }
        ).Count -gt 0
        (
          $candidateProcess.Name -in @('powershell.exe', 'pwsh.exe') -and
          $matchesProductScript
        ) -or (
          $candidateProcess.Name -eq 'CodexPetProbe.exe' -and
          -not [string]::IsNullOrWhiteSpace(
            [string]$candidateProcess.ExecutablePath
          ) -and
          [string]$candidateProcess.ExecutablePath -in $managedProbePaths
        )
      }
  )
}

$managedProcesses = @(Get-ManagedProcesses)
foreach ($managedProcess in $managedProcesses) {
  Stop-Process `
    -Id ([int]$managedProcess.ProcessId) `
    -Force `
    -ErrorAction SilentlyContinue
}

if ($managedProcesses.Count -gt 0) {
  $deadline = [DateTime]::UtcNow.AddSeconds(3)
  do {
    Start-Sleep -Milliseconds 100
    $remainingProcesses = @(Get-ManagedProcesses)
  } while (
    $remainingProcesses.Count -gt 0 -and
    [DateTime]::UtcNow -lt $deadline
  )

  if ($remainingProcesses.Count -gt 0) {
    throw (
      'Could not stop Codex Pet Dock process IDs: ' +
      (($remainingProcesses | ForEach-Object ProcessId) -join ', ')
    )
  }
}
