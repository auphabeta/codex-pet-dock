[CmdletBinding()]
param(
  [switch]$SkipIntegration
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sidecarScript = Join-Path $projectRoot 'src\Start-CodexPetQuota.ps1'
$themeStudioScript = Join-Path `
  $projectRoot `
  'src\Start-CodexPetThemeStudio.ps1'
$probeScript = Join-Path $projectRoot 'src\native\CodexPetProbe.exe'
$probeSourcePath = Join-Path $projectRoot 'src\native\CodexPetProbe.cs'
$nativeBuildScript = Join-Path $projectRoot 'packaging\Build-Native.ps1'
if (-not (Test-Path -LiteralPath $probeScript)) {
  & $nativeBuildScript
}
$results = New-Object System.Collections.Generic.List[object]
$failures = 0

function Add-TestResult {
  param(
    [Parameter(Mandatory = $true)][string]$Area,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][bool]$Passed,
    [string]$Detail = ''
  )

  if (-not $Passed) {
    $script:failures += 1
  }
  $script:results.Add([pscustomobject]@{
    Area = $Area
    Test = $Name
    Result = if ($Passed) { 'PASS' } else { 'FAIL' }
    Detail = $Detail
  })
}

function Invoke-Diagnostics {
  param([Parameter(Mandatory = $true)][string]$Theme)

  $output = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $sidecarScript `
    -Diagnostics `
    -Theme $Theme 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw 'Diagnostics failed for ' + $Theme + ': ' + ($output -join ' ')
  }
  return (($output -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Invoke-MascotSelectionDiagnostics {
  $output = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $sidecarScript `
    -MascotSelectionDiagnostics 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw (
      'Mascot selection diagnostics failed: ' +
      ($output -join ' ')
    )
  }
  return (($output -join [Environment]::NewLine) | ConvertFrom-Json)
}

Add-Type -AssemblyName System.Drawing

$requiredAssets = @(
  @{ Name = 'Holo Cyan'; File = 'assets\tech-platform-v2.png'; Width = 896; Height = 288 },
  @{ Name = 'Holo Amber'; File = 'assets\tech-platform-amber.png'; Width = 896; Height = 288 },
  @{ Name = 'Circuit Flat'; File = 'assets\tech-platform.png'; Width = 896; Height = 256 },
  @{ Name = 'Princess Cradle'; File = 'assets\themes\princess-cradle.png'; Width = 896; Height = 288 },
  @{ Name = 'Forest Rune'; File = 'assets\themes\forest-rune.png'; Width = 896; Height = 288 },
  @{ Name = 'Clockwork Brass'; File = 'assets\themes\clockwork-brass.png'; Width = 896; Height = 288 },
  @{ Name = 'Moon Lotus'; File = 'assets\themes\moon-lotus.png'; Width = 896; Height = 288 },
  @{ Name = 'Sakura Shrine'; File = 'assets\themes\sakura-shrine.png'; Width = 896; Height = 288 },
  @{ Name = 'Iron Throne'; File = 'assets\themes\iron-throne.png'; Width = 896; Height = 384 }
)
foreach ($asset in $requiredAssets) {
  $assetPath = Join-Path $projectRoot $asset.File
  $exists = Test-Path -LiteralPath $assetPath
  Add-TestResult `
    -Area 'Assets' `
    -Name ($asset.Name + ' exists') `
    -Passed $exists `
    -Detail $assetPath
  if (-not $exists) {
    continue
  }

  $bitmap = New-Object System.Drawing.Bitmap $assetPath
  try {
    $sizeOk = (
      $bitmap.Width -eq [int]$asset.Width -and
      $bitmap.Height -eq [int]$asset.Height
    )
    Add-TestResult `
      -Area 'Assets' `
      -Name ($asset.Name + ' dimensions') `
      -Passed $sizeOk `
      -Detail ([string]$bitmap.Width + 'x' + [string]$bitmap.Height)

    $transparentCorners = (
      $bitmap.GetPixel(0, 0).A -eq 0 -and
      $bitmap.GetPixel($bitmap.Width - 1, 0).A -eq 0 -and
      $bitmap.GetPixel(0, $bitmap.Height - 1).A -eq 0 -and
      $bitmap.GetPixel($bitmap.Width - 1, $bitmap.Height - 1).A -eq 0
    )
    Add-TestResult `
      -Area 'Assets' `
      -Name ($asset.Name + ' transparent corners') `
      -Passed $transparentCorners
  } finally {
    $bitmap.Dispose()
  }
}

$assetHashes = @(
  $requiredAssets |
    ForEach-Object {
      $assetPath = Join-Path $projectRoot $_.File
      if (Test-Path -LiteralPath $assetPath) {
        [pscustomobject]@{
          Name = $_.Name
          Hash = (Get-FileHash `
            -LiteralPath $assetPath `
            -Algorithm SHA256).Hash
        }
      }
    }
)
$duplicateHashes = @(
  $assetHashes |
    Group-Object -Property Hash |
    Where-Object { $_.Count -gt 1 }
)
$duplicateHashDetail = if ($duplicateHashes.Count -eq 0) {
  'unique=' + [string]$assetHashes.Count
} else {
  $duplicateHashes.Name -join ', '
}
Add-TestResult `
  -Area 'Themes' `
  -Name 'Built-in theme assets have no exact duplicates' `
  -Passed ($duplicateHashes.Count -eq 0) `
  -Detail $duplicateHashDetail

$themeFeatures = @{}
foreach ($asset in $requiredAssets) {
  $assetPath = Join-Path $projectRoot $asset.File
  if (-not (Test-Path -LiteralPath $assetPath)) {
    continue
  }
  $sourceImage = New-Object System.Drawing.Bitmap $assetPath
  $sampleImage = New-Object System.Drawing.Bitmap 64, 32
  $sampleGraphics = [System.Drawing.Graphics]::FromImage($sampleImage)
  try {
    $sampleGraphics.Clear(
      [System.Drawing.Color]::FromArgb(12, 16, 27)
    )
    $sampleGraphics.DrawImage($sourceImage, 0, 0, 64, 32)
    $feature = New-Object System.Collections.Generic.List[double]
    for ($sampleY = 0; $sampleY -lt 32; $sampleY++) {
      for ($sampleX = 0; $sampleX -lt 64; $sampleX++) {
        $pixel = $sampleImage.GetPixel($sampleX, $sampleY)
        $feature.Add(
          ($pixel.R + $pixel.G + $pixel.B) / (3.0 * 255)
        )
      }
    }
    $themeFeatures[[string]$asset.Name] = $feature.ToArray()
  } finally {
    $sampleGraphics.Dispose()
    $sampleImage.Dispose()
    $sourceImage.Dispose()
  }
}

$visualPairs = @()
$featureNames = @($themeFeatures.Keys)
for ($leftIndex = 0; $leftIndex -lt $featureNames.Count; $leftIndex++) {
  for (
    $rightIndex = $leftIndex + 1;
    $rightIndex -lt $featureNames.Count;
    $rightIndex++
  ) {
    $leftName = [string]$featureNames[$leftIndex]
    $rightName = [string]$featureNames[$rightIndex]
    $leftFeature = $themeFeatures[$leftName]
    $rightFeature = $themeFeatures[$rightName]
    $squareSum = 0.0
    for ($featureIndex = 0; $featureIndex -lt $leftFeature.Length; $featureIndex++) {
      $difference = $leftFeature[$featureIndex] - $rightFeature[$featureIndex]
      $squareSum += $difference * $difference
    }
    $orderedPair = @($leftName, $rightName) | Sort-Object
    $visualPairs += [pscustomobject]@{
      Pair = $orderedPair -join '|'
      Distance = [math]::Sqrt($squareSum / $leftFeature.Length)
    }
  }
}
$allowedNearVariants = @('Holo Amber|Holo Cyan')
$unexpectedNearDuplicates = @(
  $visualPairs |
    Where-Object {
      $_.Distance -lt 0.03 -and
      $_.Pair -notin $allowedNearVariants
    }
)
$closestPair = $visualPairs |
  Sort-Object -Property Distance |
  Select-Object -First 1
Add-TestResult `
  -Area 'Themes' `
  -Name 'Built-in themes have no unexpected visual duplicates' `
  -Passed ($unexpectedNearDuplicates.Count -eq 0) `
  -Detail (
    'closest=' +
    [string]$closestPair.Pair +
    ', distance=' +
    ([double]$closestPair.Distance).ToString('0.0000') +
    ' (intentional palette variant)'
  )

$iconPath = Join-Path `
  $projectRoot `
  'assets\branding\codex-pet-dock.ico'
$iconExists = Test-Path -LiteralPath $iconPath
Add-TestResult `
  -Area 'Branding' `
  -Name 'Custom application icon exists' `
  -Passed $iconExists `
  -Detail $iconPath
if ($iconExists) {
  $icon = New-Object System.Drawing.Icon $iconPath
  try {
    Add-TestResult `
      -Area 'Branding' `
      -Name 'Custom icon is readable by Windows' `
      -Passed ($icon.Width -ge 16 -and $icon.Height -ge 16) `
      -Detail ([string]$icon.Width + 'x' + [string]$icon.Height)
  } finally {
    $icon.Dispose()
  }
}

$smallIconPath = Join-Path `
  $projectRoot `
  'assets\branding\codex-pet-dock-16.png'
$smallIconExists = Test-Path -LiteralPath $smallIconPath
Add-TestResult `
  -Area 'Branding' `
  -Name 'Tray-size icon exists' `
  -Passed $smallIconExists `
  -Detail $smallIconPath
if ($smallIconExists) {
  $smallIcon = New-Object System.Drawing.Bitmap $smallIconPath
  try {
    Add-TestResult `
      -Area 'Branding' `
      -Name 'Tray-size icon is 16x16 with alpha' `
      -Passed (
        $smallIcon.Width -eq 16 -and
        $smallIcon.Height -eq 16 -and
        $smallIcon.PixelFormat.ToString() -match 'Argb|Alpha'
      ) `
      -Detail (
        [string]$smallIcon.Width +
        'x' +
        [string]$smallIcon.Height +
        ', ' +
        [string]$smallIcon.PixelFormat
      )
  } finally {
    $smallIcon.Dispose()
  }
}

$sidecarSource = [System.IO.File]::ReadAllText($sidecarScript)
$probeSource = [System.IO.File]::ReadAllText($probeSourcePath)
$performanceScript = Join-Path `
  $projectRoot `
  'tests\Measure-CodexPetDockPerformance.ps1'
$performanceDocument = Join-Path $projectRoot 'docs\performance.md'
$performanceSource = if (Test-Path -LiteralPath $performanceScript) {
  [System.IO.File]::ReadAllText($performanceScript)
} else {
  ''
}
$performanceDocumentSource = if (
  Test-Path -LiteralPath $performanceDocument
) {
  [System.IO.File]::ReadAllText(
    $performanceDocument,
    [System.Text.Encoding]::UTF8
  )
} else {
  ''
}
$performanceTokens = $null
$performanceParseErrors = $null
if (Test-Path -LiteralPath $performanceScript) {
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $performanceScript,
    [ref]$performanceTokens,
    [ref]$performanceParseErrors
  )
}
$englishLocalePath = Join-Path $projectRoot 'src\locales\en-US.json'
$chineseLocalePath = Join-Path $projectRoot 'src\locales\zh-CN.json'
$englishLocaleSource = [System.IO.File]::ReadAllText(
  $englishLocalePath,
  [System.Text.Encoding]::UTF8
)
$chineseLocaleSource = [System.IO.File]::ReadAllText(
  $chineseLocalePath,
  [System.Text.Encoding]::UTF8
)
$englishLocale = $englishLocaleSource | ConvertFrom-Json
$chineseLocale = $chineseLocaleSource | ConvertFrom-Json
$englishAppKeys = @($englishLocale.app.PSObject.Properties.Name | Sort-Object)
$chineseAppKeys = @($chineseLocale.app.PSObject.Properties.Name | Sort-Object)
$englishStudioKeys = @(
  $englishLocale.studio.PSObject.Properties.Name |
    Sort-Object
)
$chineseStudioKeys = @(
  $chineseLocale.studio.PSObject.Properties.Name |
    Sort-Object
)
Add-TestResult `
  -Area 'Localization' `
  -Name 'English and Chinese locale contracts have matching keys' `
  -Passed (
    (Test-Path -LiteralPath $englishLocalePath) -and
    (Test-Path -LiteralPath $chineseLocalePath) -and
    (($englishAppKeys -join '|') -eq ($chineseAppKeys -join '|')) -and
    (($englishStudioKeys -join '|') -eq ($chineseStudioKeys -join '|'))
  ) `
  -Detail (
    'app=' +
    [string]$englishAppKeys.Count +
    ', studio=' +
    [string]$englishStudioKeys.Count
  )
