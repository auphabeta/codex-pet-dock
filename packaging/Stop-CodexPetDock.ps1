[CmdletBinding()]
param(
  [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
  $InstallRoot = Join-Path `
    ([Environment]::GetFolderPath('LocalApplicationData')) `
    'Programs\CodexPetDock'
}
$resolvedInstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$expectedProgramsRoot = [System.IO.Path]::GetFullPath(
  (Join-Path `
    ([Environment]::GetFolderPath('LocalApplicationData')) `
    'Programs')
)
if (-not $resolvedInstallRoot.StartsWith(
  $expectedProgramsRoot + [System.IO.Path]::DirectorySeparatorChar,
  [System.StringComparison]::OrdinalIgnoreCase
)) {
  throw 'Refusing to manage processes for an unexpected install path.'
}

$scriptNames = @(
  'Start-CodexPetQuota.ps1',
  'Start-CodexPetThemeCreator.ps1'
)
$escapedInstallRoot = [regex]::Escape($resolvedInstallRoot)
Get-CimInstance -ClassName Win32_Process |
  Where-Object {
    $candidateProcess = $_
    $candidateCommandLine = [string]$candidateProcess.CommandLine
    $matchesProductScript = @(
      $scriptNames |
        Where-Object {
          $candidateCommandLine -match [regex]::Escape($_)
        }
    ).Count -gt 0
    $candidateProcess.Name -in @('powershell.exe', 'pwsh.exe') -and
    $candidateCommandLine -match $escapedInstallRoot -and
    $matchesProductScript
  } |
  ForEach-Object {
    Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue
  }

Get-CimInstance -ClassName Win32_Process |
  Where-Object {
    $_.Name -eq 'CodexPetProbe.exe' -and
    [string]$_.ExecutablePath -like ($resolvedInstallRoot + '\*')
  } |
  ForEach-Object {
    Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue
  }
