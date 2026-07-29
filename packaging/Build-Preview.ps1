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

& (Join-Path $PSScriptRoot 'Build-Native.ps1')

[void][System.IO.Directory]::CreateDirectory($distRoot)
foreach ($target in @($stagingRoot, $zipPath, $checksumPath)) {
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
}
[void][System.IO.Directory]::CreateDirectory($stagingRoot)

foreach ($directory in @('src', 'packaging')) {
  Copy-Item `
    -LiteralPath (Join-Path $projectRoot $directory) `
    -Destination $stagingRoot `
    -Recurse `
    -Force
}

# Release archives are installable artifacts, not mirrors of the source
# repository. Keep text documentation, but leave screenshots, videos and
# media-source libraries in GitHub where they can be viewed without inflating
# every user's download.
[void][System.IO.Directory]::CreateDirectory((Join-Path $stagingRoot 'docs'))
foreach ($document in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'docs') -File) {
  if ($document.Extension -ne '.md') {
    continue
  }
  Copy-Item `
    -LiteralPath $document.FullName `
    -Destination (Join-Path $stagingRoot ('docs\' + $document.Name)) `
    -Force
}

$themeSkillRelativeRoot = '.agents\skills\codex-pet-dock-theme'
$themeSkillFiles = @(
  'SKILL.md',
  'agents\openai.yaml'
)
foreach ($themeSkillFile in $themeSkillFiles) {
  $themeSkillDestination = Join-Path `
    (Join-Path $stagingRoot $themeSkillRelativeRoot) `
    $themeSkillFile
  [void][System.IO.Directory]::CreateDirectory(
    (Split-Path -Parent $themeSkillDestination)
  )
  Copy-Item `
    -LiteralPath (
      Join-Path `
        (Join-Path $projectRoot $themeSkillRelativeRoot) `
        $themeSkillFile
    ) `
    -Destination $themeSkillDestination `
    -Force
}
[void][System.IO.Directory]::CreateDirectory(
  (Join-Path $stagingRoot 'tests')
)
foreach ($testScript in @(
  'Test-CodexPetDock.ps1',
  'Test-ReleasePackage.ps1',
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
  (Join-Path $stagingRoot 'tests\fixtures\performance')
)
foreach ($performanceFixture in @(
  'NativeWinFormsShell.cs',
  'README.md'
)) {
  Copy-Item `
    -LiteralPath (
      Join-Path `
        $projectRoot `
        ('tests\fixtures\performance\' + $performanceFixture)
    ) `
    -Destination (
      Join-Path `
        $stagingRoot `
        ('tests\fixtures\performance\' + $performanceFixture)
    ) `
    -Force
}
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
  'themes\iron-throne.png'
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
  'NOTICE.md',
  'LICENSE'
)) {
  $sourcePath = Join-Path $projectRoot $file
  if (Test-Path -LiteralPath $sourcePath) {
    Copy-Item `
      -LiteralPath $sourcePath `
      -Destination (Join-Path $stagingRoot $file) `
      -Force
  }
}

$forbiddenReleaseEntries = @(
  'docs\media',
  'docs\screenshots',
  'docs\video',
  '.agents\skills\codex-pet-dock-theme\darwin-result-card.png',
  '.agents\skills\codex-pet-dock-theme\results.tsv',
  '.agents\skills\codex-pet-dock-theme\test-prompts.json',
  'assets\themes\built-in-themes-preview.png'
)
$stagingPrefixLength = $stagingRoot.TrimEnd('\').Length + 1
$packagedRelativeFiles = @(
  Get-ChildItem -LiteralPath $stagingRoot -Recurse -File |
    ForEach-Object {
      $_.FullName.Substring($stagingPrefixLength)
    }
)
$unexpectedReleaseEntries = @(
  foreach ($forbiddenEntry in $forbiddenReleaseEntries) {
    $forbiddenPrefix = $forbiddenEntry.TrimEnd('\') + '\'
    $packagedRelativeFiles |
      Where-Object {
        $_ -ieq $forbiddenEntry -or
        $_.StartsWith(
          $forbiddenPrefix,
          [System.StringComparison]::OrdinalIgnoreCase
        )
      }
  }
)
if ($unexpectedReleaseEntries.Count -gt 0) {
  throw (
    'Release contains repository-only media or audit artifacts: ' +
    (($unexpectedReleaseEntries | Sort-Object -Unique) -join ', ')
  )
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