Add-TestResult `
  -Area 'Power policy' `
  -Name 'No-pet polling is throttled to one second' `
  -Passed (
    $sidecarSource -match (
      '(?s)\$petSearchIntervalSeconds\s*=\s*if\s*\(.+?' +
      '\)\s*\{\s*1\.0'
    ) -and
    $sidecarSource -match '\$timer\.Interval\s*=\s*1000'
  )
Add-TestResult `
  -Area 'Power policy' `
  -Name 'Quota refresh requires a visible pet' `
  -Passed (
    $sidecarSource -match (
      '\$script:currentPetWindow\.Visible\s+-and\s+' +
      '\$null\s+-eq\s+\$script:probeProcess'
    ) -and
    $sidecarSource -match 'Stop-QuotaRefresh'
  )
Add-TestResult `
  -Area 'Power policy' `
  -Name 'Default quota refresh is five minutes' `
  -Passed (
    $sidecarSource -match '\[int\]\$RefreshSeconds\s*=\s*300' -and
    $sidecarSource -match '\$quotaFreshness\.AgeSeconds\s+-ge\s+300'
  )
Add-TestResult `
  -Area 'Power policy' `
  -Name 'Quota failures use bounded exponential backoff' `
  -Passed (
    $sidecarSource -match '\$probeFailureCount' -and
    $sidecarSource -match '\$probeFailureBaseSeconds\s*=\s*900' -and
    $sidecarSource -match '\$nextAutomaticProbeAt' -and
    $sidecarSource -match (
      '(?s)\$retrySeconds\s*=\s*\[math\]::Min\(.+?' +
      '3600.+?\$probeFailureBaseSeconds.+?\[math\]::Pow'
    )
  )
