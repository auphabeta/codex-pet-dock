[CmdletBinding()]
param(
  [string]$Version = '0.3.0-beta'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$distRoot = Join-Path $projectRoot 'dist'
$packageName = 'CodexPetDock-' + $Version
$stagingRoot = Join-Path $distRoot $packageName
$zipPath = Join-Path $distRoot ($packageName + '.zip')
$checksumPath = $zipPath + '.sha256'

$resolvedProjectRoot = [System.IO.Path]::GetFullPath($projectRoot)
$resolvedDistRoot = [System.IO.Path]::GetFullPath($distRoot)
if (-not $resolvedDistRoot.StartsWith(
  $resolvedProjectRoot + [System.IO.Path]::DirectorySeparatorChar,
  [System.StringComparison]::OrdinalIgnoreCase
)) {
  throw 'Refusing to build outside the project workspace.'
}

[void][System.IO.Directory]::CreateDirectory($distRoot)
foreach ($target in @($stagingRoot, $zipPath, $checksumPath)) {
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
}
[void][System.IO.Directory]::CreateDirectory($stagingRoot)

foreach ($directory in @('src', 'docs', 'packaging')) {
  Copy-Item `
    -LiteralPath (Join-Path $projectRoot $directory) `
    -Destination $stagingRoot `
    -Recurse `
    -Force
}
[void][System.IO.Directory]::CreateDirectory(
  (Join-Path $stagingRoot 'tests')
)
foreach ($testScript in @(
  'Test-CodexPetDock.ps1',
  'Measure-CodexPetDockPerformance.ps1'
)) {
  Copy-Item `
    -LiteralPath (Join-Path $projectRoot ('tests\' + $testScript)) `
    -Destination (Join-Path $stagingRoot ('tests\' + $testScript)) `
    -Force
}
[void][System.IO.Directory]::CreateDirectory(
  (Join-Path $stagingRoot 'tests\fixtures\custom-theme')
)
Copy-Item `
  -LiteralPath (
    Join-Path $projectRoot 'tests\fixtures\custom-theme\theme.json'
  ) `
  -Destination (
    Join-Path $stagingRoot 'tests\fixtures\custom-theme\theme.json'
  ) `
  -Force
[void][System.IO.Directory]::CreateDirectory(
  (Join-Path $stagingRoot 'assets\branding')
)
[void][System.IO.Directory]::CreateDirectory(
  (Join-Path $stagingRoot 'assets\themes')
)
foreach ($asset in @(
  'tech-platform-v2.png',
  'tech-platform-amber.png',
  'tech-platform.png',
  'branding\codex-pet-dock.ico',
  'branding\codex-pet-dock-16.png',
  'themes\princess-cradle.png',
  'themes\forest-rune.png',
  'themes\clockwork-brass.png',
  'themes\moon-lotus.png',
  'themes\sakura-shrine.png',
  'themes\iron-throne.png',
  'themes\built-in-themes-preview.png'
)) {
  $assetSource = Join-Path (Join-Path $projectRoot 'assets') $asset
  $assetDestination = Join-Path (Join-Path $stagingRoot 'assets') $asset
  Copy-Item `
    -LiteralPath $assetSource `
    -Destination $assetDestination `
    -Force
}
foreach ($file in @(
  'CodexPetDock.vbs',
  'Install-Preview.cmd',
  'README.md',
  'PRODUCT.md',
  'CHANGELOG.md',
  'PRIVACY.md',
  'SECURITY.md',
  'NOTICE.md'
)) {
  $sourcePath = Join-Path $projectRoot $file
  if (Test-Path -LiteralPath $sourcePath) {
    Copy-Item `
      -LiteralPath $sourcePath `
      -Destination (Join-Path $stagingRoot $file) `
      -Force
  }
}

Compress-Archive `
  -LiteralPath $stagingRoot `
  -DestinationPath $zipPath `
  -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
Set-Content `
  -LiteralPath $checksumPath `
  -Encoding ASCII `
  -Value ($hash + '  ' + [System.IO.Path]::GetFileName($zipPath))

Write-Host ('Package: ' + $zipPath)
Write-Host ('SHA-256: ' + $hash)
