[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stopScript = Join-Path $projectRoot 'packaging\Stop-CodexPetDock.ps1'
$installerDefinition = Join-Path `
  $projectRoot `
  'packaging\windows\CodexPetDock.iss'
$failures = New-Object System.Collections.Generic.List[string]

function Add-Assertion {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ($Condition) {
    Write-Host ('PASS: ' + $Message)
  } else {
    $script:failures.Add($Message)
    Write-Host ('FAIL: ' + $Message)
  }
}

foreach ($validPath in @(
  'D:\CodexPetDock',
  'C:\Apps\CodexPetDock',
  (Join-Path `
    ([Environment]::GetFolderPath('LocalApplicationData')) `
    'Programs\CodexPetDock')
)) {
  $output = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $stopScript `
    -InstallRoot $validPath `
    -ValidateOnly 2>&1
  Add-Assertion `
    -Condition ($LASTEXITCODE -eq 0) `
    -Message ('Accepts safe local install path: ' + $validPath)
}

foreach ($invalidPath in @(
  'D:\',
  'relative\CodexPetDock',
  '\\server\share\CodexPetDock'
)) {
  $previousErrorPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $stopScript `
    -InstallRoot $invalidPath `
    -ValidateOnly 2>&1
  $validationExitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorPreference
  Add-Assertion `
    -Condition ($validationExitCode -ne 0) `
    -Message ('Rejects unsafe install path: ' + $invalidPath)
}

$testRoot = Join-Path `
  ([System.IO.Path]::GetTempPath()) `
  ('CodexPetDockStopTest-' + [guid]::NewGuid().ToString('N'))
$otherRoot = $testRoot + '-unrelated'
$managedProcess = $null
$unrelatedProcess = $null
try {
  $managedScript = Join-Path $testRoot 'src\Start-CodexPetQuota.ps1'
  $unrelatedScript = Join-Path $otherRoot 'src\Start-CodexPetQuota.ps1'
  [void][System.IO.Directory]::CreateDirectory(
    (Split-Path -Parent $managedScript)
  )
  [void][System.IO.Directory]::CreateDirectory(
    (Split-Path -Parent $unrelatedScript)
  )
  Set-Content `
    -LiteralPath $managedScript `
    -Encoding ASCII `
    -Value 'Start-Sleep -Seconds 60'
  Set-Content `
    -LiteralPath $unrelatedScript `
    -Encoding ASCII `
    -Value 'Start-Sleep -Seconds 60'

  $managedProcess = Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList @(
      '-NoProfile',
      '-ExecutionPolicy',
      'RemoteSigned',
      '-File',
      ('"' + $managedScript + '"')
    ) `
    -WindowStyle Hidden `
    -PassThru
  $unrelatedProcess = Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList @(
      '-NoProfile',
      '-ExecutionPolicy',
      'RemoteSigned',
      '-File',
      ('"' + $unrelatedScript + '"')
    ) `
    -WindowStyle Hidden `
    -PassThru
  Start-Sleep -Milliseconds 500

  & powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File $stopScript `
    -InstallRoot $testRoot `
    -SelectedRootOnly
  $stopExitCode = $LASTEXITCODE
  $managedProcess.Refresh()
  $unrelatedProcess.Refresh()
  Add-Assertion `
    -Condition ($stopExitCode -eq 0 -and $managedProcess.HasExited) `
    -Message 'Stops a Pet Dock process from the selected install directory'
  Add-Assertion `
    -Condition (-not $unrelatedProcess.HasExited) `
    -Message 'Does not stop the same script name outside the selected directory'
} finally {
  foreach ($process in @($managedProcess, $unrelatedProcess)) {
    if ($null -ne $process) {
      try {
        $process.Refresh()
        if (-not $process.HasExited) {
          Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
      } catch {
        # The process may already have exited between Refresh and cleanup.
      }
      $process.Dispose()
    }
  }
  Remove-Item `
    -LiteralPath $testRoot, $otherRoot `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue
}

$installerSource = Get-Content `
  -LiteralPath $installerDefinition `
  -Encoding UTF8 `
  -Raw
Add-Assertion `
  -Condition ($installerSource -match 'function IsUnsafeInstallPath') `
  -Message 'Installer validates custom install directories'
Add-Assertion `
  -Condition (
    $installerSource -notmatch
      'Type:\s*filesandordirs;\s*Name:\s*"\{app\}\\\*"'
  ) `
  -Message 'Upgrade never recursively clears the selected install directory'

$stopScriptSource = Get-Content `
  -LiteralPath $stopScript `
  -Encoding UTF8 `
  -Raw
Add-Assertion `
  -Condition (
    $stopScriptSource -match
      '\{5C836C8E-D328-4A2D-A271-30FBB9D39D01\}_is1' -and
    $stopScriptSource -match "'Programs\\CodexPetDock'"
  ) `
  -Message 'Drive migration also stops the registered and legacy install roots'

if ($failures.Count -gt 0) {
  throw (
    [string]$failures.Count +
    ' installer path regression test(s) failed: ' +
    ($failures -join '; ')
  )
}

Write-Host 'Installer path regression PASS.'