Add-TestResult `
  -Area 'Data' `
  -Name 'Weekly Token scans use a privacy-preserving file cache' `
  -Passed (
    $sidecarSource -match 'token-usage-cache-v1\.json' -and
    $sidecarSource -match '--token-cache' -and
    $probeSource -match 'class TokenUsageIndex' -and
    $probeSource -match 'SHA256\.Create\(\)' -and
    $probeSource -match 'filesParsed' -and
    $probeSource -match 'cacheHits'
  )
Add-TestResult `
  -Area 'Reliability' `
  -Name 'Native probe terminates its app-server process tree' `
  -Passed (
    $probeSource -match 'class ChildProcessJob' -and
    $probeSource -match 'KillOnJobClose' -and
    $probeSource -match 'AssignProcessToJobObject' -and
    $probeSource -match 'job\.Add\(process\)'
  )
Add-TestResult `
  -Area 'Interaction' `
  -Name 'Pet switching invalidates stale anchors and accelerates reacquisition' `
  -Passed (
    $sidecarSource -match 'Reset-PetMascotTracking -ClearLastBounds' -and
    $sidecarSource -match '\$mascotAutomationIdentity' -and
    $sidecarSource -match 'Get-StableMascotIdentity' -and
    $sidecarSource -match 'Select-PetMascotCandidate' -and
    $sidecarSource -match '\$snapDockToMascotAtNextFrame' -and
    $sidecarSource -match (
      '(?s)\$petSearchIntervalSeconds\s*=\s*if\s*\(.+?' +
      '\)\s*\{.+?\}\s*else\s*\{\s*0\.5'
    ) -and
    $sidecarSource -match '80\s*\r?\n\s*\}\s*else\s*\{\s*\r?\n\s*500' -and
    $sidecarSource -match '\$lastMascotGraceSeconds' -and
    $sidecarSource -match '0\.35'
  )
$mascotSelectionDiagnostics = Invoke-MascotSelectionDiagnostics
Add-TestResult `
  -Area 'Interaction' `
  -Name 'First pet switch keeps the on-screen anchor and ignores remount IDs' `
  -Passed (
    $mascotSelectionDiagnostics.selectedCandidate -eq 'main-current' -and
    $mascotSelectionDiagnostics.remountIdentityStable
  ) `
  -Detail (
    'selected=' +
    [string]$mascotSelectionDiagnostics.selectedCandidate +
    ', identityStable=' +
    [string]$mascotSelectionDiagnostics.remountIdentityStable
  )
Add-TestResult `
  -Area 'Power policy' `
  -Name 'Dock movement is smoothed only while active and idles cheaply' `
  -Passed (
    $sidecarSource -match 'function Get-SmoothedDockCoordinate' -and
    $sidecarSource -match '\[double\]\$delta \* 0\.68' -and
    $sidecarSource -match '\$script:baseIsSettling' -and
    $sidecarSource -match '\$basePositionChanged -or \$zOrderMaintenanceDue' -and
    $sidecarSource -match 'TotalMilliseconds -ge 1000' -and
    $sidecarSource -match 'Extend-FastTracking -Milliseconds 400'
  )
Add-TestResult `
  -Area 'Performance' `
  -Name 'Reproducible benchmark and honest reference report are included' `
  -Passed (
    (Test-Path -LiteralPath $performanceScript) -and
    (Test-Path -LiteralPath $performanceDocument) -and
    @($performanceParseErrors).Count -eq 0 -and
    $performanceSource -match 'DurationSeconds' -and
    $performanceSource -match 'averagePercentOfOneLogicalProcessor' -and
    $performanceSource -match 'peakNodeProbeProcesses' -and
    $performanceSource -match 'peakQuotaProbeProcesses' -and
    $performanceDocumentSource -match '0\.2083%' -and
    $performanceDocumentSource -match 'not a guarantee' -and
    $performanceDocumentSource -match 'does not measure GPU energy'
  )
Add-TestResult `
  -Area 'Reliability' `
  -Name 'Single-instance guard is enabled by default' `
  -Passed (
    $sidecarSource -match 'Local\\CodexPetDock\.Singleton' -and
    $sidecarSource -match '\$AllowMultipleInstances' -and
    $sidecarSource -match 'Local\\CodexPetDock\.Activate'
  )
Add-TestResult `
  -Area 'Reliability' `
  -Name 'Config writes are atomic and logs are bounded' `
  -Passed (
    $sidecarSource -match '\[System\.IO\.File\]::Replace' -and
    $sidecarSource -match 'sidecar\.previous\.log' -and
    $sidecarSource -match '262144'
  )
Add-TestResult `
  -Area 'Onboarding' `
  -Name 'Tray exposes waiting, connected, and duplicate-launch status' `
  -Passed (
    $englishLocaleSource -match 'WAITING.+Open Codex pet' -and
    $englishLocaleSource -match 'CONNECTED.+Loading quota' -and
    $englishLocaleSource -match 'already running'
  )
