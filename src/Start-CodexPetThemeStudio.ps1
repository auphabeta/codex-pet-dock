[CmdletBinding()]
param(
  [string]$ConfigDirectoryOverride = '',
  [switch]$Diagnostics,
  [switch]$LayoutDiagnostics
)

$ErrorActionPreference = 'Stop'
$configDirectory = if (
  [string]::IsNullOrWhiteSpace($ConfigDirectoryOverride)
) {
  Join-Path $env:LOCALAPPDATA 'CodexPetDock'
} else {
  [System.IO.Path]::GetFullPath($ConfigDirectoryOverride)
}
$customThemesDirectory = Join-Path $configDirectory 'themes'
$manifestFields = @(
  'schemaVersion',
  'id',
  'name',
  'asset',
  'width',
  'height',
  'contactSurfaceY',
  'contactOverlap',
  'contentOffsetY',
  'contactShadow',
  'contactShadowY',
  'compactMetrics',
  'metricsScrimOpacity',
  'accent'
)

if ($Diagnostics) {
  [pscustomobject]@{
    ok = $true
    editorVersion = 1
    schemaVersion = 1
    customThemeRoot = $customThemesDirectory
    manifestFields = $manifestFields
    supportsHotReload = $true
    executableFieldsAllowed = $false
  } | ConvertTo-Json -Depth 3
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies @(
  'System.Windows.Forms',
  'System.Drawing'
) -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

namespace CodexPetDockStudio
{
    public sealed class ThemePreview : Control
    {
        private Image texture;
        public Image Texture
        {
            get { return texture; }
            set { texture = value; Invalidate(); }
        }

        public int RuntimeWidth { get; set; }
        public int RuntimeHeight { get; set; }
        public int ContactSurfaceY { get; set; }
        public int ContactOverlap { get; set; }
        public int ContentOffsetY { get; set; }
        public int MetricsScrimOpacity { get; set; }
        public bool CompactMetrics { get; set; }
        public Color Accent { get; set; }

        public ThemePreview()
        {
            DoubleBuffered = true;
            BackColor = Color.FromArgb(14, 17, 22);
            ForeColor = Color.White;
            RuntimeWidth = 224;
            RuntimeHeight = 72;
            ContactSurfaceY = 20;
            ContactOverlap = 7;
            ContentOffsetY = 0;
            MetricsScrimOpacity = 120;
            CompactMetrics = false;
            Accent = Color.FromArgb(111, 232, 239);
        }

        private static GraphicsPath RoundRect(RectangleF rect, float radius)
        {
            float diameter = radius * 2f;
            GraphicsPath path = new GraphicsPath();
            path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(BackColor);

            float scale = Math.Min(
                (Width - 56f) / Math.Max(1, RuntimeWidth),
                (Height - 190f) / Math.Max(1, RuntimeHeight)
            );
            scale = Math.Max(1.4f, Math.Min(2.7f, scale));
            float baseWidth = RuntimeWidth * scale;
            float baseHeight = RuntimeHeight * scale;
            float baseX = (Width - baseWidth) / 2f;
            float baseY = Height - baseHeight - 48f;
            RectangleF baseRect = new RectangleF(baseX, baseY, baseWidth, baseHeight);

            using (LinearGradientBrush glow = new LinearGradientBrush(
                new PointF(0, baseY - 80f),
                new PointF(0, baseY + baseHeight),
                Color.FromArgb(0, Accent),
                Color.FromArgb(52, Accent)
            ))
            {
                g.FillEllipse(glow, baseX + baseWidth * .16f, baseY - 42f, baseWidth * .68f, 94f);
            }

            if (texture != null)
            {
                g.DrawImage(texture, baseRect);
            }
            else
            {
                using (GraphicsPath placeholder = RoundRect(baseRect, 18f))
                using (Brush fill = new SolidBrush(Color.FromArgb(24, 34, 49)))
                using (Pen rim = new Pen(Color.FromArgb(100, Accent), 1.5f))
                {
                    g.FillPath(fill, placeholder);
                    g.DrawPath(rim, placeholder);
                }
            }

            float metricTop = baseY + (34 + ContentOffsetY) * scale;
            float metricHeight = (CompactMetrics ? 28 : 32) * scale;
            RectangleF scrim = new RectangleF(
                baseX + 11f * scale,
                metricTop - 2f * scale,
                baseWidth - 22f * scale,
                metricHeight
            );
            using (GraphicsPath scrimPath = RoundRect(scrim, 8f * scale))
            using (Brush scrimBrush = new SolidBrush(
                Color.FromArgb(Math.Max(0, Math.Min(220, MetricsScrimOpacity)), 5, 10, 19)
            ))
            {
                g.FillPath(scrimBrush, scrimPath);
            }

            float half = baseWidth / 2f;
            using (Pen divider = new Pen(Color.FromArgb(70, 155, 190, 222), 1f))
            {
                g.DrawLine(
                    divider,
                    baseX + half,
                    metricTop,
                    baseX + half,
                    metricTop + metricHeight - 2f * scale
                );
            }

            StringFormat center = new StringFormat {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center
            };
            using (Font micro = new Font(
                "Segoe UI Semibold",
                Math.Max(8f, 9f * scale),
                FontStyle.Regular,
                GraphicsUnit.Pixel
            ))
            using (Font value = new Font(
                "Bahnschrift SemiBold",
                Math.Max(14f, (CompactMetrics ? 14f : 17f) * scale),
                FontStyle.Regular,
                GraphicsUnit.Pixel
            ))
            using (Brush muted = new SolidBrush(Color.FromArgb(210, 190, 222, 238)))
            using (Brush text = new SolidBrush(Color.FromArgb(248, 249, 253)))
            {
                RectangleF leftTitle = new RectangleF(baseX, metricTop, half, 10f * scale);
                RectangleF rightTitle = new RectangleF(baseX + half, metricTop, half, 10f * scale);
                RectangleF leftValue = new RectangleF(baseX, metricTop + 8f * scale, half, 22f * scale);
                RectangleF rightValue = new RectangleF(baseX + half, metricTop + 8f * scale, half, 22f * scale);
                g.DrawString("WEEK LEFT", micro, muted, leftTitle, center);
                g.DrawString("WEEK TOKENS", micro, muted, rightTitle, center);
                g.DrawString("85%", value, text, leftValue, center);
                g.DrawString("525M", value, text, rightValue, center);
            }

            float contactY = baseY + ContactSurfaceY * scale;
            float petBottom = baseY + (ContactSurfaceY + ContactOverlap) * scale;
            float petWidth = 74f * scale;
            float petHeight = 92f * scale;
            RectangleF body = new RectangleF(
                baseX + baseWidth / 2f - petWidth / 2f,
                petBottom - petHeight,
                petWidth,
                petHeight
            );
            using (GraphicsPath bodyPath = RoundRect(body, 20f * scale))
            using (LinearGradientBrush petBrush = new LinearGradientBrush(
                body,
                Color.FromArgb(224, 83, 139, 255),
                Color.FromArgb(230, 31, 68, 157),
                90f
            ))
            using (Pen petRim = new Pen(Color.FromArgb(190, 123, 214, 255), 1.5f * scale))
            {
                g.FillPath(petBrush, bodyPath);
                g.DrawPath(petRim, bodyPath);
            }
            RectangleF face = new RectangleF(
                body.Left + 10f * scale,
                body.Top + 18f * scale,
                body.Width - 20f * scale,
                34f * scale
            );
            using (GraphicsPath facePath = RoundRect(face, 8f * scale))
            using (Brush faceBrush = new SolidBrush(Color.FromArgb(235, 12, 27, 57)))
            {
                g.FillPath(faceBrush, facePath);
            }
            using (Pen contactPen = new Pen(Color.FromArgb(210, Accent), 1.5f))
            {
                contactPen.DashStyle = DashStyle.Dash;
                g.DrawLine(contactPen, baseX, contactY, baseX + baseWidth, contactY);
            }

            using (Font hint = new Font("Segoe UI", 9f, FontStyle.Regular))
            using (Brush hintBrush = new SolidBrush(Color.FromArgb(145, 158, 178)))
            {
                g.DrawString(
                    "Dashed line = visible contact surface - exact runtime geometry",
                    hint,
                    hintBrush,
                    new PointF(22f, Height - 28f)
                );
            }
        }
    }
}
'@

function Get-UnlockedBitmap {
  param([Parameter(Mandatory = $true)][string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $stream = [System.IO.MemoryStream]::new($bytes, $false)
  try {
    $image = [System.Drawing.Image]::FromStream($stream)
    try {
      return New-Object System.Drawing.Bitmap $image
    } finally {
      $image.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function New-DarkLabel {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][int]$X,
    [Parameter(Mandatory = $true)][int]$Y,
    [int]$Width = 150
  )
  $label = New-Object System.Windows.Forms.Label
  $label.Text = $Text
  $label.Location = New-Object System.Drawing.Point $X, $Y
  $label.Size = New-Object System.Drawing.Size $Width, 20
  $label.ForeColor = [System.Drawing.Color]::FromArgb(177, 189, 207)
  $label.Font = New-Object System.Drawing.Font 'Segoe UI Semibold', 8.5
  return $label
}

function New-DarkTextBox {
  param(
    [Parameter(Mandatory = $true)][int]$X,
    [Parameter(Mandatory = $true)][int]$Y,
    [int]$Width = 270
  )
  $box = New-Object System.Windows.Forms.TextBox
  $box.Location = New-Object System.Drawing.Point $X, $Y
  $box.Size = New-Object System.Drawing.Size $Width, 26
  $box.BackColor = [System.Drawing.Color]::FromArgb(27, 33, 44)
  $box.ForeColor = [System.Drawing.Color]::FromArgb(241, 245, 252)
  $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  return $box
}

function New-DarkNumeric {
  param(
    [Parameter(Mandatory = $true)][int]$X,
    [Parameter(Mandatory = $true)][int]$Y,
    [Parameter(Mandatory = $true)][int]$Minimum,
    [Parameter(Mandatory = $true)][int]$Maximum,
    [Parameter(Mandatory = $true)][int]$Value
  )
  $numeric = New-Object System.Windows.Forms.NumericUpDown
  $numeric.Location = New-Object System.Drawing.Point $X, $Y
  $numeric.Size = New-Object System.Drawing.Size 82, 24
  $numeric.Minimum = $Minimum
  $numeric.Maximum = $Maximum
  $numeric.Value = $Value
  $numeric.BackColor = [System.Drawing.Color]::FromArgb(27, 33, 44)
  $numeric.ForeColor = [System.Drawing.Color]::FromArgb(241, 245, 252)
  return $numeric
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[void][System.IO.Directory]::CreateDirectory($customThemesDirectory)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Codex Pet Dock - Theme Studio'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.ClientSize = New-Object System.Drawing.Size 980, 650
$form.MinimumSize = New-Object System.Drawing.Size 996, 689
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 18, 24)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font 'Segoe UI', 9
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$projectRoot = Split-Path -Parent $PSScriptRoot
$iconPath = Join-Path $projectRoot 'assets\branding\codex-pet-dock.ico'
if (Test-Path -LiteralPath $iconPath) {
  $form.Icon = New-Object System.Drawing.Icon $iconPath
}

$title = New-Object System.Windows.Forms.Label
$title.Text = 'CUSTOM BASE STUDIO'
$title.Location = New-Object System.Drawing.Point 24, 18
$title.Size = New-Object System.Drawing.Size 600, 32
$title.Font = New-Object System.Drawing.Font 'Segoe UI Semibold', 17
$title.ForeColor = [System.Drawing.Color]::FromArgb(241, 247, 255)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Drop in a transparent PNG, align the contact surface, then save. No code is allowed.'
$subtitle.Location = New-Object System.Drawing.Point 26, 51
$subtitle.Size = New-Object System.Drawing.Size 720, 24
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(142, 158, 181)
$form.Controls.Add($subtitle)

$preview = New-Object CodexPetDockStudio.ThemePreview
$preview.Location = New-Object System.Drawing.Point 24, 86
$preview.Size = New-Object System.Drawing.Size 620, 500
$preview.Anchor = (
  [System.Windows.Forms.AnchorStyles]::Top -bor
  [System.Windows.Forms.AnchorStyles]::Bottom -bor
  [System.Windows.Forms.AnchorStyles]::Left -bor
  [System.Windows.Forms.AnchorStyles]::Right
)
$form.Controls.Add($preview)

$rightX = 676
$form.Controls.Add((New-DarkLabel -Text 'Theme name' -X $rightX -Y 88))
$nameBox = New-DarkTextBox -X $rightX -Y 109 -Width 274
$nameBox.Text = 'My Custom Base'
$form.Controls.Add($nameBox)

$form.Controls.Add((New-DarkLabel -Text 'Stable theme ID' -X $rightX -Y 143))
$idBox = New-DarkTextBox -X $rightX -Y 164 -Width 274
$idBox.Text = 'your-name.custom-base'
$form.Controls.Add($idBox)

$form.Controls.Add((New-DarkLabel -Text 'Transparent PNG' -X $rightX -Y 198))
$imageBox = New-DarkTextBox -X $rightX -Y 219 -Width 205
$imageBox.ReadOnly = $true
$form.Controls.Add($imageBox)
$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse'
$browseButton.Location = New-Object System.Drawing.Point 888, 217
$browseButton.Size = New-Object System.Drawing.Size 62, 28
$form.Controls.Add($browseButton)

$form.Controls.Add((New-DarkLabel -Text 'Runtime size' -X $rightX -Y 259))
$widthNumeric = New-DarkNumeric -X $rightX -Y 280 -Minimum 160 -Maximum 320 -Value 224
$heightNumeric = New-DarkNumeric -X ($rightX + 94) -Y 280 -Minimum 48 -Maximum 140 -Value 72
$form.Controls.Add($widthNumeric)
$form.Controls.Add($heightNumeric)
$sizeHint = New-DarkLabel -Text 'W x H' -X ($rightX + 184) -Y 283 -Width 70
$form.Controls.Add($sizeHint)

$form.Controls.Add((New-DarkLabel -Text 'Contact surface / overlap' -X $rightX -Y 317 -Width 220))
$surfaceNumeric = New-DarkNumeric -X $rightX -Y 338 -Minimum 0 -Maximum 64 -Value 20
$overlapNumeric = New-DarkNumeric -X ($rightX + 94) -Y 338 -Minimum 0 -Maximum 16 -Value 7
$form.Controls.Add($surfaceNumeric)
$form.Controls.Add($overlapNumeric)

$form.Controls.Add((New-DarkLabel -Text 'Metrics offset / scrim' -X $rightX -Y 375 -Width 220))
$offsetNumeric = New-DarkNumeric -X $rightX -Y 396 -Minimum -12 -Maximum 80 -Value 0
$scrimNumeric = New-DarkNumeric -X ($rightX + 94) -Y 396 -Minimum 0 -Maximum 220 -Value 120
$form.Controls.Add($offsetNumeric)
$form.Controls.Add($scrimNumeric)

$compactCheck = New-Object System.Windows.Forms.CheckBox
$compactCheck.Text = 'Compact metric values'
$compactCheck.Location = New-Object System.Drawing.Point $rightX, 435
$compactCheck.Size = New-Object System.Drawing.Size 190, 24
$compactCheck.ForeColor = [System.Drawing.Color]::FromArgb(205, 216, 232)
$form.Controls.Add($compactCheck)

$accentButton = New-Object System.Windows.Forms.Button
$accentButton.Text = 'Accent  #6FE8EF'
$accentButton.Location = New-Object System.Drawing.Point $rightX, 470
$accentButton.Size = New-Object System.Drawing.Size 178, 30
$accentButton.BackColor = [System.Drawing.Color]::FromArgb(32, 48, 58)
$accentButton.ForeColor = [System.Drawing.Color]::FromArgb(207, 249, 253)
$form.Controls.Add($accentButton)
$script:accentColor = [System.Drawing.Color]::FromArgb(111, 232, 239)

$openButton = New-Object System.Windows.Forms.Button
$openButton.Text = 'Open existing'
$openButton.Location = New-Object System.Drawing.Point $rightX, 526
$openButton.Size = New-Object System.Drawing.Size 112, 34
$form.Controls.Add($openButton)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = 'Save & reload'
$saveButton.Location = New-Object System.Drawing.Point ($rightX + 122), 526
$saveButton.Size = New-Object System.Drawing.Size 152, 34
$saveButton.BackColor = [System.Drawing.Color]::FromArgb(49, 100, 214)
$saveButton.ForeColor = [System.Drawing.Color]::White
$saveButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($saveButton)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Ready - themes are stored locally under %LOCALAPPDATA%.'
$status.Location = New-Object System.Drawing.Point 24, 602
$status.Size = New-Object System.Drawing.Size 926, 28
$status.Anchor = (
  [System.Windows.Forms.AnchorStyles]::Left -bor
  [System.Windows.Forms.AnchorStyles]::Right -bor
  [System.Windows.Forms.AnchorStyles]::Bottom
)
$status.ForeColor = [System.Drawing.Color]::FromArgb(133, 151, 176)
$form.Controls.Add($status)

$script:previewBitmap = $null

function Update-Preview {
  $preview.RuntimeWidth = [int]$widthNumeric.Value
  $preview.RuntimeHeight = [int]$heightNumeric.Value
  $preview.ContactSurfaceY = [int]$surfaceNumeric.Value
  $preview.ContactOverlap = [int]$overlapNumeric.Value
  $preview.ContentOffsetY = [int]$offsetNumeric.Value
  $preview.MetricsScrimOpacity = [int]$scrimNumeric.Value
  $preview.CompactMetrics = $compactCheck.Checked
  $preview.Accent = $script:accentColor
  $surfaceNumeric.Maximum = [math]::Max(0, [int]$heightNumeric.Value - 8)
  $offsetNumeric.Maximum = [math]::Max(-12, [int]$heightNumeric.Value - 48)
  $preview.Invalidate()
}

function Set-PreviewImage {
  param([Parameter(Mandatory = $true)][string]$Path)

  $bitmap = Get-UnlockedBitmap -Path $Path
  if ($null -ne $script:previewBitmap) {
    $script:previewBitmap.Dispose()
  }
  $script:previewBitmap = $bitmap
  $preview.Texture = $bitmap
  $imageBox.Text = $Path
  Update-Preview
}

foreach ($control in @(
  $widthNumeric,
  $heightNumeric,
  $surfaceNumeric,
  $overlapNumeric,
  $offsetNumeric,
  $scrimNumeric
)) {
  $control.Add_ValueChanged({ Update-Preview })
}
$compactCheck.Add_CheckedChanged({ Update-Preview })

$browseButton.Add_Click({
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Title = 'Choose a transparent base PNG'
  $dialog.Filter = 'PNG image (*.png)|*.png'
  $dialog.CheckFileExists = $true
  try {
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
      Set-PreviewImage -Path $dialog.FileName
      $status.Text = 'PNG loaded - adjust the dashed contact surface.'
    }
  } catch {
    [void][System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      'Could not load PNG',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )
  } finally {
    $dialog.Dispose()
  }
})

$accentButton.Add_Click({
  $dialog = New-Object System.Windows.Forms.ColorDialog
  $dialog.Color = $script:accentColor
  try {
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
      $script:accentColor = $dialog.Color
      $accentButton.Text = (
        'Accent  #{0:X2}{1:X2}{2:X2}' -f
        $dialog.Color.R,
        $dialog.Color.G,
        $dialog.Color.B
      )
      Update-Preview
    }
  } finally {
    $dialog.Dispose()
  }
})

$openButton.Add_Click({
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = 'Choose a custom theme directory'
  $dialog.SelectedPath = $customThemesDirectory
  try {
    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
      return
    }
    $resolvedRoot = [System.IO.Path]::GetFullPath($customThemesDirectory)
    $resolvedDirectory = [System.IO.Path]::GetFullPath($dialog.SelectedPath)
    if (-not $resolvedDirectory.StartsWith(
      $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      throw 'Choose a directory inside the Codex Pet Dock custom themes folder.'
    }
    $directoryInfo = Get-Item -LiteralPath $resolvedDirectory
    if (
      (
        $directoryInfo.Attributes -band
        [System.IO.FileAttributes]::ReparsePoint
      ) -ne 0
    ) {
      throw 'Reparse-point theme directories are not allowed.'
    }
    $manifestPath = Join-Path $resolvedDirectory 'theme.json'
    $manifestInfo = Get-Item -LiteralPath $manifestPath
    if (
      $manifestInfo.Length -gt 32768 -or
      (
        $manifestInfo.Attributes -band
        [System.IO.FileAttributes]::ReparsePoint
      ) -ne 0
    ) {
      throw 'theme.json is too large or is a reparse point.'
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath |
      ConvertFrom-Json
    $unknown = @(
      $manifest.PSObject.Properties.Name |
        Where-Object { $_ -notin $manifestFields }
    )
    if ($unknown.Count -gt 0) {
      throw 'Unsupported manifest fields: ' + ($unknown -join ', ')
    }
    $assetName = ([string]$manifest.asset).Trim()
    if (
      [System.IO.Path]::GetFileName($assetName) -ne $assetName -or
      [System.IO.Path]::GetExtension($assetName).ToLowerInvariant() -ne '.png'
    ) {
      throw 'Theme asset must be one PNG file name in the theme directory.'
    }
    $assetPath = [System.IO.Path]::GetFullPath(
      (Join-Path $resolvedDirectory $assetName)
    )
    if (-not $assetPath.StartsWith(
      $resolvedDirectory + [System.IO.Path]::DirectorySeparatorChar,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      throw 'Theme asset escaped its directory.'
    }
    $assetInfo = Get-Item -LiteralPath $assetPath
    if (
      $assetInfo.Length -gt 10485760 -or
      (
        $assetInfo.Attributes -band
        [System.IO.FileAttributes]::ReparsePoint
      ) -ne 0
    ) {
      throw 'Theme PNG is too large or is a reparse point.'
    }
    $nameBox.Text = [string]$manifest.name
    $idBox.Text = [string]$manifest.id
    $widthNumeric.Value = [int]$manifest.width
    $heightNumeric.Value = [int]$manifest.height
    $surfaceNumeric.Value = [int]$manifest.contactSurfaceY
    $overlapNumeric.Value = [int]$manifest.contactOverlap
    $offsetNumeric.Value = [int]$manifest.contentOffsetY
    $scrimNumeric.Value = [int]$manifest.metricsScrimOpacity
    $compactCheck.Checked = [bool]$manifest.compactMetrics
    $accentText = [string]$manifest.accent
    $script:accentColor = [System.Drawing.ColorTranslator]::FromHtml($accentText)
    $accentButton.Text = 'Accent  ' + $accentText.ToUpperInvariant()
    Set-PreviewImage -Path $assetPath
    $status.Text = 'Existing theme loaded - saving will update it safely.'
  } catch {
    [void][System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      'Could not open theme',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )
  } finally {
    $dialog.Dispose()
  }
})

$saveButton.Add_Click({
  try {
    $themeName = $nameBox.Text.Trim()
    $themeId = $idBox.Text.Trim().ToLowerInvariant()
    $sourcePath = $imageBox.Text.Trim()
    if ($themeName.Length -lt 1 -or $themeName.Length -gt 40) {
      throw 'Theme name must contain 1-40 characters.'
    }
    if ($themeId -notmatch '^[a-z0-9][a-z0-9._-]{2,63}$') {
      throw 'Theme ID must use 3-64 lowercase letters, digits, dot, dash, or underscore.'
    }
    if (
      [string]::IsNullOrWhiteSpace($sourcePath) -or
      -not (Test-Path -LiteralPath $sourcePath) -or
      [System.IO.Path]::GetExtension($sourcePath).ToLowerInvariant() -ne '.png'
    ) {
      throw 'Choose one PNG before saving.'
    }
    $sourceInfo = Get-Item -LiteralPath $sourcePath
    if (
      $sourceInfo.Length -gt 10485760 -or
      (
        $sourceInfo.Attributes -band
        [System.IO.FileAttributes]::ReparsePoint
      ) -ne 0
    ) {
      throw 'The PNG must be 10 MB or smaller and cannot be a reparse point.'
    }
    $sourceBitmap = Get-UnlockedBitmap -Path $sourcePath
    try {
      if (
        $sourceBitmap.Width -lt 64 -or
        $sourceBitmap.Height -lt 32 -or
        $sourceBitmap.Width -gt 4096 -or
        $sourceBitmap.Height -gt 4096
      ) {
        throw 'PNG dimensions must be between 64x32 and 4096x4096.'
      }
    } finally {
      $sourceBitmap.Dispose()
    }
    if (
      [int]$surfaceNumeric.Value + [int]$overlapNumeric.Value -gt
      [int]$heightNumeric.Value - 4
    ) {
      throw 'Contact surface plus overlap exceeds the theme height.'
    }
    $metricsBottom = (
      $(if ($compactCheck.Checked) { 62 } else { 64 }) +
      [int]$offsetNumeric.Value
    )
    if ($metricsBottom -gt [int]$heightNumeric.Value - 2) {
      throw 'Metric text would be clipped. Increase height or move metrics upward.'
    }

    $themeDirectory = [System.IO.Path]::GetFullPath(
      (Join-Path $customThemesDirectory $themeId)
    )
    $resolvedRoot = [System.IO.Path]::GetFullPath($customThemesDirectory)
    if (-not $themeDirectory.StartsWith(
      $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      throw 'Theme directory escaped the custom theme root.'
    }
    if (Test-Path -LiteralPath $themeDirectory) {
      $directoryInfo = Get-Item -LiteralPath $themeDirectory
      if (
        (
          $directoryInfo.Attributes -band
          [System.IO.FileAttributes]::ReparsePoint
        ) -ne 0
      ) {
        throw 'Reparse-point theme directories are not allowed.'
      }
      $answer = [System.Windows.Forms.MessageBox]::Show(
        'Update the existing theme "' + $themeId + '"?',
        'Confirm theme update',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
      )
      if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
      }
    } else {
      [void][System.IO.Directory]::CreateDirectory($themeDirectory)
    }

    $assetPath = Join-Path $themeDirectory 'platform.png'
    $resolvedSource = [System.IO.Path]::GetFullPath($sourcePath)
    if (-not $resolvedSource.Equals(
      [System.IO.Path]::GetFullPath($assetPath),
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      $assetTemporaryPath = $assetPath + '.tmp'
      [System.IO.File]::Copy($resolvedSource, $assetTemporaryPath, $true)
      if (Test-Path -LiteralPath $assetPath) {
        $assetBackupPath = $assetPath + '.bak'
        [System.IO.File]::Replace(
          $assetTemporaryPath,
          $assetPath,
          $assetBackupPath,
          $true
        )
        [System.IO.File]::Delete($assetBackupPath)
      } else {
        [System.IO.File]::Move($assetTemporaryPath, $assetPath)
      }
    }

    $accentHex = (
      '#{0:X2}{1:X2}{2:X2}' -f
      $script:accentColor.R,
      $script:accentColor.G,
      $script:accentColor.B
    )
    $manifest = [ordered]@{
      schemaVersion = 1
      id = $themeId
      name = $themeName
      asset = 'platform.png'
      width = [int]$widthNumeric.Value
      height = [int]$heightNumeric.Value
      contactSurfaceY = [int]$surfaceNumeric.Value
      contactOverlap = [int]$overlapNumeric.Value
      contentOffsetY = [int]$offsetNumeric.Value
      contactShadow = $true
      contactShadowY = [int]$surfaceNumeric.Value
      compactMetrics = [bool]$compactCheck.Checked
      metricsScrimOpacity = [int]$scrimNumeric.Value
      accent = $accentHex
    }
    $manifestPath = Join-Path $themeDirectory 'theme.json'
    $manifestTemporaryPath = $manifestPath + '.tmp'
    [System.IO.File]::WriteAllText(
      $manifestTemporaryPath,
      ($manifest | ConvertTo-Json),
      (New-Object System.Text.UTF8Encoding($false))
    )
    if (Test-Path -LiteralPath $manifestPath) {
      $manifestBackupPath = $manifestPath + '.bak'
      [System.IO.File]::Replace(
        $manifestTemporaryPath,
        $manifestPath,
        $manifestBackupPath,
        $true
      )
      [System.IO.File]::Delete($manifestBackupPath)
    } else {
      [System.IO.File]::Move($manifestTemporaryPath, $manifestPath)
    }

    try {
      $reloadEvent = [System.Threading.EventWaitHandle]::OpenExisting(
        'Local\CodexPetDock.ReloadThemes'
      )
      [void]$reloadEvent.Set()
      $reloadEvent.Dispose()
      $status.Text = 'Saved and reloaded - select it from the Base theme menu.'
    } catch {
      $status.Text = 'Saved - start Codex Pet Dock to load the new theme.'
    }
  } catch {
    [void][System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      'Could not save theme',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )
  }
})

$form.Add_FormClosed({
  if ($null -ne $script:previewBitmap) {
    $script:previewBitmap.Dispose()
    $script:previewBitmap = $null
  }
  if ($null -ne $form.Icon) {
    $form.Icon.Dispose()
  }
})

Update-Preview
if ($LayoutDiagnostics) {
  $layoutRows = @(
    $form.Controls |
      ForEach-Object {
        [pscustomobject]@{
          type = $_.GetType().Name
          text = [string]$_.Text
          left = [int]$_.Left
          top = [int]$_.Top
          right = [int]$_.Right
          bottom = [int]$_.Bottom
          insideClient = (
            $_.Left -ge 0 -and
            $_.Top -ge 0 -and
            $_.Right -le $form.ClientSize.Width -and
            $_.Bottom -le $form.ClientSize.Height
          )
        }
      }
  )
  [pscustomobject]@{
    ok = (@($layoutRows | Where-Object { -not $_.insideClient }).Count -eq 0)
    clientWidth = [int]$form.ClientSize.Width
    clientHeight = [int]$form.ClientSize.Height
    controls = $layoutRows
  } | ConvertTo-Json -Depth 4
  if ($null -ne $script:previewBitmap) {
    $script:previewBitmap.Dispose()
  }
  if ($null -ne $form.Icon) {
    $form.Icon.Dispose()
  }
  $form.Dispose()
  exit 0
}
[void]$form.ShowDialog()
$form.Dispose()
