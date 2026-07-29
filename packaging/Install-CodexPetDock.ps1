[CmdletBinding()]
param(
  [switch]$LaunchAtSignIn,
  [switch]$DoNotLaunchAtSignIn,
  [switch]$DoNotLaunch,
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
if ($LaunchAtSignIn -and $DoNotLaunchAtSignIn) {
  throw 'Choose either -LaunchAtSignIn or -DoNotLaunchAtSignIn, not both.'
}
$productName = 'Codex Pet Dock'
$productVersion = '0.3.0-beta'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$installRoot = Join-Path `
  ([Environment]::GetFolderPath('LocalApplicationData')) `
  'Programs\CodexPetDock'
$stateRoot = Join-Path `
  ([Environment]::GetFolderPath('LocalApplicationData')) `
  'CodexPetDock'
$launcherPath = Join-Path $installRoot 'CodexPetDock.vbs'
$iconPath = Join-Path `
  $installRoot `
  'assets\branding\codex-pet-dock.ico'
$startMenuRoot = Join-Path `
  ([Environment]::GetFolderPath('Programs')) `
  'Codex Pet Dock'
$shortcutPath = Join-Path $startMenuRoot 'Codex Pet Dock.lnk'
$uninstallShortcutPath = Join-Path `
  $startMenuRoot `
  'Uninstall Codex Pet Dock.lnk'
$runRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallRegistryPath = (
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexPetDock'
)

function Assert-PreviewPrerequisites {
  $nativeProbePath = Join-Path `
    $sourceRoot `
    'src\native\CodexPetProbe.exe'
  if (-not (Test-Path -LiteralPath $nativeProbePath)) {
    $nativeBuildScript = Join-Path $PSScriptRoot 'Build-Native.ps1'
    if (Test-Path -LiteralPath $nativeBuildScript) {
      & $nativeBuildScript
    }
  }

  foreach ($relativePath in @(
    'CodexPetDock.vbs',
    'src\Start-CodexPetQuota.ps1',
    'src\native\CodexPetProbe.exe',
    'assets\branding\codex-pet-dock.ico'
  )) {
    $sourcePath = Join-Path $sourceRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
      throw 'Release payload is incomplete: ' + $relativePath
    }
  }
}

function Stop-InstalledPreview {
  if (-not (Test-Path -LiteralPath $installRoot)) {
    return
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
}

function New-ApplicationShortcut {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [string]$Arguments = ''
  )

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($Path)
  $shortcut.TargetPath = $TargetPath
  $shortcut.Arguments = $Arguments
  $shortcut.WorkingDirectory = $installRoot
  $shortcut.IconLocation = $iconPath + ',0'
  $shortcut.Description = $productName
  $shortcut.Save()
}

Assert-PreviewPrerequisites
if ($ValidateOnly) {
  Write-Host (
    $productName +
    ' Preview payload and local prerequisites are valid.'
  )
  exit 0
}
Stop-InstalledPreview

[void][System.IO.Directory]::CreateDirectory($installRoot)
[void][System.IO.Directory]::CreateDirectory($stateRoot)
[void][System.IO.Directory]::CreateDirectory($startMenuRoot)

foreach ($obsoleteRelativePath in @(
  'src\quota-probe.mjs'
)) {
  $obsoletePath = Join-Path $installRoot $obsoleteRelativePath
  if ([System.IO.File]::Exists($obsoletePath)) {
    [System.IO.File]::Delete($obsoletePath)
  }
}

foreach ($directory in @('src', 'assets', 'docs')) {
  Copy-Item `
    -LiteralPath (Join-Path $sourceRoot $directory) `
    -Destination $installRoot `
    -Recurse `
    -Force
}
foreach ($file in @(
  'CodexPetDock.vbs',
  'README.md',
  'PRODUCT.md',
  'CHANGELOG.md'
)) {
  Copy-Item `
    -LiteralPath (Join-Path $sourceRoot $file) `
    -Destination (Join-Path $installRoot $file) `
    -Force
}
Copy-Item `
  -LiteralPath (Join-Path $PSScriptRoot 'Uninstall-CodexPetDock.ps1') `
  -Destination (Join-Path $installRoot 'Uninstall-CodexPetDock.ps1') `
  -Force

[ordered]@{
  schemaVersion = 1
  name = $productName
  version = $productVersion
  installedAt = [DateTime]::UtcNow.ToString('o')
  source = 'preview-installer'
} |
  ConvertTo-Json |
  Set-Content `
    -LiteralPath (Join-Path $installRoot 'install-manifest.json') `
    -Encoding UTF8

$wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
New-ApplicationShortcut `
  -Path $shortcutPath `
  -TargetPath $wscriptPath `
  -Arguments ('"' + $launcherPath + '"')

$powershellPath = Join-Path `
  $env:SystemRoot `
  'System32\WindowsPowerShell\v1.0\powershell.exe'
New-ApplicationShortcut `
  -Path $uninstallShortcutPath `
  -TargetPath $powershellPath `
  -Arguments (
    '-NoProfile -ExecutionPolicy RemoteSigned -File "' +
    (Join-Path $installRoot 'Uninstall-CodexPetDock.ps1') +
    '"'
  )

[void](New-Item -Path $uninstallRegistryPath -Force)
$uninstallCommand = (
  '"' +
  $powershellPath +
  '" -NoProfile -ExecutionPolicy RemoteSigned -File "' +
  (Join-Path $installRoot 'Uninstall-CodexPetDock.ps1') +
  '"'
)
$uninstallValues = [ordered]@{
  DisplayName = $productName
  DisplayVersion = $productVersion
  Publisher = 'Codex Pet Dock contributors'
  DisplayIcon = $iconPath
  InstallLocation = $installRoot
  UninstallString = $uninstallCommand
  NoModify = 1
  NoRepair = 1
}
foreach ($entry in $uninstallValues.GetEnumerator()) {
  [void](New-ItemProperty `
    -Path $uninstallRegistryPath `
    -Name $entry.Key `
    -Value $entry.Value `
    -Force)
}

$enableLaunchAtSignIn = $LaunchAtSignIn -or -not $DoNotLaunchAtSignIn
if ($enableLaunchAtSignIn) {
  if (-not (Test-Path -LiteralPath $runRegistryPath)) {
    [void](New-Item -Path $runRegistryPath)
  }
  [void](New-ItemProperty `
    -Path $runRegistryPath `
    -Name 'CodexPetDock' `
    -Value ('"' + $wscriptPath + '" "' + $launcherPath + '"') `
    -PropertyType String `
    -Force)
} else {
  Remove-ItemProperty `
    -LiteralPath $runRegistryPath `
    -Name 'CodexPetDock' `
    -ErrorAction SilentlyContinue
}

if (-not $DoNotLaunch) {
  Start-Process `
    -FilePath $wscriptPath `
    -ArgumentList ('"' + $launcherPath + '"') `
    -WindowStyle Hidden
}

Write-Host ($productName + ' ' + $productVersion + ' installed.')
Write-Host ('Location: ' + $installRoot)
Write-Host (
  'Launch at sign-in: ' +
  $(if ($enableLaunchAtSignIn) { 'enabled' } else { 'disabled' })
)
Write-Host 'Configuration is preserved separately under LocalAppData.'
