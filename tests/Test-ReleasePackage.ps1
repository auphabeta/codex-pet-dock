[CmdletBinding()]
param(
  [string]$ZipPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ZipPath)) {
  $ZipPath = Join-Path $projectRoot 'dist\CodexPetDock-0.3.0-beta.zip'
}
$resolvedZipPath = [System.IO.Path]::GetFullPath($ZipPath)
if (-not [System.IO.File]::Exists($resolvedZipPath)) {
  throw 'Release ZIP does not exist: ' + $resolvedZipPath
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedZipPath)
try {
  $files = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
  $entryNames = @($files | ForEach-Object FullName)
  $requiredSuffixes = @(
    '\CodexPetDock.vbs',
    '\Install-Preview.cmd',
    '\LICENSE',
    '\NOTICE.md',
    '\src\Start-CodexPetQuota.ps1',
    '\src\native\CodexPetProbe.exe',
    '\assets\branding\codex-pet-dock.ico',
    '\.agents\skills\codex-pet-dock-theme\SKILL.md'
  )
  $missingRequiredEntries = @(
    foreach ($requiredSuffix in $requiredSuffixes) {
      if (-not ($entryNames | Where-Object { $_.EndsWith(
        $requiredSuffix,
        [System.StringComparison]::OrdinalIgnoreCase
      ) })) {
        $requiredSuffix
      }
    }
  )

  $forbiddenEntries = @(
    $files |
      Where-Object {
        $_.FullName -match (
          '(?i)(^|[\\/])docs[\\/](media|screenshots|video)([\\/]|$)|' +
          'darwin-result-card\.png$|results\.tsv$|test-prompts\.json$|' +
          'built-in-themes-preview\.png$'
        )
      } |
      ForEach-Object FullName
  )
  $repositoryOnlyMedia = @(
    $files |
      Where-Object {
        $_.FullName -match '(?i)\.(gif|jpe?g|webp|mp4|mov|avi|mkv|svg|psd|xcf)$'
      } |
      ForEach-Object FullName
  )

  $sensitiveTextEntries = New-Object System.Collections.Generic.List[string]
  foreach ($entry in $files | Where-Object {
    $_.FullName -match (
      '(?i)\.(ps1|psm1|cmd|vbs|md|json|yaml|yml|txt|cs)$|[\\/]LICENSE$'
    )
  }) {
    $reader = New-Object System.IO.StreamReader($entry.Open())
    try {
      $content = $reader.ReadToEnd()
    } finally {
      $reader.Dispose()
    }
    if ($content -match (
      '(?i)C:\\Users\\|E:\\workplace\\|BEGIN (RSA |EC |OPENSSH )?' +
      'PRIVATE KEY|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|' +
      'gh[pousr]_[A-Za-z0-9]{20,}'
    )) {
      $sensitiveTextEntries.Add($entry.FullName)
    }
  }

  if ($missingRequiredEntries.Count -gt 0) {
    throw 'Release is missing required entries: ' + ($missingRequiredEntries -join ', ')
  }
  if ($forbiddenEntries.Count -gt 0) {
    throw 'Release contains repository-only artifacts: ' + ($forbiddenEntries -join ', ')
  }
  if ($repositoryOnlyMedia.Count -gt 0) {
    throw 'Release contains documentation media: ' + ($repositoryOnlyMedia -join ', ')
  }
  if ($sensitiveTextEntries.Count -gt 0) {
    throw 'Release contains sensitive text patterns: ' + ($sensitiveTextEntries -join ', ')
  }
} finally {
  $archive.Dispose()
}

$checksumPath = $resolvedZipPath + '.sha256'
if (-not [System.IO.File]::Exists($checksumPath)) {
  throw 'Release checksum file does not exist: ' + $checksumPath
}
$expectedHash = (
  [System.IO.File]::ReadAllText($checksumPath) -split '\s+'
)[0].Trim()
$actualHash = (Get-FileHash -LiteralPath $resolvedZipPath -Algorithm SHA256).Hash
if ($expectedHash -ine $actualHash) {
  throw 'Release checksum does not match the ZIP.'
}

Write-Host (
  'Release audit PASS: ' +
  [string]$files.Count +
  ' files, no repository media or sensitive text patterns, SHA-256 ' +
  $actualHash
)