Add-TestResult `
  -Area 'Data trust' `
  -Name 'Quota freshness and local Token semantics are explicit' `
  -Passed (
    $englishLocaleSource -match 'STALE DATA' -and
    $englishLocaleSource -match 'LOCAL WEEK TOKENS' -and
    $englishLocaleSource -match 'not billing data'
  )
try {
  $panelLayoutOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $sidecarScript `
    -PanelLayoutDiagnostics `
    -Language 'en-US' 2>&1
  $panelLayoutExit = $LASTEXITCODE
  $panelLayout = (
    ($panelLayoutOutput -join [Environment]::NewLine) |
      ConvertFrom-Json
  )
  $clippedPanelControls = @(
    $panelLayout.controls |
      Where-Object { -not $_.textFits -or -not $_.insidePanel }
  )
  Add-TestResult `
    -Area 'Layout' `
    -Name 'Quota detail text is measured, visible, and non-overlapping' `
    -Passed (
      $panelLayoutExit -eq 0 -and
      $panelLayout.ok -and
      [string]$panelLayout.language -eq 'en-US' -and
      $panelLayout.baseMetricsFontFits -and
      [int]$panelLayout.overlapCount -eq 0 -and
      $clippedPanelControls.Count -eq 0
    ) `
    -Detail (
      [string]$panelLayout.panelWidth +
      'x' +
      [string]$panelLayout.panelHeight +
      ', controls=' +
      [string]@($panelLayout.controls).Count +
      ', clipped=' +
      [string]$clippedPanelControls.Count
    )
} catch {
  Add-TestResult `
    -Area 'Layout' `
    -Name 'Quota detail text is measured, visible, and non-overlapping' `
    -Passed $false `
    -Detail $_.Exception.Message
}
try {
  $chinesePanelLayoutOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $sidecarScript `
    -PanelLayoutDiagnostics `
    -Language 'zh-CN' 2>&1
  $chinesePanelLayoutExit = $LASTEXITCODE
  $chinesePanelLayout = (
    ($chinesePanelLayoutOutput -join [Environment]::NewLine) |
      ConvertFrom-Json
  )
  $clippedChinesePanelControls = @(
    $chinesePanelLayout.controls |
      Where-Object { -not $_.textFits -or -not $_.insidePanel }
  )
  Add-TestResult `
    -Area 'Localization' `
    -Name 'Chinese Dock and detail panel text fit without overlap' `
    -Passed (
      $chinesePanelLayoutExit -eq 0 -and
      $chinesePanelLayout.ok -and
      [string]$chinesePanelLayout.language -eq 'zh-CN' -and
      [string]$chinesePanelLayout.baseLeftHeader -eq
        [string]$chineseLocale.app.WeekLeft -and
      [string]$chinesePanelLayout.baseRightHeader -eq
        [string]$chineseLocale.app.WeekTokens -and
      $chinesePanelLayout.baseMetricsFontFits -and
      [int]$chinesePanelLayout.overlapCount -eq 0 -and
      $clippedChinesePanelControls.Count -eq 0
    ) `
    -Detail (
      [string]$chinesePanelLayout.panelWidth +
      'x' +
      [string]$chinesePanelLayout.panelHeight +
      ', clipped=' +
      [string]$clippedChinesePanelControls.Count
    )
} catch {
  Add-TestResult `
    -Area 'Localization' `
    -Name 'Chinese Dock and detail panel text fit without overlap' `
    -Passed $false `
    -Detail $_.Exception.Message
}
Add-TestResult `
  -Area 'Custom themes' `
  -Name 'Theme Studio and hot reload entry points exist' `
  -Passed (
    (Test-Path -LiteralPath $themeStudioScript) -and
    $sidecarSource -match 'Start-CodexPetThemeStudio\.ps1' -and
    $sidecarSource -match 'Local\\CodexPetDock\.ReloadThemes' -and
    $englishLocaleSource -match 'Reload custom themes'
  )
$vibePromptPath = Join-Path `
  $projectRoot `
  'docs\vibe-custom-theme-prompt.md'
$vibePromptSource = if (Test-Path -LiteralPath $vibePromptPath) {
  Get-Content -Raw -Encoding UTF8 -LiteralPath $vibePromptPath
} else {
  ''
}
Add-TestResult `
  -Area 'Custom themes' `
  -Name 'Vibe Coding prompt preserves the data-only safety contract' `
  -Passed (
    -not [string]::IsNullOrWhiteSpace($vibePromptSource) -and
    $vibePromptSource -match '%LOCALAPPDATA%\\CodexPetDock\\themes' -and
    $vibePromptSource -match 'theme\.json' -and
    $vibePromptSource -match 'platform\.png' -and
    $vibePromptSource -match 'app\.asar' -and
    $vibePromptSource -match 'ThemeSwitchDiagnostics' -and
    $vibePromptSource -match 'Reload custom themes'
  )
try {
  $studioDiagnosticsOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $themeStudioScript `
    -Diagnostics `
    -Language 'en-US' 2>&1
  $studioDiagnosticsExit = $LASTEXITCODE
  $studioDiagnostics = (
    ($studioDiagnosticsOutput -join [Environment]::NewLine) |
      ConvertFrom-Json
  )
  Add-TestResult `
    -Area 'Custom themes' `
    -Name 'Theme Studio contract is data-only and hot-reloadable' `
    -Passed (
      $studioDiagnosticsExit -eq 0 -and
      $studioDiagnostics.ok -and
      [string]$studioDiagnostics.language -eq 'en-US' -and
      @($studioDiagnostics.supportedLanguages).Count -eq 2 -and
      $studioDiagnostics.supportsHotReload -and
      -not $studioDiagnostics.executableFieldsAllowed -and
      [int]$studioDiagnostics.schemaVersion -eq 1
    )

  $studioLayoutOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $themeStudioScript `
    -LayoutDiagnostics `
    -Language 'en-US' 2>&1
  $studioLayoutExit = $LASTEXITCODE
  $studioLayout = (
    ($studioLayoutOutput -join [Environment]::NewLine) |
      ConvertFrom-Json
  )
  Add-TestResult `
    -Area 'Custom themes' `
    -Name 'Theme Studio controls fit inside the 0.3 layout' `
    -Passed (
      $studioLayoutExit -eq 0 -and
      $studioLayout.ok -and
      [string]$studioLayout.language -eq 'en-US' -and
      @($studioLayout.controls).Count -ge 20
    ) `
    -Detail (
      [string]$studioLayout.clientWidth +
      'x' +
      [string]$studioLayout.clientHeight +
      ', controls=' +
      [string]@($studioLayout.controls).Count
    )

  $chineseStudioDiagnosticsOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $themeStudioScript `
    -Diagnostics `
    -Language 'zh-CN' 2>&1
  $chineseStudioDiagnosticsExit = $LASTEXITCODE
  $chineseStudioDiagnostics = (
    ($chineseStudioDiagnosticsOutput -join [Environment]::NewLine) |
      ConvertFrom-Json
  )
  $chineseStudioLayoutOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $themeStudioScript `
    -LayoutDiagnostics `
    -Language 'zh-CN' 2>&1
  $chineseStudioLayoutExit = $LASTEXITCODE
  $chineseStudioLayout = (
    ($chineseStudioLayoutOutput -join [Environment]::NewLine) |
      ConvertFrom-Json
  )
  $badChineseStudioControls = @(
    $chineseStudioLayout.controls |
      Where-Object { -not $_.insideClient -or -not $_.textFits }
  )
  Add-TestResult `
    -Area 'Localization' `
    -Name 'Chinese Theme Studio contract and controls are complete' `
    -Passed (
      $chineseStudioDiagnosticsExit -eq 0 -and
      $chineseStudioDiagnostics.ok -and
      [string]$chineseStudioDiagnostics.language -eq 'zh-CN' -and
      $chineseStudioLayoutExit -eq 0 -and
      $chineseStudioLayout.ok -and
      [string]$chineseStudioLayout.language -eq 'zh-CN' -and
      $badChineseStudioControls.Count -eq 0
    ) `
    -Detail (
      'controls=' +
      [string]@($chineseStudioLayout.controls).Count +
      ', clipped=' +
      [string]$badChineseStudioControls.Count
    )
} catch {
  Add-TestResult `
    -Area 'Custom themes' `
    -Name 'Theme Studio contract is data-only and hot-reloadable' `
    -Passed $false `
    -Detail $_.Exception.Message
}

