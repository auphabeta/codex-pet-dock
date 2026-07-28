[CmdletBinding()]
param(
  [switch]$RemoveUserData,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$installRoot = Split-Path -Parent $PSCommandPath
$stateRoot = Join-Path `
  ([Environment]::GetFolderPath('LocalApplicationData')) `
  'CodexPetDock'
$startMenuRoot = Join-Path `
  ([Environment]::GetFolderPath('Programs')) `
  'Codex Pet Dock'
$runRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallRegistryPath = (
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexPetDock'
)

if (-not $Quiet) {
  $message = 'Uninstall Codex Pet Dock? Your themes and settings will be kept.'
  $answer = $Host.UI.PromptForChoice(
    'Codex Pet Dock',
    $message,
    @('&Uninstall', '&Cancel'),
    1
  )
  if ($answer -ne 0) {
    exit 0
  }
}

$escapedScriptPath = [regex]::Escape(
  (Join-Path $installRoot 'src\Start-CodexPetQuota.ps1')
)
Get-CimInstance -ClassName Win32_Process |
  Where-Object {
    $_.Name -in @('powershell.exe', 'pwsh.exe') -and
    [string]$_.CommandLine -match $escapedScriptPath
  } |
  ForEach-Object {
    Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue
  }

Remove-ItemProperty `
  -LiteralPath $runRegistryPath `
  -Name 'CodexPetDock' `
  -ErrorAction SilentlyContinue
Remove-Item `
  -LiteralPath $uninstallRegistryPath `
  -Recurse `
  -Force `
  -ErrorAction SilentlyContinue
Remove-Item `
  -LiteralPath $startMenuRoot `
  -Recurse `
  -Force `
  -ErrorAction SilentlyContinue

if ($RemoveUserData) {
  $resolvedStateRoot = [System.IO.Path]::GetFullPath($stateRoot)
  $expectedParent = [System.IO.Path]::GetFullPath(
    [Environment]::GetFolderPath('LocalApplicationData')
  )
  if (-not $resolvedStateRoot.StartsWith(
    $expectedParent + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw 'Refusing to remove an unexpected user-data path.'
  }
  Remove-Item `
    -LiteralPath $resolvedStateRoot `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue
}

$resolvedInstallRoot = [System.IO.Path]::GetFullPath($installRoot)
$expectedProgramsRoot = [System.IO.Path]::GetFullPath(
  (Join-Path `
    ([Environment]::GetFolderPath('LocalApplicationData')) `
    'Programs')
)
if (-not $resolvedInstallRoot.StartsWith(
  $expectedProgramsRoot + [System.IO.Path]::DirectorySeparatorChar,
  [System.StringComparison]::OrdinalIgnoreCase
)) {
  throw 'Refusing to remove an unexpected install path.'
}

$cleanupCommand = (
  'ping 127.0.0.1 -n 3 > nul & rmdir /s /q "' +
  $resolvedInstallRoot +
  '"'
)
Start-Process `
  -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') `
  -ArgumentList @('/d', '/c', $cleanupCommand) `
  -WindowStyle Hidden

Write-Host 'Codex Pet Dock was uninstalled.'
if (-not $RemoveUserData) {
  Write-Host ('Settings were kept at: ' + $stateRoot)
}

