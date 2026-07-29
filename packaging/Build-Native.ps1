[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'src\native\CodexPetProbe.cs'
$outputPath = Join-Path $projectRoot 'src\native\CodexPetProbe.exe'
$windowsDirectory = [Environment]::GetFolderPath(
  [Environment+SpecialFolder]::Windows
)
if ([string]::IsNullOrWhiteSpace($windowsDirectory)) {
  $windowsDirectory = 'C:\Windows'
}
$compilerCandidates = @(
  (Join-Path $windowsDirectory 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $windowsDirectory 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates |
  Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1
if ([string]::IsNullOrWhiteSpace([string]$compiler)) {
  throw (
    'The Windows .NET Framework compiler was not found. ' +
    'Windows 11 with .NET Framework 4.8 or newer is required to build.'
  )
}
if (-not (Test-Path -LiteralPath $sourcePath)) {
  throw 'Native probe source is missing: ' + $sourcePath
}

& $compiler `
  /nologo `
  /warn:4 `
  /optimize+ `
  /target:exe `
  /platform:x64 `
  ('/out:' + $outputPath) `
  /reference:System.dll `
  /reference:System.Core.dll `
  /reference:System.Web.Extensions.dll `
  $sourcePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
  throw 'CodexPetProbe.exe compilation failed.'
}

Write-Host ('Native probe: ' + $outputPath)