$installerScript = Join-Path `
  $projectRoot `
  'packaging\Install-CodexPetDock.ps1'
$installerSource = Get-Content `
  -Raw `
  -Encoding UTF8 `
  -LiteralPath $installerScript
Add-TestResult `
  -Area 'Packaging' `
  -Name 'One-click install enables startup without recreating the Run key' `
  -Passed (
    $installerSource -match '\$enableLaunchAtSignIn = ' -and
    $installerSource -match '\[switch\]\$DoNotLaunchAtSignIn' -and
    $installerSource -match 'Test-Path -LiteralPath \$runRegistryPath' -and
    $installerSource -match 'Remove-ItemProperty' -and
    $installerSource -match 'CodexPetDock'
  )
Add-TestResult `
  -Area 'Packaging' `
  -Name 'End users do not need Node or a .NET SDK' `
  -Passed (
    $installerSource -match 'src\\native\\CodexPetProbe\.exe' -and
    $installerSource -notmatch 'Get-Command node' -and
    $installerSource -notmatch 'node --version'
  )
try {
  $installerValidation = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $installerScript `
    -ValidateOnly 2>&1
  $installerValidationExit = $LASTEXITCODE
  Add-TestResult `
    -Area 'Packaging' `
    -Name 'Preview installer preflight succeeds without writing' `
    -Passed ($installerValidationExit -eq 0) `
    -Detail ($installerValidation -join ' ')
} catch {
  Add-TestResult `
    -Area 'Packaging' `
    -Name 'Preview installer preflight succeeds without writing' `
    -Passed $false `
    -Detail $_.Exception.Message
}

$themeDiagnosticState = Join-Path `
  ([System.IO.Path]::GetTempPath()) `
  ('CodexPetDockThemeTest-' + [guid]::NewGuid().ToString('N'))
