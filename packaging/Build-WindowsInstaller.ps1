[CmdletBinding()]
param(
  [string]$Version = '0.3.0-beta',
  [string]$NumericVersion = '0.3.0.0'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$distRoot = Join-Path $projectRoot 'dist'
$payloadRoot = Join-Path $distRoot ('CodexPetDock-' + $Version)
$setupName = 'CodexPetDock-Setup-' + $Version + '.exe'
$setupPath = Join-Path $distRoot $setupName

& (Join-Path $PSScriptRoot 'Build-Preview.ps1') -Version $Version

$compilerCandidates = @(
  (Join-Path `
    ([Environment]::GetFolderPath('LocalApplicationData')) `
    'Programs\Inno Setup 6\ISCC.exe'),
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$iscc = $compilerCandidates |
  Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1
if ([string]::IsNullOrWhiteSpace([string]$iscc)) {
  throw (
    'Inno Setup 6 was not found. Install JRSoftware.InnoSetup with winget ' +
    'or provide ISCC.exe in a standard install location.'
  )
}

$installerDefinition = Join-Path `
  $PSScriptRoot `
  'windows\CodexPetDock.iss'
& $iscc `
  ('/DProductVersion=' + $Version) `
  ('/DNumericVersion=' + $NumericVersion) `
  ('/DPayloadRoot=' + $payloadRoot) `
  ('/DProjectRoot=' + $projectRoot) `
  ('/DOutputDir=' + $distRoot) `
  $installerDefinition
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $setupPath)) {
  throw 'Windows installer compilation failed.'
}

$signingThumbprint = [Environment]::GetEnvironmentVariable(
  'CODEX_PET_DOCK_SIGNING_THUMBPRINT'
)
if (-not [string]::IsNullOrWhiteSpace($signingThumbprint)) {
  $signTool = Get-Command signtool.exe -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Source -First 1
  if ([string]::IsNullOrWhiteSpace([string]$signTool)) {
    throw 'A signing thumbprint was provided, but signtool.exe was not found.'
  }
  & $signTool sign `
    /sha1 $signingThumbprint `
    /fd SHA256 `
    /tr http://timestamp.digicert.com `
    /td SHA256 `
    $setupPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Authenticode signing failed.'
  }
}

$zipPath = Join-Path $distRoot ('CodexPetDock-' + $Version + '.zip')
$artifacts = @($setupPath, $zipPath)
$checksumLines = @(
  foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
    $hash + '  ' + [System.IO.Path]::GetFileName($artifact)
  }
)
$checksumsPath = Join-Path $distRoot 'SHA256SUMS.txt'
Set-Content `
  -LiteralPath $checksumsPath `
  -Encoding ASCII `
  -Value $checksumLines

Write-Host ('Setup: ' + $setupPath)
Write-Host ('Portable ZIP: ' + $zipPath)
Write-Host ('Checksums: ' + $checksumsPath)
Write-Host (
  'Authenticode: ' +
  $(if ([string]::IsNullOrWhiteSpace($signingThumbprint)) {
    'not signed (no certificate thumbprint provided)'
  } else {
    'signed'
  })
)
