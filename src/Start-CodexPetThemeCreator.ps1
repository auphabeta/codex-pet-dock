[CmdletBinding()]
param(
  [ValidateSet('en-US', 'zh-CN')]
  [string]$Language = 'en-US',
  [string]$ProjectRootOverride = '',
  [switch]$Diagnostics
)

$ErrorActionPreference = 'Stop'
$projectRoot = if (
  [string]::IsNullOrWhiteSpace($ProjectRootOverride)
) {
  Split-Path -Parent $PSScriptRoot
} else {
  [System.IO.Path]::GetFullPath($ProjectRootOverride)
}
$skillPath = Join-Path `
  $projectRoot `
  '.agents\skills\codex-pet-dock-theme\SKILL.md'
if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
  throw (
    'The bundled Codex theme skill is missing: ' +
    $skillPath
  )
}

$localePath = Join-Path $PSScriptRoot ('locales\' + $Language + '.json')
if (-not (Test-Path -LiteralPath $localePath -PathType Leaf)) {
  throw 'The requested locale is missing: ' + $Language
}
$locale = Get-Content `
  -Raw `
  -Encoding UTF8 `
  -LiteralPath $localePath |
    ConvertFrom-Json
$prompt = [string]$locale.app.CreateWithCodexPrompt
if ([string]::IsNullOrWhiteSpace($prompt)) {
  throw 'The Codex theme creator prompt is missing from the locale.'
}
$encodedPrompt = [Uri]::EscapeDataString($prompt)
$encodedPath = [Uri]::EscapeDataString(
  [System.IO.Path]::GetFullPath($projectRoot)
)
$deepLink = (
  'codex://new?prompt=' +
  $encodedPrompt +
  '&path=' +
  $encodedPath
)

if ($Diagnostics) {
  [ordered]@{
    ok = $true
    language = $Language
    workspacePath = [System.IO.Path]::GetFullPath($projectRoot)
    skillPath = [System.IO.Path]::GetFullPath($skillPath)
    prompt = $prompt
    deepLinkScheme = ([Uri]$deepLink).Scheme
    promptEncoded = $deepLink.Contains($encodedPrompt)
    workspaceEncoded = $deepLink.Contains($encodedPath)
  } |
    ConvertTo-Json -Depth 4
  exit 0
}

Start-Process -FilePath $deepLink