try {
  [void][System.IO.Directory]::CreateDirectory($themeDiagnosticState)
  $validCustomThemeDirectory = Join-Path `
    $themeDiagnosticState `
    'themes\regression-custom'
  [void][System.IO.Directory]::CreateDirectory(
    $validCustomThemeDirectory
  )
  Copy-Item `
    -LiteralPath (
      Join-Path $projectRoot 'assets\tech-platform-v2.png'
    ) `
    -Destination (
      Join-Path $validCustomThemeDirectory 'platform.png'
    ) `
    -Force
  Copy-Item `
    -LiteralPath (
      Join-Path `
        $projectRoot `
        'tests\fixtures\custom-theme\theme.json'
    ) `
    -Destination (
      Join-Path $validCustomThemeDirectory 'theme.json'
    ) `
    -Force

  $rejectedCustomThemeDirectory = Join-Path `
    $themeDiagnosticState `
    'themes\rejected-script-theme'
  [void][System.IO.Directory]::CreateDirectory(
    $rejectedCustomThemeDirectory
  )
  Copy-Item `
    -LiteralPath (
      Join-Path $projectRoot 'assets\tech-platform-v2.png'
    ) `
    -Destination (
      Join-Path $rejectedCustomThemeDirectory 'platform.png'
    ) `
    -Force
  [ordered]@{
    schemaVersion = 1
    id = 'regression.rejected'
    name = 'Rejected Script Theme'
    asset = 'platform.png'
    width = 224
    height = 72
    contactSurfaceY = 14
    contactOverlap = 7
    contentOffsetY = 0
    contactShadow = $true
    contactShadowY = 14
    compactMetrics = $false
    metricsScrimOpacity = 96
    accent = '#6FE8EF'
    script = 'must-not-be-accepted'
  } |
    ConvertTo-Json |
    Set-Content `
      -LiteralPath (
        Join-Path $rejectedCustomThemeDirectory 'theme.json'
      ) `
      -Encoding UTF8

  $themeSwitchOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $sidecarScript `
    -ThemeSwitchDiagnostics `
    -AllowMultipleInstances `
    -Language 'zh-CN' `
    -ConfigDirectoryOverride $themeDiagnosticState 2>&1
  $themeSwitchExit = $LASTEXITCODE
  $themeSwitchReport = (
    ($themeSwitchOutput -join [Environment]::NewLine) |
      ConvertFrom-Json
  )
  $failedThemeSwitches = @(
    $themeSwitchReport.themes |
      Where-Object {
        -not $_.switched -or
        -not $_.persisted -or
        -not $_.layoutFits -or
        -not $_.controlSizeFits -or
        -not $_.fontFits -or
        [double]$_.alphaCoverage -lt 0.95 -or
        -not $_.contactFits
      }
  )
  $loadedCustomTheme = @(
    $themeSwitchReport.themes |
      Where-Object {
        $_.theme -eq 'regression.custom-base' -and
        $_.switched -and
        $_.persisted
      }
  ).Count -eq 1
  $rejectedScriptTheme = @(
    $themeSwitchReport.themes |
      Where-Object { $_.theme -eq 'regression.rejected' }
  ).Count -eq 0
  Add-TestResult `
    -Area 'Interaction' `
    -Name 'Every theme switches, fits, and persists safely' `
    -Passed (
      $themeSwitchExit -eq 0 -and
      $themeSwitchReport.ok -and
      $failedThemeSwitches.Count -eq 0
    ) `
    -Detail (
      'themes=' +
      [string]@($themeSwitchReport.themes).Count +
      ', failed=' +
      [string]$failedThemeSwitches.Count +
      ', maxBottom=' +
      [string](($themeSwitchReport.themes |
        Measure-Object -Property metricsBottom -Maximum).Maximum) +
      ', minAlpha=' +
       ('{0:P1}' -f (
         $themeSwitchReport.themes |
           Measure-Object -Property alphaCoverage -Minimum
       ).Minimum)
    )
  Add-TestResult `
    -Area 'Custom themes' `
    -Name 'Valid data-only custom theme loads safely' `
    -Passed $loadedCustomTheme `
    -Detail ('themes=' + [string]@($themeSwitchReport.themes).Count)
  Add-TestResult `
    -Area 'Custom themes' `
    -Name 'Custom theme with executable field is rejected' `
    -Passed $rejectedScriptTheme

  $savedLocalizedConfig = Get-Content `
    -Raw `
    -Encoding UTF8 `
    -LiteralPath (Join-Path $themeDiagnosticState 'config.json') |
      ConvertFrom-Json
  $localizedRestartOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $sidecarScript `
    -PanelLayoutDiagnostics `
    -ConfigDirectoryOverride $themeDiagnosticState 2>&1
  $localizedRestartExit = $LASTEXITCODE
  $localizedRestart = (
    ($localizedRestartOutput -join [Environment]::NewLine) |
      ConvertFrom-Json
  )
  Add-TestResult `
    -Area 'Localization' `
    -Name 'Language selection persists without losing the selected theme' `
    -Passed (
      [int]$savedLocalizedConfig.version -eq 2 -and
      [string]$savedLocalizedConfig.language -eq 'zh-CN' -and
      -not [string]::IsNullOrWhiteSpace(
        [string]$savedLocalizedConfig.theme
      ) -and
      $localizedRestartExit -eq 0 -and
      $localizedRestart.ok -and
      [string]$localizedRestart.language -eq 'zh-CN'
    ) `
    -Detail (
      'language=' +
      [string]$savedLocalizedConfig.language +
      ', theme=' +
      [string]$savedLocalizedConfig.theme
    )
} catch {
  Add-TestResult `
    -Area 'Interaction' `
    -Name 'Every theme switches, fits, and persists safely' `
    -Passed $false `
    -Detail $_.Exception.Message
} finally {
  $resolvedThemeDiagnosticState = [System.IO.Path]::GetFullPath(
    $themeDiagnosticState
  )
  $resolvedTempRoot = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::GetTempPath()
  )
  if ($resolvedThemeDiagnosticState.StartsWith(
    $resolvedTempRoot,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    Remove-Item `
      -LiteralPath $resolvedThemeDiagnosticState `
      -Recurse `
      -Force `
      -ErrorAction SilentlyContinue
  }
}

$themes = @(
  'holo-cyan',
  'holo-amber',
  'circuit-flat',
  'princess-cradle',
  'forest-rune',
  'clockwork-brass',
  'moon-lotus',
  'sakura-shrine',
  'iron-throne'
)
$diagnostics = $null
foreach ($theme in $themes) {
  try {
    $themeDiagnostics = Invoke-Diagnostics -Theme $theme
    if ($null -eq $diagnostics) {
      $diagnostics = $themeDiagnostics
    }
    Add-TestResult `
      -Area 'Diagnostics' `
      -Name ($theme + ' selects correctly') `
      -Passed (
        $themeDiagnostics.ok -and
        [string]$themeDiagnostics.selectedTheme -eq $theme
      ) `
      -Detail (
        'pet=' +
        [string]($null -ne $themeDiagnostics.petMascotBounds) +
        ', buckets=' +
        [string]@($themeDiagnostics.quota.buckets).Count
      )
  } catch {
    Add-TestResult `
      -Area 'Diagnostics' `
      -Name ($theme + ' selects correctly') `
      -Passed $false `
      -Detail $_.Exception.Message
  }
}

$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $invalidOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $sidecarScript `
    -Diagnostics `
    -Theme 'not-a-theme' 2>&1
  $invalidExit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $savedErrorActionPreference
}
Add-TestResult `
  -Area 'Validation' `
  -Name 'Unknown theme is rejected' `
  -Passed (
    $invalidExit -ne 0 -and
    (($invalidOutput -join ' ') -match 'Unknown theme')
  ) `
  -Detail ('exit=' + [string]$invalidExit)

if ($null -ne $diagnostics) {
  $probeCachePath = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    (
      'codex-pet-dock-regression-' +
      [guid]::NewGuid().ToString('N') +
      '.json'
    )
  try {
      $probeOutput = & $probeScript `
        --codex ([string]$diagnostics.codexExecutable) `
        --token-cache $probeCachePath 2>&1
      $probeExit = $LASTEXITCODE
      $probeText = $probeOutput -join [Environment]::NewLine
      $probe = $probeText | ConvertFrom-Json
      Add-TestResult `
        -Area 'Data' `
        -Name 'Official app-server probe succeeds' `
        -Passed ($probeExit -eq 0 -and $null -ne $probe.capturedAt) `
        -Detail ('buckets=' + [string]@($probe.buckets).Count)

      $tokenStats = $probe.tokenStats
      $tokenMathOk = (
        [long]$tokenStats.weeklyTokens -ge 0 -and
        [long]$tokenStats.inputTokens -ge [long]$tokenStats.cachedInputTokens -and
        [long]$tokenStats.freshInputTokens -eq (
          [long]$tokenStats.inputTokens -
          [long]$tokenStats.cachedInputTokens
        )
      )
      Add-TestResult `
        -Area 'Data' `
        -Name 'Weekly Token arithmetic is consistent' `
        -Passed $tokenMathOk `
        -Detail (
          'weekly=' +
          [string]$tokenStats.weeklyTokens +
          ', cached=' +
          [string]$tokenStats.cachedPercent +
          '%'
        )

      $privacyOk = $probeText -notmatch (
        '(?i)"(email|accessToken|refreshToken|idToken|authJson|messageText)"\s*:'
      )
      Add-TestResult `
        -Area 'Privacy' `
        -Name 'Probe output excludes credential and message fields' `
        -Passed $privacyOk

      $cachedProbeOutput = & $probeScript `
        --codex ([string]$diagnostics.codexExecutable) `
        --token-cache $probeCachePath 2>&1
      $cachedProbeExit = $LASTEXITCODE
      $cachedProbeText = (
        $cachedProbeOutput -join [Environment]::NewLine
      )
      $cachedProbe = $cachedProbeText | ConvertFrom-Json
      $cachePreservesTotals = (
        $cachedProbeExit -eq 0 -and
        [long]$cachedProbe.tokenStats.weeklyTokens -ge
          [long]$tokenStats.weeklyTokens -and
        [int]$cachedProbe.tokenStats.filesParsed -le 2 -and
        [int]$cachedProbe.tokenStats.cacheHits -ge
          (
            [int]$cachedProbe.tokenStats.scannedSessions -
            [int]$cachedProbe.tokenStats.filesParsed
          )
      )
      Add-TestResult `
        -Area 'Data' `
        -Name 'Warm Token cache reuses unchanged sessions' `
        -Passed $cachePreservesTotals `
        -Detail (
          'hits=' +
          [string]$cachedProbe.tokenStats.cacheHits +
          ', parsed=' +
          [string]$cachedProbe.tokenStats.filesParsed
        )

      $cacheText = [System.IO.File]::ReadAllText(
        $probeCachePath,
        [System.Text.Encoding]::UTF8
      )
      $cachePrivacyOk = $cacheText -notmatch (
        '(?i)([\\/]+sessions[\\/]+|\.jsonl|' +
        'accessToken|refreshToken|authJson|messageText|email)'
      )
      Add-TestResult `
        -Area 'Privacy' `
        -Name 'Token cache contains hashes and numeric aggregates only' `
        -Passed $cachePrivacyOk
  } catch {
      Add-TestResult `
        -Area 'Data' `
        -Name 'Official app-server probe succeeds' `
        -Passed $false `
        -Detail $_.Exception.Message
  } finally {
      if ([System.IO.File]::Exists($probeCachePath)) {
        [System.IO.File]::Delete($probeCachePath)
      }
  }
}

foreach ($theme in $themes) {
  $runtimeOutput = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $sidecarScript `
    -Theme $theme `
    -AllowMultipleInstances `
    -RunSeconds 2 2>&1
  $runtimeExit = $LASTEXITCODE
  Add-TestResult `
    -Area 'Runtime' `
    -Name ($theme + ' starts and exits cleanly') `
    -Passed ($runtimeExit -eq 0) `
    -Detail (
      'exit=' +
      [string]$runtimeExit +
      $(if ($runtimeExit -ne 0) { ', ' + ($runtimeOutput -join ' ') } else { '' })
    )
}

if (-not $SkipIntegration -and $null -ne $diagnostics.petWindow) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class CodexPetDockTestNative
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr data);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags
    );

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint command);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(
        IntPtr hWnd,
        uint message,
        IntPtr wParam,
        IntPtr lParam
    );

    public static List<IntPtr> VisibleWindowsForProcess(uint wanted)
    {
        var windows = new List<IntPtr>();
        EnumWindows((hWnd, data) => {
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            if (processId == wanted && IsWindowVisible(hWnd))
            {
                windows.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        return windows;
    }
}
'@
  try {
    [void][CodexPetDockTestNative]::SetProcessDpiAwarenessContext(
      [IntPtr](-4)
    )
  } catch {
  }

  $petHandle = [IntPtr]([long]$diagnostics.petWindow.Handle)
  $originalPetRect = New-Object CodexPetDockTestNative+RECT
  [void][CodexPetDockTestNative]::GetWindowRect(
    $petHandle,
    [ref]$originalPetRect
  )
  $originalPetVisible = [CodexPetDockTestNative]::IsWindowVisible($petHandle)
  $integrationProcess = $null
  try {
    $integrationProcess = Start-Process `
      -FilePath 'powershell.exe' `
      -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'RemoteSigned',
        '-File',
        $sidecarScript,
        '-Theme',
        'holo-cyan',
        '-AllowMultipleInstances',
        '-RunSeconds',
        '120'
      ) `
      -WindowStyle Hidden `
      -PassThru

    $visibleBefore = @()
    for ($attempt = 0; $attempt -lt 24 -and $visibleBefore.Count -eq 0; $attempt++) {
      Start-Sleep -Milliseconds 250
      $visibleBefore = @(
        [CodexPetDockTestNative]::VisibleWindowsForProcess(
          [uint32]$integrationProcess.Id
        )
      )
    }
    Add-TestResult `
      -Area 'Integration' `
      -Name 'Dock appears for a visible pet' `
      -Passed ($visibleBefore.Count -eq 1) `
      -Detail ('windows=' + [string]$visibleBefore.Count)

    if ($visibleBefore.Count -gt 0) {
      $baseHandleBefore = [IntPtr]$visibleBefore[0]
      $baseRectBefore = New-Object CodexPetDockTestNative+RECT
      [void][CodexPetDockTestNative]::GetWindowRect(
        $baseHandleBefore,
        [ref]$baseRectBefore
      )

      $childHandle = [CodexPetDockTestNative]::GetWindow(
        $baseHandleBefore,
        5
      )
      if ($childHandle -eq [IntPtr]::Zero) {
        $childHandle = $baseHandleBefore
      }
      $clickPoint = [IntPtr]((55 -shl 16) -bor 112)
      [void][CodexPetDockTestNative]::SendMessage(
        $childHandle,
        0x0201,
        [IntPtr]1,
        $clickPoint
      )
      [void][CodexPetDockTestNative]::SendMessage(
        $childHandle,
        0x0202,
        [IntPtr]::Zero,
        $clickPoint
      )
      $afterClick = @()
      for (
        $attempt = 0;
        $attempt -lt 8 -and $afterClick.Count -lt 2;
        $attempt++
      ) {
        Start-Sleep -Milliseconds 250
        $afterClick = @(
          [CodexPetDockTestNative]::VisibleWindowsForProcess(
            [uint32]$integrationProcess.Id
          )
        )
      }
      Add-TestResult `
        -Area 'Interaction' `
        -Name 'Clicking Dock opens the detail panel' `
        -Passed ($afterClick.Count -eq 2) `
        -Detail ('windows=' + [string]$afterClick.Count)

      [void][CodexPetDockTestNative]::ShowWindow($petHandle, 0)
      $visibleWhileHidden = $afterClick
      for (
        $attempt = 0;
        $attempt -lt 8 -and $visibleWhileHidden.Count -gt 0;
        $attempt++
      ) {
        Start-Sleep -Milliseconds 250
        $visibleWhileHidden = @(
          [CodexPetDockTestNative]::VisibleWindowsForProcess(
            [uint32]$integrationProcess.Id
          )
        )
      }
      Add-TestResult `
        -Area 'Integration' `
        -Name 'Hiding the pet hides Dock without a dialog' `
        -Passed (
          -not $integrationProcess.HasExited -and
          $visibleWhileHidden.Count -eq 0
        ) `
        -Detail (
          'processAlive=' +
          [string](-not $integrationProcess.HasExited) +
          ', windows=' +
          [string]$visibleWhileHidden.Count
        )

      $hiddenSampleProcess = Get-Process -Id $integrationProcess.Id
      $hiddenCpuStart = $hiddenSampleProcess.TotalProcessorTime.TotalSeconds
      Start-Sleep -Seconds 3
      $hiddenSampleProcess.Refresh()
      $hiddenCpuDelta = (
        $hiddenSampleProcess.TotalProcessorTime.TotalSeconds -
        $hiddenCpuStart
      )
      $hiddenCpuPercent = (
        $hiddenCpuDelta /
        (3 * [Environment]::ProcessorCount) *
        100
      )
      Add-TestResult `
        -Area 'Performance' `
        -Name 'Hidden-pet waiting CPU stays below 2%' `
        -Passed ($hiddenCpuPercent -lt 2) `
        -Detail (
          (
            'cpu={0:0.00}%, workingSet={1:0.0}MB' -f `
              $hiddenCpuPercent, `
              ($hiddenSampleProcess.WorkingSet64 / 1MB)
          )
        )

      try {
        $probeChildren = @(
          Get-CimInstance `
            -ClassName Win32_Process `
            -Filter (
              'ParentProcessId = ' +
              [string]$integrationProcess.Id +
              " AND Name = 'CodexPetProbe.exe'"
            )
        )
        Add-TestResult `
          -Area 'Performance' `
          -Name 'Hidden pet has no quota probe process' `
          -Passed ($probeChildren.Count -eq 0) `
          -Detail ('nativeProbeChildren=' + [string]$probeChildren.Count)
      } catch {
        Add-TestResult `
          -Area 'Performance' `
          -Name 'Hidden pet has no quota probe process' `
          -Passed $false `
          -Detail $_.Exception.Message
      }

      [void][CodexPetDockTestNative]::ShowWindow($petHandle, 5)
      $visibleAfterRestore = @()
      for (
        $attempt = 0;
        $attempt -lt 20 -and $visibleAfterRestore.Count -eq 0;
        $attempt++
      ) {
        Start-Sleep -Milliseconds 250
        $visibleAfterRestore = @(
          [CodexPetDockTestNative]::VisibleWindowsForProcess(
            [uint32]$integrationProcess.Id
          )
        )
      }
      Add-TestResult `
        -Area 'Integration' `
        -Name 'Restoring the pet restores Dock' `
        -Passed ($visibleAfterRestore.Count -eq 1) `
        -Detail ('windows=' + [string]$visibleAfterRestore.Count)

      if ($visibleAfterRestore.Count -gt 0) {
        $restoredBaseHandle = [IntPtr]$visibleAfterRestore[0]
        $restoredBaseRect = New-Object CodexPetDockTestNative+RECT
        [void][CodexPetDockTestNative]::GetWindowRect(
          $restoredBaseHandle,
          [ref]$restoredBaseRect
        )
        $liveDiagnostics = Invoke-Diagnostics -Theme 'holo-cyan'
        $mascot = $liveDiagnostics.petMascotBounds
        $baseCenterX = (
          $restoredBaseRect.Left +
          (($restoredBaseRect.Right - $restoredBaseRect.Left) / 2)
        )
        $mascotCenterX = (
          [double]$mascot.Left +
          ([double]$mascot.Width / 2)
        )
        $centerDelta = [math]::Abs($baseCenterX - $mascotCenterX)
        Add-TestResult `
          -Area 'Integration' `
          -Name 'Dock remains centered under the active pet' `
          -Passed ($null -ne $mascot -and $centerDelta -le 8) `
          -Detail ('centerDelta=' + ('{0:0.0}px' -f $centerDelta))
      }

      $sampleProcess = Get-Process -Id $integrationProcess.Id
      $cpuStart = $sampleProcess.TotalProcessorTime.TotalSeconds
      Start-Sleep -Seconds 3
      $sampleProcess.Refresh()
      $cpuDelta = (
        $sampleProcess.TotalProcessorTime.TotalSeconds -
        $cpuStart
      )
      $cpuPercent = (
        $cpuDelta /
        (3 * [Environment]::ProcessorCount) *
        100
      )
      $memoryMb = $sampleProcess.WorkingSet64 / 1MB
      Add-TestResult `
        -Area 'Performance' `
        -Name 'Idle CPU stays below 5%' `
        -Passed ($cpuPercent -lt 5) `
        -Detail (
          ('cpu={0:0.00}%, workingSet={1:0.0}MB' -f $cpuPercent, $memoryMb)
        )
    }
  } catch {
    Add-TestResult `
      -Area 'Integration' `
      -Name 'Integration harness completes' `
      -Passed $false `
      -Detail $_.Exception.Message
  } finally {
    if (
      $null -ne $integrationProcess -and
      -not $integrationProcess.HasExited
    ) {
      Stop-Process -Id $integrationProcess.Id -Force
    }
    if ($originalPetVisible) {
      [void][CodexPetDockTestNative]::ShowWindow($petHandle, 5)
    }
    [void][CodexPetDockTestNative]::SetWindowPos(
      $petHandle,
      [IntPtr]::Zero,
      $originalPetRect.Left,
      $originalPetRect.Top,
      0,
      0,
      0x0015
    )
  }
}

$results | Format-Table -AutoSize -Wrap
Write-Host ''
Write-Host (
  'Summary: ' +
  [string]($results.Count - $failures) +
  ' passed, ' +
  [string]$failures +
  ' failed, ' +
  [string]$results.Count +
  ' total.'
)

if ($failures -gt 0) {
  exit 1
}
exit 0
