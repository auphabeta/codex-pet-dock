[CmdletBinding()]
param(
  [switch]$Diagnostics,
  [int]$BaseOffsetX = 0,
  [int]$BaseOffsetY = 0,
  [string]$Theme = '',
  [ValidateRange(15, 3600)]
  [int]$RefreshSeconds = 300,
  [ValidateRange(0, 86400)]
  [int]$RunSeconds = 0,
  [switch]$AllowMultipleInstances,
  [switch]$ThemeSwitchDiagnostics,
  [switch]$PanelLayoutDiagnostics,
  [switch]$MascotSelectionDiagnostics,
  [ValidateSet('', 'en-US', 'zh-CN')]
  [string]$Language = '',
  [string]$ConfigDirectoryOverride = ''
)

$ErrorActionPreference = 'Stop'

$script:uiLanguage = 'en-US'
$localeDirectory = Join-Path $PSScriptRoot 'locales'

function Import-UiLocale {
  param([Parameter(Mandatory = $true)][string]$Locale)

  $localePath = Join-Path $localeDirectory ($Locale + '.json')
  if (-not (Test-Path -LiteralPath $localePath)) {
    throw 'UI locale file was not found: ' + $localePath
  }
  return Get-Content -Raw -Encoding UTF8 -LiteralPath $localePath |
    ConvertFrom-Json
}

$script:uiText = @{
  'en-US' = (Import-UiLocale -Locale 'en-US').app
  'zh-CN' = (Import-UiLocale -Locale 'zh-CN').app
}

function Get-UiText {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [object[]]$Arguments = @()
  )

  $languageTable = $script:uiText[$script:uiLanguage]
  $property = if ($null -ne $languageTable) {
    $languageTable.PSObject.Properties[$Key]
  } else {
    $null
  }
  if ($null -eq $property) {
    $languageTable = $script:uiText['en-US']
    $property = $languageTable.PSObject.Properties[$Key]
  }
  if ($null -eq $property) {
    throw 'Missing UI text key: ' + $Key
  }
  $template = [string]$property.Value
  if ($Arguments.Count -eq 0) {
    return $template
  }
  return [string]::Format(
    [Globalization.CultureInfo]::InvariantCulture,
    $template,
    [object[]]$Arguments
  )
}

$instanceMutex = $null
$ownsInstanceMutex = $false
$instanceActivationEvent = $null
$themeReloadEvent = $null
if (
  -not $Diagnostics -and
  -not $ThemeSwitchDiagnostics -and
  -not $PanelLayoutDiagnostics -and
  -not $MascotSelectionDiagnostics -and
  -not $AllowMultipleInstances
) {
  $createdNew = $false
  $instanceMutex = [System.Threading.Mutex]::new(
    $true,
    'Local\CodexPetDock.Singleton',
    [ref]$createdNew
  )
  if (-not $createdNew) {
    try {
      $existingActivationEvent = [System.Threading.EventWaitHandle]::OpenExisting(
        'Local\CodexPetDock.Activate'
      )
      [void]$existingActivationEvent.Set()
      $existingActivationEvent.Dispose()
    } catch {
      # A concurrent instance may still be creating its activation event.
    }
    $instanceMutex.Dispose()
    exit 0
  }
  $ownsInstanceMutex = $true
  $instanceActivationEvent = New-Object System.Threading.EventWaitHandle `
    $false, `
    ([System.Threading.EventResetMode]::AutoReset), `
    'Local\CodexPetDock.Activate'
  $themeReloadEvent = New-Object System.Threading.EventWaitHandle `
    $false, `
    ([System.Threading.EventResetMode]::AutoReset), `
    'Local\CodexPetDock.ReloadThemes'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -ReferencedAssemblies @(
  'System.Windows.Forms',
  'System.Drawing'
) -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace CodexPetQuota
{
    public static class NativeMethods
    {
        public const int GWL_EXSTYLE = -20;
        public const long WS_EX_TOPMOST = 0x00000008L;
        public const long WS_EX_TOOLWINDOW = 0x00000080L;

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxLength);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxLength);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool SetProcessDpiAwarenessContext(
            IntPtr dpiContext
        );

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int virtualKey);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(
            IntPtr hWnd,
            uint message,
            IntPtr wParam,
            IntPtr lParam
        );

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

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);

        [DllImport("user32.dll")]
        public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        public struct MONITORINFO
        {
            public int Size;
            public RECT Monitor;
            public RECT Work;
            public uint Flags;
        }
    }

    public class NoActivateForm : Form
    {
        public NoActivateForm()
        {
            AutoScaleMode = AutoScaleMode.None;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams parameters = base.CreateParams;
                parameters.ExStyle |= 0x08000000;
                parameters.ExStyle |= 0x00000080;
                return parameters;
            }
        }

    }

    public sealed class MouseTransparentForm : NoActivateForm
    {
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams parameters = base.CreateParams;
                parameters.ExStyle |= 0x00000020;
                return parameters;
            }
        }
    }

    public sealed class QuotaBar : Control
    {
        private int value = 0;
        private string caption = "";
        private string detail = "";

        public int Value
        {
            get { return value; }
            set { this.value = Math.Max(0, Math.Min(100, value)); Invalidate(); }
        }

        public string Caption
        {
            get { return caption; }
            set { caption = value ?? ""; Invalidate(); }
        }

        public string Detail
        {
            get { return detail; }
            set { detail = value ?? ""; Invalidate(); }
        }

        public QuotaBar()
        {
            DoubleBuffered = true;
            Height = 62;
            Width = 288;
            BackColor = Color.FromArgb(30, 32, 42);
            ForeColor = Color.White;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            using (Font titleFont = new Font(
                "Segoe UI",
                13f,
                FontStyle.Bold,
                GraphicsUnit.Pixel
            ))
            using (Font detailFont = new Font(
                "Segoe UI",
                11f,
                FontStyle.Regular,
                GraphicsUnit.Pixel
            ))
            using (Brush primary = new SolidBrush(Color.FromArgb(244, 246, 255)))
            using (Brush secondary = new SolidBrush(Color.FromArgb(166, 174, 197)))
            using (Brush track = new SolidBrush(Color.FromArgb(55, 59, 76)))
            {
                e.Graphics.DrawString(caption, titleFont, primary, 0, 2);
                SizeF valueSize = e.Graphics.MeasureString(value + "%", titleFont);
                e.Graphics.DrawString(value + "%", titleFont, primary, Width - valueSize.Width, 2);

                Rectangle trackRect = new Rectangle(0, 27, Width, 8);
                using (GraphicsPath trackPath = RoundedRect(trackRect, 4))
                {
                    e.Graphics.FillPath(track, trackPath);
                }

                int fillWidth = (int)Math.Round(Width * value / 100.0);
                if (fillWidth > 0)
                {
                    Color fillColor = value > 50
                        ? Color.FromArgb(91, 124, 250)
                        : value > 20
                            ? Color.FromArgb(242, 174, 74)
                            : Color.FromArgb(239, 93, 105);
                    Rectangle fillRect = new Rectangle(0, 27, Math.Max(8, fillWidth), 8);
                    using (GraphicsPath fillPath = RoundedRect(fillRect, 4))
                    using (Brush fill = new SolidBrush(fillColor))
                    {
                        e.Graphics.FillPath(fill, fillPath);
                    }
                }

                e.Graphics.DrawString(detail, detailFont, secondary, 0, 42);
            }
        }

        private static GraphicsPath RoundedRect(Rectangle rectangle, int radius)
        {
            int diameter = radius * 2;
            GraphicsPath path = new GraphicsPath();
            path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    public sealed class PetBaseControl : Control
    {
        private int remaining = 0;
        private int state = 0;
        private string windowCode = "LIMIT";
        private string resetDate = "--";
        private string resetTime = "--:--";
        private string planCode = "";
        private string tokenLabel = "--";
        private string tokenHeader = "WEEK TOKENS";
        private Image baseTexture = null;
        private bool hovered = false;
        private bool showContactShadow = true;
        private bool compactMetrics = false;
        private int metricsScrimOpacity = 60;
        private int contactShadowY = 14;
        private int contentOffsetY = 0;
        private Color healthyAccent = Color.FromArgb(210, 111, 232, 239);

        public int Remaining
        {
            get { return remaining; }
            set { remaining = Math.Max(0, Math.Min(100, value)); Invalidate(); }
        }

        public int State
        {
            get { return state; }
            set { state = value; Invalidate(); }
        }

        public string WindowCode
        {
            get { return windowCode; }
            set { windowCode = value ?? "LIMIT"; Invalidate(); }
        }

        public string ResetDate
        {
            get { return resetDate; }
            set { resetDate = value ?? "--"; Invalidate(); }
        }

        public string ResetTime
        {
            get { return resetTime; }
            set { resetTime = value ?? "--:--"; Invalidate(); }
        }

        public string PlanCode
        {
            get { return planCode; }
            set { planCode = value ?? ""; Invalidate(); }
        }

        public string TokenLabel
        {
            get { return tokenLabel; }
            set { tokenLabel = value ?? "--"; Invalidate(); }
        }

        public string TokenHeader
        {
            get { return tokenHeader; }
            set { tokenHeader = value ?? "WEEK TOKENS"; Invalidate(); }
        }

        public Image BaseTexture
        {
            get { return baseTexture; }
            set { baseTexture = value; Invalidate(); }
        }

        public bool ShowContactShadow
        {
            get { return showContactShadow; }
            set { showContactShadow = value; Invalidate(); }
        }

        public int ContactShadowY
        {
            get { return contactShadowY; }
            set { contactShadowY = value; Invalidate(); }
        }

        public int ContentOffsetY
        {
            get { return contentOffsetY; }
            set { contentOffsetY = value; Invalidate(); }
        }

        public bool CompactMetrics
        {
            get { return compactMetrics; }
            set { compactMetrics = value; Invalidate(); }
        }

        public int MetricsScrimOpacity
        {
            get { return metricsScrimOpacity; }
            set
            {
                metricsScrimOpacity = Math.Max(0, Math.Min(220, value));
                Invalidate();
            }
        }

        public int MetricsBottom
        {
            get
            {
                int valueTop = compactMetrics ? 44 : 43;
                int valueHeight = compactMetrics ? 18 : 21;
                return valueTop + contentOffsetY + valueHeight;
            }
        }

        public bool MetricsFontFits
        {
            get
            {
                using (Bitmap sample = new Bitmap(1, 1))
                using (Graphics graphics = Graphics.FromImage(sample))
                using (Font micro = new Font(
                    "Segoe UI Semibold",
                    9.0f,
                    FontStyle.Regular,
                    GraphicsUnit.Pixel
                ))
                using (Font valueFont = new Font(
                    "Bahnschrift SemiBold",
                    compactMetrics ? 14.0f : 17.0f,
                    FontStyle.Regular,
                    GraphicsUnit.Pixel
                ))
                {
                    int valueHeight = compactMetrics ? 18 : 21;
                    return
                        micro.GetHeight(graphics) <= 12.0f &&
                        valueFont.GetHeight(graphics) <= valueHeight &&
                        graphics.MeasureString(windowCode, micro).Width <= 82.0f &&
                        graphics.MeasureString(tokenHeader, micro).Width <= 82.0f;
                }
            }
        }

        public double MetricsAlphaCoverage
        {
            get
            {
                if (baseTexture == null)
                {
                    return 1.0;
                }

                int valueTop = compactMetrics ? 44 : 43;
                int valueHeight = compactMetrics ? 18 : 21;
                Rectangle[] regions = new Rectangle[] {
                    new Rectangle(40, 32 + contentOffsetY, 64, 12),
                    new Rectangle(120, 32 + contentOffsetY, 64, 12),
                    new Rectangle(
                        40,
                        valueTop + contentOffsetY,
                        64,
                        valueHeight
                    ),
                    new Rectangle(
                        120,
                        valueTop + contentOffsetY,
                        64,
                        valueHeight
                    )
                };

                double minimum = 1.0;
                using (Bitmap sample = new Bitmap(baseTexture, Width, Height))
                {
                    foreach (Rectangle region in regions)
                    {
                        int visible = 0;
                        int total = 0;
                        int bottom = Math.Min(Height, region.Bottom);
                        int right = Math.Min(Width, region.Right);
                        for (int y = Math.Max(0, region.Top); y < bottom; y++)
                        {
                            for (int x = Math.Max(0, region.Left); x < right; x++)
                            {
                                total += 1;
                                if (sample.GetPixel(x, y).A > 12)
                                {
                                    visible += 1;
                                }
                            }
                        }
                        double coverage = total == 0
                            ? 0.0
                            : (double)visible / total;
                        minimum = Math.Min(minimum, coverage);
                    }
                }
                return minimum;
            }
        }

        public Color HealthyAccent
        {
            get { return healthyAccent; }
            set { healthyAccent = value; Invalidate(); }
        }

        public PetBaseControl()
        {
            DoubleBuffered = true;
            Width = 224;
            Height = 72;
            Cursor = Cursors.Hand;
            SetStyle(
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw |
                ControlStyles.UserPaint,
                true
            );
        }

        public void ApplyHostRegion(Form host)
        {
            if (baseTexture != null)
            {
                using (Bitmap sample = new Bitmap(baseTexture, Width, Height))
                using (GraphicsPath texturePath = new GraphicsPath())
                {
                    for (int y = 0; y < sample.Height; y++)
                    {
                        int runStart = -1;
                        for (int x = 0; x <= sample.Width; x++)
                        {
                            bool visible =
                                x < sample.Width &&
                                sample.GetPixel(x, y).A > 12;
                            if (visible && runStart < 0)
                            {
                                runStart = x;
                            }
                            else if (!visible && runStart >= 0)
                            {
                                texturePath.AddRectangle(
                                    new Rectangle(
                                        runStart,
                                        y,
                                        x - runStart,
                                        1
                                    )
                                );
                                runStart = -1;
                            }
                        }
                    }

                    if (texturePath.PointCount > 0)
                    {
                        Region oldRegion = host.Region;
                        host.Region = new Region(texturePath);
                        if (oldRegion != null)
                        {
                            oldRegion.Dispose();
                        }
                        return;
                    }
                }
            }

            using (GraphicsPath path = CreateSilhouette(Width, Height))
            {
                Region oldRegion = host.Region;
                host.Region = new Region(path);
                if (oldRegion != null)
                {
                    oldRegion.Dispose();
                }
            }
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            hovered = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            hovered = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.TextRenderingHint =
                System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;

            if (baseTexture != null)
            {
                e.Graphics.CompositingQuality =
                    CompositingQuality.HighQuality;
                e.Graphics.InterpolationMode =
                    InterpolationMode.HighQualityBicubic;
                e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                e.Graphics.DrawImage(
                    baseTexture,
                    new Rectangle(0, 0, Width, Height)
                );

                // A soft contact shadow on the raised rear pad makes the
                // independently rendered mascot feel grounded on the base.
                if (showContactShadow)
                {
                    Rectangle contactRect = new Rectangle(
                        81,
                        contactShadowY,
                        62,
                        11
                    );
                    using (GraphicsPath contact = new GraphicsPath())
                    {
                        contact.AddEllipse(contactRect);
                        using (PathGradientBrush shadow =
                            new PathGradientBrush(contact))
                        {
                            shadow.CenterColor = Color.FromArgb(142, 0, 7, 16);
                            shadow.SurroundColors = new Color[] {
                                Color.FromArgb(0, 0, 16, 28)
                            };
                            e.Graphics.FillPath(shadow, contact);
                        }
                    }
                }
            }
            else
            {
                using (GraphicsPath shell = CreateSilhouette(Width, Height))
                using (LinearGradientBrush ice = new LinearGradientBrush(
                    ClientRectangle,
                    hovered
                        ? Color.FromArgb(246, 174, 227, 250)
                        : Color.FromArgb(238, 127, 201, 238),
                    hovered
                        ? Color.FromArgb(249, 65, 133, 193)
                        : Color.FromArgb(246, 42, 101, 164),
                    LinearGradientMode.Vertical
                ))
                using (Pen rim = new Pen(
                    hovered
                        ? Color.FromArgb(228, 228, 249, 255)
                        : Color.FromArgb(170, 169, 222, 248),
                    1.0f
                ))
                {
                    e.Graphics.FillPath(ice, shell);
                    e.Graphics.DrawPath(rim, shell);
                }

                Rectangle panelRect = new Rectangle(7, 5, Width - 14, 27);
                using (GraphicsPath panel = CreateRoundedRect(panelRect, 12))
                using (LinearGradientBrush panelSurface =
                    new LinearGradientBrush(
                        panelRect,
                        hovered
                            ? Color.FromArgb(247, 20, 43, 76)
                            : Color.FromArgb(248, 14, 32, 61),
                        Color.FromArgb(252, 6, 17, 37),
                        LinearGradientMode.Vertical
                    ))
                using (Pen panelRim = new Pen(
                    Color.FromArgb(94, 176, 225, 255),
                    1
                ))
                {
                    e.Graphics.FillPath(panelSurface, panel);
                    e.Graphics.DrawPath(panelRim, panel);
                }
            }

            Color accent = state == 2
                ? Color.FromArgb(242, 102, 118)
                : remaining > 50
                    ? healthyAccent
                    : remaining > 20
                        ? Color.FromArgb(246, 181, 79)
                        : Color.FromArgb(242, 102, 118);

            if (metricsScrimOpacity > 0)
            {
                int scrimTop = 31 + contentOffsetY;
                Rectangle scrimRect = new Rectangle(
                    29,
                    scrimTop,
                    166,
                    Math.Max(12, MetricsBottom - scrimTop + 1)
                );
                using (GraphicsPath scrim = CreateRoundedRect(scrimRect, 7))
                using (LinearGradientBrush scrimBrush =
                    new LinearGradientBrush(
                        scrimRect,
                        Color.FromArgb(
                            metricsScrimOpacity,
                            3,
                            9,
                            19
                        ),
                        Color.FromArgb(
                            Math.Max(0, metricsScrimOpacity - 24),
                            7,
                            17,
                            31
                        ),
                        LinearGradientMode.Vertical
                    ))
                using (Pen scrimRim = new Pen(
                    Color.FromArgb(
                        Math.Min(80, metricsScrimOpacity / 2),
                        accent
                    ),
                    1.0f
                ))
                {
                    e.Graphics.FillPath(scrimBrush, scrim);
                    e.Graphics.DrawPath(scrimRim, scrim);
                }
            }

            using (Font micro = new Font(
                "Segoe UI Semibold",
                9.0f,
                FontStyle.Regular,
                GraphicsUnit.Pixel
            ))
            using (Font valueFont = new Font(
                "Bahnschrift SemiBold",
                compactMetrics ? 14.0f : 17.0f,
                FontStyle.Regular,
                GraphicsUnit.Pixel
            ))
            using (Brush text = new SolidBrush(Color.FromArgb(240, 244, 255)))
            using (Brush muted = new SolidBrush(Color.FromArgb(238, 202, 232, 237)))
            using (Brush textShadow = new SolidBrush(Color.FromArgb(232, 0, 4, 10)))
            using (Pen divider = new Pen(Color.FromArgb(42, 151, 205, 215), 1))
            using (Pen progressTrack = new Pen(
                Color.FromArgb(150, 25, 57, 72),
                1.4f
            ))
            using (Pen progressGlow = new Pen(
                Color.FromArgb(26, accent),
                3.2f
            ))
            using (Pen progress = new Pen(accent, 1.4f))
            using (StringFormat centered = new StringFormat())
            {
                centered.Alignment = StringAlignment.Center;
                centered.LineAlignment = StringAlignment.Near;
                progressGlow.StartCap = LineCap.Round;
                progressGlow.EndCap = LineCap.Round;
                progress.StartCap = LineCap.Round;
                progress.EndCap = LineCap.Round;
                const int progressLeft = 57;
                const int progressRight = 167;
                int progressY = 29 + contentOffsetY;
                e.Graphics.DrawLine(
                    progressTrack,
                    progressLeft,
                    progressY,
                    progressRight,
                    progressY
                );
                int progressWidth = state == 1
                    ? (int)Math.Round(
                        (progressRight - progressLeft) * remaining / 100.0
                    )
                    : 0;
                if (progressWidth > 0)
                {
                    e.Graphics.DrawLine(
                        progressGlow,
                        progressLeft,
                        progressY,
                        progressLeft + progressWidth,
                        progressY
                    );
                    e.Graphics.DrawLine(
                        progress,
                        progressLeft,
                        progressY,
                        progressLeft + progressWidth,
                        progressY
                    );
                }

                string leftHeader = windowCode;
                RectangleF leftHeaderRect = new RectangleF(
                    30, 32 + contentOffsetY, 82, 12
                );
                RectangleF rightHeaderRect = new RectangleF(
                    112, 32 + contentOffsetY, 82, 12
                );
                RectangleF leftValueRect = new RectangleF(
                    30,
                    (compactMetrics ? 44 : 43) + contentOffsetY,
                    82,
                    compactMetrics ? 18 : 21
                );
                RectangleF rightValueRect = new RectangleF(
                    112,
                    (compactMetrics ? 44 : 43) + contentOffsetY,
                    82,
                    compactMetrics ? 18 : 21
                );
                RectangleF leftHeaderShadowRect = leftHeaderRect;
                leftHeaderShadowRect.Offset(0, 1);
                e.Graphics.DrawString(
                    leftHeader,
                    micro,
                    textShadow,
                    leftHeaderShadowRect,
                    centered
                );
                e.Graphics.DrawString(
                    leftHeader,
                    micro,
                    muted,
                    leftHeaderRect,
                    centered
                );

                string valueText = state == 0
                    ? "--"
                    : state == 2
                        ? "!"
                        : remaining.ToString() + "%";
                RectangleF leftValueShadowRect = leftValueRect;
                leftValueShadowRect.Offset(1, 1);
                e.Graphics.DrawString(
                    valueText,
                    valueFont,
                    textShadow,
                    leftValueShadowRect,
                    centered
                );
                e.Graphics.DrawString(
                    valueText,
                    valueFont,
                    text,
                    leftValueRect,
                    centered
                );
                RectangleF rightHeaderShadowRect = rightHeaderRect;
                rightHeaderShadowRect.Offset(0, 1);
                e.Graphics.DrawString(
                    tokenHeader,
                    micro,
                    textShadow,
                    rightHeaderShadowRect,
                    centered
                );
                e.Graphics.DrawString(
                    tokenHeader,
                    micro,
                    muted,
                    rightHeaderRect,
                    centered
                );
                RectangleF rightValueShadowRect = rightValueRect;
                rightValueShadowRect.Offset(1, 1);
                e.Graphics.DrawString(
                    tokenLabel,
                    valueFont,
                    textShadow,
                    rightValueShadowRect,
                    centered
                );
                e.Graphics.DrawString(
                    tokenLabel,
                    valueFont,
                    text,
                    rightValueRect,
                    centered
                );

                e.Graphics.DrawLine(
                    divider,
                    112,
                    36 + contentOffsetY,
                    112,
                    (compactMetrics ? 91 : 63 + contentOffsetY)
                );
            }
        }

        private static GraphicsPath CreateSilhouette(int width, int height)
        {
            GraphicsPath path = new GraphicsPath();
            path.AddPolygon(new Point[] {
                new Point(47, 8),
                new Point(width - 47, 8),
                new Point(width - 18, 18),
                new Point(width - 7, 28),
                new Point(width - 1, 43),
                new Point(width - 8, 53),
                new Point(width - 28, height - 1),
                new Point(28, height - 1),
                new Point(8, 53),
                new Point(1, 43),
                new Point(7, 28),
                new Point(18, 18)
            });
            return path;
        }

        private static GraphicsPath CreateRoundedRect(
            Rectangle rectangle,
            int radius
        )
        {
            int diameter = radius * 2;
            GraphicsPath path = new GraphicsPath();
            path.AddArc(
                rectangle.Left,
                rectangle.Top,
                diameter,
                diameter,
                180,
                90
            );
            path.AddArc(
                rectangle.Right - diameter,
                rectangle.Top,
                diameter,
                diameter,
                270,
                90
            );
            path.AddArc(
                rectangle.Right - diameter,
                rectangle.Bottom - diameter,
                diameter,
                diameter,
                0,
                90
            );
            path.AddArc(
                rectangle.Left,
                rectangle.Bottom - diameter,
                diameter,
                diameter,
                90,
                90
            );
            path.CloseFigure();
            return path;
        }
    }
}
'@

# Use one coordinate space across Win32, UI Automation and WinForms. This must
# run before the first window handle is created. -4 is PER_MONITOR_AWARE_V2.
try {
  $script:perMonitorDpiAware = (
    [CodexPetQuota.NativeMethods]::SetProcessDpiAwarenessContext(
      [IntPtr](-4)
    )
  )
} catch {
  $script:perMonitorDpiAware = $false
  # Older Windows builds can reject the context; relative DPI conversion in
  # Get-PetMascotBounds remains as the fallback.
}

function Quote-NativeArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Get-NativeProbeExecutable {
  $candidate = Join-Path $PSScriptRoot 'native\CodexPetProbe.exe'
  if (-not (Test-Path -LiteralPath $candidate)) {
    throw (
      'CodexPetProbe.exe is missing. Reinstall Codex Pet Dock or run ' +
      'packaging\Build-Native.ps1 before starting from source.'
    )
  }
  return [System.IO.Path]::GetFullPath($candidate)
}

function Get-CodexExecutable {
  $desktopBin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
  if (Test-Path -LiteralPath $desktopBin) {
    $candidate = Get-ChildItem -LiteralPath $desktopBin -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($null -ne $candidate) {
      return $candidate.FullName
    }
  }

  $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
  if ($null -ne $codexCommand) {
    $commandRoot = Split-Path -Parent $codexCommand.Source
    $vendorRoot = Join-Path $commandRoot 'node_modules\@openai\codex\node_modules'
    if (Test-Path -LiteralPath $vendorRoot) {
      $candidate = Get-ChildItem -LiteralPath $vendorRoot -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*vendor*x86_64-pc-windows-msvc*bin*' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
      if ($null -ne $candidate) {
        return $candidate.FullName
      }
    }
  }

  throw 'Could not find a directly runnable Codex CLI executable.'
}

function Get-OfficialCodexProcessIds {
  $now = [DateTime]::Now
  if (
    $null -ne $script:officialCodexProcessIds -and
    $null -ne $script:officialCodexProcessIdsReadAt -and
    (
      $now - [DateTime]$script:officialCodexProcessIdsReadAt
    ).TotalSeconds -lt 2
  ) {
    return @($script:officialCodexProcessIds)
  }

  $script:officialCodexProcessIds = @(
    Get-CimInstance Win32_Process |
      Where-Object {
        $_.Name -eq 'ChatGPT.exe' -and
        $_.ExecutablePath -like '*\WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe'
      } |
      Select-Object -ExpandProperty ProcessId
  )
  $script:officialCodexProcessIdsReadAt = $now
  return @($script:officialCodexProcessIds)
}

function Get-PetWindow {
  $officialProcessIds = Get-OfficialCodexProcessIds
  if ($officialProcessIds.Count -eq 0) {
    return $null
  }

  $matches = New-Object System.Collections.Generic.List[object]
  $callback = [CodexPetQuota.NativeMethods+EnumWindowsProc] {
    param($windowHandle, $lParam)

    [uint32]$processIdValue = 0
    [void][CodexPetQuota.NativeMethods]::GetWindowThreadProcessId(
      $windowHandle,
      [ref]$processIdValue
    )

    if ($officialProcessIds -notcontains [int]$processIdValue) {
      return $true
    }
    if (-not [CodexPetQuota.NativeMethods]::IsWindowVisible($windowHandle)) {
      return $true
    }

    $className = New-Object System.Text.StringBuilder 128
    $title = New-Object System.Text.StringBuilder 256
    [void][CodexPetQuota.NativeMethods]::GetClassName(
      $windowHandle,
      $className,
      $className.Capacity
    )
    [void][CodexPetQuota.NativeMethods]::GetWindowText(
      $windowHandle,
      $title,
      $title.Capacity
    )

    if ($className.ToString() -ne 'Chrome_WidgetWin_1') {
      return $true
    }

    $rect = New-Object CodexPetQuota.NativeMethods+RECT
    [void][CodexPetQuota.NativeMethods]::GetWindowRect($windowHandle, [ref]$rect)
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if (
      $width -lt 120 -or
      $height -lt 120 -or
      $width -gt 1600 -or
      $height -gt 1600
    ) {
      return $true
    }

    $extendedStyle = [CodexPetQuota.NativeMethods]::GetWindowLongPtr(
      $windowHandle,
      [CodexPetQuota.NativeMethods]::GWL_EXSTYLE
    ).ToInt64()
    $isToolWindow = (
      $extendedStyle -band [CodexPetQuota.NativeMethods]::WS_EX_TOOLWINDOW
    ) -ne 0
    $isTopMost = (
      $extendedStyle -band [CodexPetQuota.NativeMethods]::WS_EX_TOPMOST
    ) -ne 0
    if (-not $isToolWindow -or -not $isTopMost) {
      return $true
    }

    $matches.Add([pscustomobject]@{
      Handle = $windowHandle
      ProcessId = $processIdValue
      Title = $title.ToString()
      ZOrder = $matches.Count
      Left = $rect.Left
      Top = $rect.Top
      Right = $rect.Right
      Bottom = $rect.Bottom
      Width = $width
      Height = $height
    })
    return $true
  }

  [void][CodexPetQuota.NativeMethods]::EnumWindows(
    $callback,
    [IntPtr]::Zero
  )

  if ($matches.Count -eq 0) {
    return $null
  }

  return $matches |
    Sort-Object -Property @{
      Expression = { if ($_.Title -eq 'Codex') { 0 } else { 1 } }
    }, @{
      Expression = { $_.Width * $_.Height }
    }, @{
      Expression = { $_.ZOrder }
    } |
    Select-Object -First 1
}

function Get-TrackedPetWindow {
  param($PetWindow)

  if (
    $null -eq $PetWindow -or
    -not [CodexPetQuota.NativeMethods]::IsWindow(
      [IntPtr]$PetWindow.Handle
    )
  ) {
    return $null
  }

  $rect = New-Object CodexPetQuota.NativeMethods+RECT
  if (
    -not [CodexPetQuota.NativeMethods]::GetWindowRect(
      [IntPtr]$PetWindow.Handle,
      [ref]$rect
    )
  ) {
    return $null
  }

  return [pscustomobject]@{
    Handle = [IntPtr]$PetWindow.Handle
    ProcessId = $PetWindow.ProcessId
    Title = $PetWindow.Title
    Left = $rect.Left
    Top = $rect.Top
    Right = $rect.Right
    Bottom = $rect.Bottom
    Width = $rect.Right - $rect.Left
    Height = $rect.Bottom - $rect.Top
    Visible = [CodexPetQuota.NativeMethods]::IsWindowVisible(
      [IntPtr]$PetWindow.Handle
    )
  }
}

function Reset-PetMascotTracking {
  param([switch]$ClearLastBounds)

  $script:mascotAutomationElement = $null
  $script:mascotAutomationRoot = $null
  $script:mascotAutomationHandle = 0
  $script:mascotAutomationLookupAt = [DateTime]::MinValue
  $script:mascotAutomationIdentity = ''
  if ($ClearLastBounds) {
    $script:lastMascotBounds = $null
    $script:lastMascotSeenAt = [DateTime]::MinValue
    $script:lastMascotSignature = ''
  }
}

function Extend-FastTracking {
  param(
    [ValidateRange(16, 5000)]
    [int]$Milliseconds
  )

  $candidate = [DateTime]::Now.AddMilliseconds($Milliseconds)
  if ($candidate -gt $script:fastTrackingUntil) {
    $script:fastTrackingUntil = $candidate
  }
}

function Get-SmoothedDockCoordinate {
  param(
    [int]$Current,
    [int]$Target,
    [ValidateRange(8, 1000)]
    [int]$SnapDistance = 160
  )

  $delta = $Target - $Current
  $distance = [math]::Abs($delta)
  if ($distance -le 1 -or $distance -ge $SnapDistance) {
    return $Target
  }

  # A strong critically-damped step removes single-frame jitter without
  # leaving the dock visibly trailing behind a dragged pet.
  $step = [int][math]::Round([double]$delta * 0.68)
  if ($step -eq 0) {
    $step = [math]::Sign($delta)
  }
  return $Current + $step
}

function Get-StableMascotIdentity {
  param(
    [string]$Name,
    [string]$RuntimeId
  )

  $normalizedName = $Name.Trim()
  if (-not [string]::IsNullOrWhiteSpace($normalizedName)) {
    return 'name|' + $normalizedName
  }
  return 'runtime|' + $RuntimeId
}

function Select-PetMascotCandidate {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Candidates,
    $ReferenceBounds
  )

  $selectedCandidate = $null
  $selectedDistance = [double]::PositiveInfinity
  $selectedArea = 0.0
  foreach ($candidate in $Candidates) {
    $candidateRect = $candidate.Bounds
    $candidateArea = (
      [double]$candidateRect.Width *
      [double]$candidateRect.Height
    )
    $candidateDistance = 0.0
    if ($null -ne $ReferenceBounds) {
      $candidateCenterX = (
        [double]$candidateRect.X +
        ([double]$candidateRect.Width / 2)
      )
      $candidateCenterY = (
        [double]$candidateRect.Y +
        ([double]$candidateRect.Height / 2)
      )
      $referenceCenterX = (
        [double]$ReferenceBounds.Left +
        ([double]$ReferenceBounds.Width / 2)
      )
      $referenceCenterY = (
        [double]$ReferenceBounds.Top +
        ([double]$ReferenceBounds.Height / 2)
      )
      $deltaX = $candidateCenterX - $referenceCenterX
      $deltaY = $candidateCenterY - $referenceCenterY
      $candidateDistance = (
        ($deltaX * $deltaX) +
        ($deltaY * $deltaY)
      )
    }

    $distanceIsBetter = $candidateDistance -lt $selectedDistance
    $distanceIsTied = (
      [math]::Abs($candidateDistance - $selectedDistance) -lt 0.5
    )
    if (
      $null -eq $selectedCandidate -or
      $distanceIsBetter -or
      ($distanceIsTied -and $candidateArea -ge $selectedArea)
    ) {
      $selectedCandidate = $candidate
      $selectedDistance = $candidateDistance
      $selectedArea = $candidateArea
    }
  }

  return $selectedCandidate
}

function Get-PetMascotBounds {
  param($PetWindow)

  if ($null -eq $PetWindow) {
    return $null
  }

  try {
    $now = [DateTime]::Now
    $mascotLookupIntervalMs = if (
      (
        [CodexPetQuota.NativeMethods]::GetAsyncKeyState(0x01) -band 0x8000
      ) -ne 0 -or
      $now -lt $script:fastTrackingUntil
    ) {
      80
    } else {
      500
    }

    $cachedMascotUsable = $false
    if (
      $null -ne $script:mascotAutomationElement -and
      $script:mascotAutomationHandle -eq [Int64]$PetWindow.Handle
    ) {
      try {
        $cachedRect = (
          $script:mascotAutomationElement.Current.BoundingRectangle
        )
        $cachedMascotUsable = (
          ([string]$script:mascotAutomationElement.Current.ClassName).
            StartsWith('codex-avatar-button') -and
          -not $script:mascotAutomationElement.Current.IsOffscreen -and
          $cachedRect.Width -gt 0 -and
          $cachedRect.Height -gt 0
        )
      } catch {
        $cachedMascotUsable = $false
      }
    }
    if (
      $null -ne $script:mascotAutomationElement -and
      -not $cachedMascotUsable
    ) {
      $script:mascotAutomationElement = $null
      $script:mascotAutomationLookupAt = [DateTime]::MinValue
      Extend-FastTracking -Milliseconds 1500
    }

    $mascotLookupExpired = (
      $null -eq $script:mascotAutomationLookupAt -or
      (
        $now - [DateTime]$script:mascotAutomationLookupAt
      ).TotalMilliseconds -ge $mascotLookupIntervalMs
    )
    $needsMascotLookup = (
      $null -eq $script:mascotAutomationElement -or
      $script:mascotAutomationHandle -ne [Int64]$PetWindow.Handle -or
      $mascotLookupExpired
    )
    if ($needsMascotLookup) {
      if (
        $null -eq $script:mascotAutomationRoot -or
        $script:mascotAutomationHandle -ne [Int64]$PetWindow.Handle
      ) {
        $script:mascotAutomationRoot = (
          [System.Windows.Automation.AutomationElement]::FromHandle(
            [IntPtr]$PetWindow.Handle
          )
        )
      }

      $mascotCandidates = @()
      $elements = $script:mascotAutomationRoot.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition
      )
      foreach ($element in $elements) {
        if (
          ([string]$element.Current.ClassName).StartsWith(
            'codex-avatar-button'
          )
        ) {
          $candidateRect = $element.Current.BoundingRectangle
          if (
            -not $element.Current.IsOffscreen -and
            $candidateRect.Width -gt 0 -and
            $candidateRect.Height -gt 0
          ) {
            $mascotCandidates += [pscustomobject]@{
              Element = $element
              Bounds = $candidateRect
            }
          }
        }
      }

      $selectedCandidate = Select-PetMascotCandidate `
        -Candidates $mascotCandidates `
        -ReferenceBounds $script:lastMascotBounds
      $selectedMascot = if ($null -ne $selectedCandidate) {
        $selectedCandidate.Element
      } else {
        $null
      }
      if ($null -ne $selectedMascot) {
        $selectedName = try {
          [string]$selectedMascot.Current.Name
        } catch {
          ''
        }
        $selectedRuntimeId = try {
          $selectedMascot.GetRuntimeId() -join '.'
        } catch {
          [string]$selectedMascot.Current.ClassName
        }
        $selectedIdentity = Get-StableMascotIdentity `
          -Name $selectedName `
          -RuntimeId $selectedRuntimeId
        if (
          -not [string]::IsNullOrWhiteSpace(
            [string]$script:mascotAutomationIdentity
          ) -and
          $selectedIdentity -ne $script:mascotAutomationIdentity
        ) {
          $script:lastMascotBounds = $null
          $script:lastMascotSeenAt = [DateTime]::MinValue
          $script:lastMascotSignature = ''
          $script:lastBaseTargetSignature = ''
          $script:baseIsSettling = $false
          $script:snapDockToMascotAtNextFrame = $true
          Extend-FastTracking -Milliseconds 1500
        }
        $script:mascotAutomationIdentity = $selectedIdentity
      }
      $script:mascotAutomationElement = $selectedMascot
      $script:mascotAutomationHandle = [Int64]$PetWindow.Handle
      $script:mascotAutomationLookupAt = $now
    }

    if ($null -eq $script:mascotAutomationElement) {
      return $null
    }

    $mascotRect = (
      $script:mascotAutomationElement.Current.BoundingRectangle
    )
    if (
      $mascotRect.Width -le 0 -or
      $mascotRect.Height -le 0
    ) {
      return $null
    }

    if ($script:perMonitorDpiAware) {
      return [pscustomobject]@{
        Left = [int][math]::Round([double]$mascotRect.X)
        Top = [int][math]::Round([double]$mascotRect.Y)
        Width = [int][math]::Round([double]$mascotRect.Width)
        Height = [int][math]::Round([double]$mascotRect.Height)
      }
    }

    # UI Automation returns physical screen pixels. Windows PowerShell's
    # WinForms coordinates can be DPI-virtualized, so convert relative to the
    # same Codex window instead of assuming a system-wide scale factor.
    $rootRect = $script:mascotAutomationRoot.Current.BoundingRectangle
    if ($rootRect.Width -le 0 -or $rootRect.Height -le 0) {
      return $null
    }
    $scaleX = [double]$rootRect.Width / [double]$PetWindow.Width
    $scaleY = [double]$rootRect.Height / [double]$PetWindow.Height
    if ($scaleX -le 0 -or $scaleY -le 0) {
      return $null
    }

    $left = (
      [double]$PetWindow.Left +
      (([double]$mascotRect.X - [double]$rootRect.X) / $scaleX)
    )
    $top = (
      [double]$PetWindow.Top +
      (([double]$mascotRect.Y - [double]$rootRect.Y) / $scaleY)
    )
    return [pscustomobject]@{
      Left = [int][math]::Round($left)
      Top = [int][math]::Round($top)
      Width = [int][math]::Round([double]$mascotRect.Width / $scaleX)
      Height = [int][math]::Round([double]$mascotRect.Height / $scaleY)
    }
  } catch {
    $script:mascotAutomationElement = $null
    $script:mascotAutomationRoot = $null
    $script:mascotAutomationHandle = 0
    $script:mascotAutomationLookupAt = [DateTime]::MinValue
    Extend-FastTracking -Milliseconds 1500
    return $null
  }
}

if ($MascotSelectionDiagnostics) {
  $referenceBounds = [pscustomobject]@{
    Left = 100
    Top = 100
    Width = 120
    Height = 140
  }
  $diagnosticCandidates = @(
    [pscustomobject]@{
      Id = 'main-current'
      Element = $null
      Bounds = [pscustomobject]@{
        X = 102
        Y = 99
        Width = 120
        Height = 140
      }
    },
    [pscustomobject]@{
      Id = 'picker-later-and-larger'
      Element = $null
      Bounds = [pscustomobject]@{
        X = 700
        Y = 220
        Width = 180
        Height = 180
      }
    }
  )
  $selectedDiagnosticCandidate = Select-PetMascotCandidate `
    -Candidates $diagnosticCandidates `
    -ReferenceBounds $referenceBounds
  [pscustomobject]@{
    selectedCandidate = $selectedDiagnosticCandidate.Id
    remountIdentityStable = (
      (
        Get-StableMascotIdentity `
          -Name 'Dewey pet' `
          -RuntimeId '42.100'
      ) -eq (
        Get-StableMascotIdentity `
          -Name 'Dewey pet' `
          -RuntimeId '42.200'
      )
    )
  } | ConvertTo-Json -Compress
  exit 0
}

function Start-QuotaProbe {
  param(
    [Parameter(Mandatory = $true)][string]$ProbeExecutable,
    [Parameter(Mandatory = $true)][string]$CodexExecutable,
    [Parameter(Mandatory = $true)][string]$TokenCachePath
  )

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $ProbeExecutable
  $startInfo.Arguments = (
    '--codex ' +
    (Quote-NativeArgument $CodexExecutable) +
    ' --token-cache ' +
    (Quote-NativeArgument $TokenCachePath)
  )
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  return $process
}

function Read-QuotaProbe {
  param([Parameter(Mandatory = $true)]$Process)

  if (-not $Process.HasExited) {
    return $null
  }

  $stdout = $Process.StandardOutput.ReadToEnd()
  $stderr = $Process.StandardError.ReadToEnd()
  $exitCode = $Process.ExitCode
  $Process.Dispose()

  if ($exitCode -ne 0) {
    $message = $stderr.Trim()
    $message = [regex]::Replace(
      $message,
      '(?:\x1B)?\[[0-9;?]*m',
      ''
    )
    if ([string]::IsNullOrWhiteSpace($message)) {
      $message = 'Quota probe failed.'
    }
    throw $message
  }

  return $stdout.Trim() | ConvertFrom-Json
}

function Get-WindowLabel {
  param($Bucket)

  $minutes = [double]$Bucket.windowDurationMins
  if ([math]::Abs($minutes - 300) -le 15) {
    return Get-UiText -Key 'FiveHourLimit'
  }
  if ([math]::Abs($minutes - 1440) -le 72) {
    return Get-UiText -Key 'DailyLimit'
  }
  if ([math]::Abs($minutes - 10080) -le 504) {
    return Get-UiText -Key 'WeeklyLimit'
  }
  if ($minutes -gt 0) {
    return Get-UiText -Key 'HourLimit' -Arguments @($minutes / 60)
  }
  return Get-UiText -Key 'UsageLimit'
}

function Format-ResetTime {
  param($UnixSeconds)

  if ($null -eq $UnixSeconds) {
    return Get-UiText -Key 'ResetUnavailable'
  }
  try {
    $time = [DateTimeOffset]::FromUnixTimeSeconds([long]$UnixSeconds).LocalDateTime
    $formatted = $time.ToString(
      (Get-UiText -Key 'ResetDateTimeFormat')
    )
    return Get-UiText -Key 'ResetsAt' -Arguments @($formatted)
  } catch {
    return Get-UiText -Key 'ResetUnavailable'
  }
}

function Format-TokenCount {
  param($TokenCount)

  if ($null -eq $TokenCount) {
    return '--'
  }
  $tokens = [double]$TokenCount
  if ($tokens -ge 1000000000) {
    return ('{0:0.00}B' -f ($tokens / 1000000000))
  }
  if ($tokens -ge 100000000) {
    return ('{0:0}M' -f ($tokens / 1000000))
  }
  if ($tokens -ge 10000000) {
    return ('{0:0.0}M' -f ($tokens / 1000000))
  }
  if ($tokens -ge 1000000) {
    return ('{0:0.00}M' -f ($tokens / 1000000))
  }
  if ($tokens -ge 1000) {
    return ('{0:0.0}K' -f ($tokens / 1000))
  }
  return [string][math]::Round($tokens)
}

function Set-RoundedRegion {
  param(
    [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control,
    [int]$Radius = 12
  )

  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $diameter = $Radius * 2
  $rect = New-Object System.Drawing.Rectangle 0, 0, $Control.Width, $Control.Height
  $path.AddArc($rect.Left, $rect.Top, $diameter, $diameter, 180, 90)
  $path.AddArc(
    $rect.Right - $diameter,
    $rect.Top,
    $diameter,
    $diameter,
    270,
    90
  )
  $path.AddArc(
    $rect.Right - $diameter,
    $rect.Bottom - $diameter,
    $diameter,
    $diameter,
    0,
    90
  )
  $path.AddArc(
    $rect.Left,
    $rect.Bottom - $diameter,
    $diameter,
    $diameter,
    90,
    90
  )
  $path.CloseFigure()
  $Control.Region = New-Object System.Drawing.Region $path
  $path.Dispose()
}

function Get-MonitorWorkArea {
  param([Parameter(Mandatory = $true)][IntPtr]$WindowHandle)

  if (
    $WindowHandle -eq [IntPtr]::Zero -or
    -not [CodexPetQuota.NativeMethods]::IsWindow($WindowHandle)
  ) {
    return $null
  }
  $monitor = [CodexPetQuota.NativeMethods]::MonitorFromWindow($WindowHandle, 2)
  if ($monitor -eq [IntPtr]::Zero) {
    return $null
  }
  $info = New-Object CodexPetQuota.NativeMethods+MONITORINFO
  $info.Size = [Runtime.InteropServices.Marshal]::SizeOf($info)
  if (-not [CodexPetQuota.NativeMethods]::GetMonitorInfo($monitor, [ref]$info)) {
    return $null
  }
  return $info.Work
}

$probeExecutable = Get-NativeProbeExecutable
$codexExecutable = Get-CodexExecutable
$projectRoot = Split-Path -Parent $PSScriptRoot
$configDirectory = if (
  [string]::IsNullOrWhiteSpace($ConfigDirectoryOverride)
) {
  Join-Path $env:LOCALAPPDATA 'CodexPetDock'
} else {
  [System.IO.Path]::GetFullPath($ConfigDirectoryOverride)
}
$configPath = Join-Path $configDirectory 'config.json'
$tokenCachePath = Join-Path $configDirectory 'token-usage-cache-v1.json'
$customThemesDirectory = Join-Path $configDirectory 'themes'
$welcomeMarkerPath = Join-Path $configDirectory 'welcome-0.3-shown'
$legacyConfigPath = Join-Path `
  (Join-Path $env:LOCALAPPDATA 'CodexPetQuota') `
  'config.json'
$script:themeCatalog = [ordered]@{
  'holo-cyan' = [pscustomobject]@{
    Name = 'Holo Cyan 3D'
    Asset = 'assets\tech-platform-v2.png'
    Width = 224
    Height = 72
    AnchorLift = 21
    ContactSurfaceY = 14
    ContactOverlap = 7
    ContentOffsetY = 0
    MetricsScrimOpacity = 48
    ContactShadow = $true
    ContactShadowY = 14
    Accent = [System.Drawing.Color]::FromArgb(210, 111, 232, 239)
  }
  'holo-amber' = [pscustomobject]@{
    Name = 'Holo Amber 3D'
    Asset = 'assets\tech-platform-amber.png'
    Width = 224
    Height = 72
    AnchorLift = 21
    ContactSurfaceY = 14
    ContactOverlap = 7
    ContentOffsetY = 0
    MetricsScrimOpacity = 48
    ContactShadow = $true
    ContactShadowY = 14
    Accent = [System.Drawing.Color]::FromArgb(220, 244, 194, 88)
  }
  'circuit-flat' = [pscustomobject]@{
    Name = 'Circuit Flat'
    Asset = 'assets\tech-platform.png'
    Width = 224
    Height = 64
    AnchorLift = 15
    ContactSurfaceY = 8
    ContactOverlap = 7
    ContentOffsetY = -6
    MetricsScrimOpacity = 56
    ContactShadow = $false
    ContactShadowY = 14
    Accent = [System.Drawing.Color]::FromArgb(210, 111, 232, 239)
  }
  'princess-cradle' = [pscustomobject]@{
    Name = 'Princess Cradle'
    Asset = 'assets\themes\princess-cradle.png'
    Width = 224
    Height = 72
    AnchorLift = 35
    ContactSurfaceY = 28
    ContactOverlap = 7
    ContentOffsetY = 6
    MetricsScrimOpacity = 162
    ContactShadow = $true
    ContactShadowY = 26
    Accent = [System.Drawing.Color]::FromArgb(224, 244, 174, 205)
  }
  'forest-rune' = [pscustomobject]@{
    Name = 'Forest Rune'
    Asset = 'assets\themes\forest-rune.png'
    Width = 224
    Height = 72
    AnchorLift = 36
    ContactSurfaceY = 29
    ContactOverlap = 7
    ContentOffsetY = 6
    MetricsScrimOpacity = 118
    ContactShadow = $true
    ContactShadowY = 27
    Accent = [System.Drawing.Color]::FromArgb(220, 94, 227, 213)
  }
  'clockwork-brass' = [pscustomobject]@{
    Name = 'Clockwork Brass'
    Asset = 'assets\themes\clockwork-brass.png'
    Width = 224
    Height = 72
    AnchorLift = 29
    ContactSurfaceY = 22
    ContactOverlap = 7
    ContentOffsetY = 6
    MetricsScrimOpacity = 112
    ContactShadow = $true
    ContactShadowY = 20
    Accent = [System.Drawing.Color]::FromArgb(224, 244, 184, 77)
  }
  'moon-lotus' = [pscustomobject]@{
    Name = 'Moon Lotus'
    Asset = 'assets\themes\moon-lotus.png'
    Width = 224
    Height = 72
    AnchorLift = 28
    ContactSurfaceY = 21
    ContactOverlap = 7
    ContentOffsetY = 6
    MetricsScrimOpacity = 148
    ContactShadow = $true
    ContactShadowY = 19
    Accent = [System.Drawing.Color]::FromArgb(220, 145, 229, 238)
  }
  'sakura-shrine' = [pscustomobject]@{
    Name = 'Sakura Shrine'
    Asset = 'assets\themes\sakura-shrine.png'
    Width = 224
    Height = 72
    AnchorLift = 35
    ContactSurfaceY = 28
    ContactOverlap = 7
    ContentOffsetY = 6
    MetricsScrimOpacity = 138
    ContactShadow = $true
    ContactShadowY = 25
    Accent = [System.Drawing.Color]::FromArgb(222, 246, 155, 164)
  }
  'iron-throne' = [pscustomobject]@{
    Name = 'Iron Throne'
    Asset = 'assets\themes\iron-throne.png'
    Width = 224
    Height = 96
    AnchorLift = 63
    ContactSurfaceY = 60
    ContactOverlap = 3
    ContentOffsetY = 30
    MetricsScrimOpacity = 112
    ContactShadow = $true
    ContactShadowY = 55
    CompactMetrics = $true
    Accent = [System.Drawing.Color]::FromArgb(224, 193, 76, 58)
  }
}
$script:builtInThemeIds = @(
  $script:themeCatalog.Keys |
    ForEach-Object { [string]$_ }
)

function Get-ManifestInteger {
  param(
    $Value,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][int]$Minimum,
    [Parameter(Mandatory = $true)][int]$Maximum
  )

  $numericValue = 0.0
  if (
    $null -eq $Value -or
    -not [double]::TryParse(
      [string]$Value,
      [Globalization.NumberStyles]::Integer,
      [Globalization.CultureInfo]::InvariantCulture,
      [ref]$numericValue
    ) -or
    $numericValue -lt $Minimum -or
    $numericValue -gt $Maximum
  ) {
    throw (
      $Name +
      ' must be an integer from ' +
      [string]$Minimum +
      ' to ' +
      [string]$Maximum +
      '.'
    )
  }
  return [int]$numericValue
}

function Convert-ThemeAccent {
  param([Parameter(Mandatory = $true)][string]$Value)

  if ($Value -notmatch '^#[0-9A-Fa-f]{6}$') {
    throw 'accent must use #RRGGBB.'
  }
  return [System.Drawing.Color]::FromArgb(
    220,
    [Convert]::ToInt32($Value.Substring(1, 2), 16),
    [Convert]::ToInt32($Value.Substring(3, 2), 16),
    [Convert]::ToInt32($Value.Substring(5, 2), 16)
  )
}

function Read-CustomThemeDefinition {
  param([Parameter(Mandatory = $true)][string]$ThemeDirectory)

  $resolvedDirectory = [System.IO.Path]::GetFullPath($ThemeDirectory)
  $resolvedRoot = [System.IO.Path]::GetFullPath($customThemesDirectory)
  if (-not $resolvedDirectory.StartsWith(
    $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw 'Theme directory escapes the custom theme root.'
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
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    return $null
  }
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
  $manifest = Get-Content `
    -Raw `
    -Encoding UTF8 `
    -LiteralPath $manifestPath |
      ConvertFrom-Json

  $allowedFields = @(
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
  $unknownFields = @(
    $manifest.PSObject.Properties.Name |
      Where-Object { $_ -notin $allowedFields }
  )
  if ($unknownFields.Count -gt 0) {
    throw 'Unsupported manifest fields: ' + ($unknownFields -join ', ')
  }
  if ([int]$manifest.schemaVersion -ne 1) {
    throw 'Only custom theme schemaVersion 1 is supported.'
  }

  $themeId = ([string]$manifest.id).Trim().ToLowerInvariant()
  if ($themeId -notmatch '^[a-z0-9][a-z0-9._-]{2,63}$') {
    throw 'Theme id must be 3-64 lowercase letters, digits, dot, dash, or underscore.'
  }
  if ($script:themeCatalog.Contains($themeId)) {
    throw 'Theme id conflicts with an existing theme.'
  }
  $themeName = ([string]$manifest.name).Trim()
  if (
    $themeName.Length -lt 1 -or
    $themeName.Length -gt 40 -or
    $themeName -match '[\x00-\x1F]'
  ) {
    throw 'Theme name must contain 1-40 display characters.'
  }

  $assetName = ([string]$manifest.asset).Trim()
  if (
    [System.IO.Path]::GetFileName($assetName) -ne $assetName -or
    [System.IO.Path]::GetExtension($assetName).ToLowerInvariant() -ne '.png'
  ) {
    throw 'asset must be one PNG file name in the theme directory.'
  }
  $assetPath = [System.IO.Path]::GetFullPath(
    (Join-Path $resolvedDirectory $assetName)
  )
  if (-not $assetPath.StartsWith(
    $resolvedDirectory + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw 'Theme asset escapes its directory.'
  }
  if (-not (Test-Path -LiteralPath $assetPath)) {
    throw 'Theme PNG was not found.'
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
  $sourceBitmap = New-Object System.Drawing.Bitmap $assetPath
  try {
    if (
      $sourceBitmap.Width -lt 64 -or
      $sourceBitmap.Height -lt 32 -or
      $sourceBitmap.Width -gt 4096 -or
      $sourceBitmap.Height -gt 4096
    ) {
      throw 'Theme PNG dimensions must be between 64x32 and 4096x4096.'
    }
  } finally {
    $sourceBitmap.Dispose()
  }

  $width = Get-ManifestInteger $manifest.width 'width' 160 320
  $height = Get-ManifestInteger $manifest.height 'height' 48 140
  $contactSurfaceY = Get-ManifestInteger `
    $manifest.contactSurfaceY `
    'contactSurfaceY' `
    0 `
    ($height - 8)
  $contactOverlap = Get-ManifestInteger `
    $manifest.contactOverlap `
    'contactOverlap' `
    0 `
    16
  if ($contactSurfaceY + $contactOverlap -gt $height - 4) {
    throw 'The contact surface and overlap exceed the theme height.'
  }
  $contentOffsetY = Get-ManifestInteger `
    $manifest.contentOffsetY `
    'contentOffsetY' `
    -12 `
    ($height - 48)
  $contactShadowY = Get-ManifestInteger `
    $manifest.contactShadowY `
    'contactShadowY' `
    0 `
    ($height - 11)
  $metricsScrimOpacity = Get-ManifestInteger `
    $manifest.metricsScrimOpacity `
    'metricsScrimOpacity' `
    0 `
    220
  $compactMetrics = $false
  if ($null -ne $manifest.compactMetrics) {
    if ($manifest.compactMetrics -isnot [bool]) {
      throw 'compactMetrics must be true or false.'
    }
    $compactMetrics = [bool]$manifest.compactMetrics
  }
  if ($manifest.contactShadow -isnot [bool]) {
    throw 'contactShadow must be true or false.'
  }
  $metricsBottom = (
    $(if ($compactMetrics) { 44 + 18 } else { 43 + 21 }) +
    $contentOffsetY
  )
  if ($metricsBottom -gt $height - 2) {
    throw 'Metric text would be clipped by the theme height.'
  }

  return [pscustomobject]@{
    Name = $themeName
    AssetPath = $assetPath
    Width = $width
    Height = $height
    AnchorLift = $contactSurfaceY + $contactOverlap
    ContactSurfaceY = $contactSurfaceY
    ContactOverlap = $contactOverlap
    ContentOffsetY = $contentOffsetY
    MetricsScrimOpacity = $metricsScrimOpacity
    ContactShadow = [bool]$manifest.contactShadow
    ContactShadowY = $contactShadowY
    CompactMetrics = $compactMetrics
    Accent = Convert-ThemeAccent ([string]$manifest.accent)
    IsCustom = $true
  }
}

function Initialize-CustomThemes {
  [void][System.IO.Directory]::CreateDirectory($customThemesDirectory)
  $exampleManifestPath = Join-Path `
    $customThemesDirectory `
    'theme.example.json'
  if (-not (Test-Path -LiteralPath $exampleManifestPath)) {
    [ordered]@{
      schemaVersion = 1
      id = 'your-name.theme-name'
      name = 'My Custom Base'
      asset = 'platform.png'
      width = 224
      height = 72
      contactSurfaceY = 20
      contactOverlap = 7
      contentOffsetY = 2
      contactShadow = $true
      contactShadowY = 18
      compactMetrics = $false
      metricsScrimOpacity = 120
      accent = '#6FE8EF'
    } |
      ConvertTo-Json |
      Set-Content `
        -LiteralPath $exampleManifestPath `
        -Encoding UTF8
  }

  foreach ($directory in @(
    Get-ChildItem `
      -LiteralPath $customThemesDirectory `
      -Directory `
      -ErrorAction SilentlyContinue
  )) {
    try {
      $definition = Read-CustomThemeDefinition `
        -ThemeDirectory $directory.FullName
      if ($null -ne $definition) {
        $manifest = Get-Content `
          -Raw `
          -Encoding UTF8 `
          -LiteralPath (Join-Path $directory.FullName 'theme.json') |
            ConvertFrom-Json
        $themeId = ([string]$manifest.id).Trim().ToLowerInvariant()
        $script:themeCatalog[$themeId] = $definition
      }
    } catch {
      Write-SidecarLog -Message (
        'Custom theme ignored (' +
        $directory.Name +
        '): ' +
        $_.Exception.Message
      )
    }
  }
}

function Reload-CustomThemeCatalog {
  foreach ($themeId in @($script:themeCatalog.Keys)) {
    $definition = $script:themeCatalog[[string]$themeId]
    if (
      $null -ne $definition.IsCustom -and
      [bool]$definition.IsCustom
    ) {
      $script:themeCatalog.Remove([string]$themeId)
    }
  }
  Initialize-CustomThemes
}

function Get-SavedPetQuotaConfig {
  $readPath = $configPath
  if (
    -not (Test-Path -LiteralPath $readPath) -and
    (Test-Path -LiteralPath $legacyConfigPath)
  ) {
    $readPath = $legacyConfigPath
  }
  if (-not (Test-Path -LiteralPath $readPath)) {
    return $null
  }
  try {
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $readPath |
      ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-SavedThemeId {
  $savedConfig = Get-SavedPetQuotaConfig
  if ($null -eq $savedConfig) {
    return $null
  }
  return [string]$savedConfig.theme
}

function Get-SavedLanguage {
  $savedConfig = Get-SavedPetQuotaConfig
  $savedLanguage = if ($null -ne $savedConfig) {
    [string]$savedConfig.language
  } else {
    ''
  }
  if ($savedLanguage -notin @('en-US', 'zh-CN')) {
    return 'en-US'
  }
  return $savedLanguage
}

function Save-PetQuotaConfig {
  param(
    [string]$ThemeId = '',
    [string]$UiLanguage = ''
  )

  if ([string]::IsNullOrWhiteSpace($ThemeId)) {
    $ThemeId = [string]$script:selectedThemeId
  }
  if ([string]::IsNullOrWhiteSpace($UiLanguage)) {
    $UiLanguage = [string]$script:uiLanguage
  }
  if ($UiLanguage -notin @('en-US', 'zh-CN')) {
    throw 'Unsupported UI language: ' + $UiLanguage
  }

  [void][System.IO.Directory]::CreateDirectory($configDirectory)
  $configJson = [ordered]@{
    version = 2
    theme = $ThemeId
    language = $UiLanguage
  } |
    ConvertTo-Json
  $temporaryConfigPath = $configPath + '.tmp'
  [System.IO.File]::WriteAllText(
    $temporaryConfigPath,
    $configJson,
    (New-Object System.Text.UTF8Encoding($false))
  )
  if (Test-Path -LiteralPath $configPath) {
    $backupConfigPath = $configPath + '.bak'
    if (Test-Path -LiteralPath $backupConfigPath) {
      [System.IO.File]::Delete($backupConfigPath)
    }
    [System.IO.File]::Replace(
      $temporaryConfigPath,
      $configPath,
      $backupConfigPath,
      $true
    )
    [System.IO.File]::Delete($backupConfigPath)
  } else {
    [System.IO.File]::Move($temporaryConfigPath, $configPath)
  }
}

function Write-SidecarLog {
  param([Parameter(Mandatory = $true)][string]$Message)

  try {
    [void][System.IO.Directory]::CreateDirectory($configDirectory)
    $logPath = Join-Path $configDirectory 'sidecar.log'
    $previousLogPath = Join-Path $configDirectory 'sidecar.previous.log'
    if (
      (Test-Path -LiteralPath $logPath) -and
      (Get-Item -LiteralPath $logPath).Length -ge 262144
    ) {
      if (Test-Path -LiteralPath $previousLogPath) {
        [System.IO.File]::Delete($previousLogPath)
      }
      [System.IO.File]::Move($logPath, $previousLogPath)
    }
    $logLine = (
      [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff') +
      '  ' +
      $Message.Replace([Environment]::NewLine, ' ') +
      [Environment]::NewLine
    )
    [System.IO.File]::AppendAllText(
      $logPath,
      $logLine,
      [System.Text.Encoding]::UTF8
    )
  } catch {
    # Logging must never turn a recoverable tracking race into a UI failure.
  }
}

[System.Windows.Forms.Application]::SetUnhandledExceptionMode(
  [System.Windows.Forms.UnhandledExceptionMode]::CatchException
)
[System.Windows.Forms.Application]::add_ThreadException({
  param($sender, $eventArgs)
  Write-SidecarLog -Message (
    'UI event recovered: ' + $eventArgs.Exception.Message
  )
})

$startupRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupValueName = 'CodexPetDock'

function Get-LaunchAtSignInEnabled {
  try {
    $value = Get-ItemPropertyValue `
      -LiteralPath $startupRegistryPath `
      -Name $startupValueName `
      -ErrorAction Stop
    return -not [string]::IsNullOrWhiteSpace([string]$value)
  } catch {
    return $false
  }
}

function Set-LaunchAtSignIn {
  param([Parameter(Mandatory = $true)][bool]$Enabled)

  if ($Enabled) {
    if (-not (Test-Path -LiteralPath $startupRegistryPath)) {
      [void](New-Item -Path $startupRegistryPath)
    }
    $powershellExecutable = Join-Path $PSHOME 'powershell.exe'
    $startupCommand = (
      '"' +
      $powershellExecutable +
      '" -NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' +
      $PSCommandPath +
      '"'
    )
    [void](New-ItemProperty `
      -Path $startupRegistryPath `
      -Name $startupValueName `
      -Value $startupCommand `
      -PropertyType String `
      -Force)
  } else {
    Remove-ItemProperty `
      -LiteralPath $startupRegistryPath `
      -Name $startupValueName `
      -ErrorAction SilentlyContinue
  }
}

Initialize-CustomThemes

$requestedLanguage = $Language.Trim()
$script:uiLanguage = if ([string]::IsNullOrWhiteSpace($requestedLanguage)) {
  Get-SavedLanguage
} else {
  $requestedLanguage
}

$script:selectedThemeId = $Theme.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($script:selectedThemeId)) {
  $script:selectedThemeId = (Get-SavedThemeId)
}
if (
  [string]::IsNullOrWhiteSpace($script:selectedThemeId) -or
  -not $script:themeCatalog.Contains($script:selectedThemeId)
) {
  if (-not [string]::IsNullOrWhiteSpace($Theme)) {
    throw (
      'Unknown theme "' +
      $Theme +
      '". Available themes: ' +
      (($script:themeCatalog.Keys | ForEach-Object { [string]$_ }) -join ', ')
    )
  }
  $script:selectedThemeId = 'holo-cyan'
}
$script:themeAnchorLift = 21

if ($Diagnostics) {
  $petWindow = Get-PetWindow
  $petMascotBounds = Get-PetMascotBounds -PetWindow $petWindow
  $probe = Start-QuotaProbe `
    -ProbeExecutable $probeExecutable `
    -CodexExecutable $codexExecutable `
    -TokenCachePath $tokenCachePath
  if (-not $probe.WaitForExit(20000)) {
    $probe.Kill()
    throw 'Quota diagnostics timed out.'
  }
  $quota = Read-QuotaProbe -Process $probe
  [pscustomobject]@{
    ok = $true
    codexExecutable = $codexExecutable
    selectedTheme = $script:selectedThemeId
    language = $script:uiLanguage
    availableThemes = @($script:themeCatalog.Keys)
    petWindow = $petWindow
    petMascotBounds = $petMascotBounds
    quota = $quota
  } | ConvertTo-Json -Depth 8
  exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$appIcon = $null
$appIconPath = Join-Path `
  $projectRoot `
  'assets\branding\codex-pet-dock.ico'
if (Test-Path -LiteralPath $appIconPath) {
  $appIcon = New-Object System.Drawing.Icon $appIconPath
}

$petBase = New-Object CodexPetQuota.NoActivateForm
$petBase.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$petBase.ShowInTaskbar = $false
$petBase.TopMost = $true
$petBase.BackColor = [System.Drawing.Color]::FromArgb(12, 16, 27)
$petBase.Opacity = 0.98
$petBase.Cursor = [System.Windows.Forms.Cursors]::Hand
if ($null -ne $appIcon) {
  $petBase.Icon = $appIcon
}

$petDragSurface = New-Object CodexPetQuota.MouseTransparentForm
$petDragSurface.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$petDragSurface.ShowInTaskbar = $false
$petDragSurface.TopMost = $true
$petDragSurface.BackColor = [System.Drawing.Color]::Black
# A one-percent layered surface remains hit-testable without producing a
# visible panel over the official animated pet.
$petDragSurface.Opacity = 0.01
$petDragSurface.Cursor = [System.Windows.Forms.Cursors]::SizeAll

$baseControl = New-Object CodexPetQuota.PetBaseControl
$baseControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$petBase.Controls.Add($baseControl)

$baseTexture = $null
$themeMenuItems = @{}

function Get-UnlockedThemeImage {
  param([Parameter(Mandatory = $true)][string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $stream = [System.IO.MemoryStream]::new($bytes, $false)
  try {
    $sourceImage = [System.Drawing.Image]::FromStream($stream)
    try {
      return New-Object System.Drawing.Bitmap $sourceImage
    } finally {
      $sourceImage.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Set-PetBaseTheme {
  param(
    [Parameter(Mandatory = $true)][string]$ThemeId,
    [switch]$Persist
  )

  if (-not $script:themeCatalog.Contains($ThemeId)) {
    throw 'Unknown pet base theme: ' + $ThemeId
  }
  $definition = $script:themeCatalog[$ThemeId]
  $texturePath = if (
    $null -ne $definition.AssetPath -and
    -not [string]::IsNullOrWhiteSpace([string]$definition.AssetPath)
  ) {
    [string]$definition.AssetPath
  } else {
    Join-Path $projectRoot ([string]$definition.Asset)
  }
  if (-not (Test-Path -LiteralPath $texturePath)) {
    throw 'Theme asset was not found: ' + $texturePath
  }

  $newTexture = Get-UnlockedThemeImage -Path $texturePath
  $oldTexture = $script:baseTexture
  $script:baseTexture = $newTexture
  $baseControl.BaseTexture = $newTexture
  $petBase.Size = New-Object System.Drawing.Size `
    ([int]$definition.Width), `
    ([int]$definition.Height)
  # Theme switches suspend WinForms layout to avoid intermediate paints.
  # Synchronize the docked child explicitly before deriving the Alpha region;
  # otherwise a 72px -> 96px theme keeps a 72px clipping region until resume.
  $baseControl.Size = New-Object System.Drawing.Size `
    ([int]$definition.Width), `
    ([int]$definition.Height)
  $baseControl.ContentOffsetY = [int]$definition.ContentOffsetY
  # The raised surface visually overlaps the pet's native drag area. Pet Dock
  # treats this part as a shared drag handle and moves the official pet window;
  # the lower metrics face remains a normal click target.
  $script:petDragTop = [math]::Max(
    0,
    [math]::Min(
      [int]$petBase.Height,
      31 + [int]$definition.ContentOffsetY
    )
  )
  $baseControl.MetricsScrimOpacity = if (
    $null -ne $definition.MetricsScrimOpacity
  ) {
    [int]$definition.MetricsScrimOpacity
  } else {
    60
  }
  $baseControl.CompactMetrics = (
    $null -ne $definition.CompactMetrics -and
    [bool]$definition.CompactMetrics
  )
  $baseControl.ShowContactShadow = [bool]$definition.ContactShadow
  $baseControl.ContactShadowY = [int]$definition.ContactShadowY
  $baseControl.HealthyAccent = $definition.Accent
  $baseControl.ApplyHostRegion($petBase)
  $script:themeAnchorLift = if (
    $null -ne $definition.ContactSurfaceY -and
    $null -ne $definition.ContactOverlap
  ) {
    [int]$definition.ContactSurfaceY + [int]$definition.ContactOverlap
  } else {
    [int]$definition.AnchorLift
  }
  $script:selectedThemeId = $ThemeId

  if ($null -ne $oldTexture) {
    $oldTexture.Dispose()
  }
  foreach ($itemId in @($script:themeMenuItems.Keys)) {
    $script:themeMenuItems[$itemId].Checked = ($itemId -eq $ThemeId)
  }
  if ($Persist) {
    Save-PetQuotaConfig -ThemeId $ThemeId
  }
}

function Align-PetBaseToCachedMascot {
  if (
    $null -eq $script:lastMascotBounds -or
    $null -eq $script:currentPetWindow -or
    -not $script:currentPetWindow.Visible
  ) {
    return
  }

  $targetLeft = (
    $script:lastMascotBounds.Left +
    [math]::Floor(
      ($script:lastMascotBounds.Width - $petBase.Width) / 2
    ) +
    $BaseOffsetX
  )
  $targetTop = (
    $script:lastMascotBounds.Top +
    $script:lastMascotBounds.Height -
    $script:themeAnchorLift +
    $BaseOffsetY
  )
  [void][CodexPetQuota.NativeMethods]::SetWindowPos(
    $petBase.Handle,
    [IntPtr]$script:currentPetWindow.Handle,
    $targetLeft,
    $targetTop,
    0,
    0,
    0x0011
  )
}

function Invoke-PetBaseThemeSwitch {
  param(
    [Parameter(Mandatory = $true)][string]$ThemeId,
    [switch]$Persist
  )

  if ($script:isApplyingTheme) {
    return $false
  }
  $script:isApplyingTheme = $true
  $previousThemeId = $script:selectedThemeId
  $redrawSuspended = $false
  try {
    [void][CodexPetQuota.NativeMethods]::SendMessage(
      $petBase.Handle,
      0x000B,
      [IntPtr]::Zero,
      [IntPtr]::Zero
    )
    $redrawSuspended = $true
    $petBase.SuspendLayout()
    $baseControl.SuspendLayout()
    Set-PetBaseTheme -ThemeId $ThemeId -Persist:$Persist
    Align-PetBaseToCachedMascot
    return $true
  } catch {
    Write-SidecarLog -Message (
      'Theme switch recovered: ' + $_.Exception.Message
    )
    if (
      -not [string]::IsNullOrWhiteSpace($previousThemeId) -and
      $script:selectedThemeId -ne $previousThemeId
    ) {
      try {
        Set-PetBaseTheme -ThemeId $previousThemeId
      } catch {
        Write-SidecarLog -Message (
          'Theme rollback failed: ' + $_.Exception.Message
        )
      }
    }
    return $false
  } finally {
    $baseControl.ResumeLayout($true)
    $petBase.ResumeLayout($true)
    if ($redrawSuspended) {
      [void][CodexPetQuota.NativeMethods]::SendMessage(
        $petBase.Handle,
        0x000B,
        [IntPtr]1,
        [IntPtr]::Zero
      )
    }
    $baseControl.Invalidate()
    $petBase.Refresh()
    $script:isApplyingTheme = $false
  }
}

Set-PetBaseTheme -ThemeId $script:selectedThemeId

$panel = New-Object CodexPetQuota.NoActivateForm
$panel.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$panel.ShowInTaskbar = $false
$panel.TopMost = $true
$panel.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 35)
$panel.Size = New-Object System.Drawing.Size 360, 150
$panel.Padding = New-Object System.Windows.Forms.Padding 16
$panel.Opacity = 0.985
if ($null -ne $appIcon) {
  $panel.Icon = $appIcon
}
Set-RoundedRegion -Control $panel -Radius 16

$panelTitle = New-Object System.Windows.Forms.Label
$panelTitle.Text = Get-UiText -Key 'PanelTitle'
$panelTitle.Location = New-Object System.Drawing.Point 16, 14
$panelTitle.Size = New-Object System.Drawing.Size 328, 24
$panelTitle.Font = [System.Drawing.Font]::new(
  'Segoe UI',
  15,
  [System.Drawing.FontStyle]::Bold,
  [System.Drawing.GraphicsUnit]::Pixel
)
$panelTitle.ForeColor = [System.Drawing.Color]::FromArgb(244, 246, 255)
$panel.Controls.Add($panelTitle)

$panelStatus = New-Object System.Windows.Forms.Label
$panelStatus.Text = Get-UiText -Key 'Loading'
$panelStatus.Location = New-Object System.Drawing.Point 16, 44
$panelStatus.Size = New-Object System.Drawing.Size 328, 50
$panelStatus.Font = [System.Drawing.Font]::new(
  'Segoe UI',
  12,
  [System.Drawing.FontStyle]::Regular,
  [System.Drawing.GraphicsUnit]::Pixel
)
$panelStatus.ForeColor = [System.Drawing.Color]::FromArgb(166, 174, 197)
$panel.Controls.Add($panelStatus)

$quotaBars = New-Object System.Collections.Generic.List[System.Windows.Forms.Control]
$latestQuota = $null
$latestError = $null
$probeProcess = $null
$lastProbeStartedAt = [DateTime]::MinValue
$nextAutomaticProbeAt = [DateTime]::MinValue
$probeFailureCount = 0
$probeFailureBaseSeconds = 15
$probeFailureMaxSeconds = 300
$networkAvailable = $true
$lastNetworkAvailable = $null
$lastNetworkCheckAt = [DateTime]::MinValue
$networkCheckIntervalSeconds = 2
$startedAt = [DateTime]::Now
$currentPetWindow = $null
$petWindowDrag = $null
$petPointerDrag = $null
$petPointerWasDown = $false
$lastPetVisibleAt = [DateTime]::MinValue
$lastPetSearchAt = [DateTime]::MinValue
$officialCodexProcessIds = $null
$officialCodexProcessIdsReadAt = [DateTime]::MinValue
$mascotAutomationElement = $null
$mascotAutomationRoot = $null
$mascotAutomationHandle = 0
$mascotAutomationLookupAt = [DateTime]::MinValue
$mascotAutomationIdentity = ''
$lastMascotBounds = $null
$lastMascotSeenAt = [DateTime]::MinValue
$lastMascotSignature = ''
$fastTrackingUntil = [DateTime]::MinValue
$baseIsSettling = $false
$lastBaseTargetSignature = ''
$lastBaseZOrderAt = [DateTime]::MinValue
$lastPetDragSurfaceSignature = ''
$lastPetDragSurfaceZOrderAt = [DateTime]::MinValue
$snapDockToMascotAtNextFrame = $false
$isExiting = $false
$lastTrayStatusKey = ''

function Get-QuotaFreshness {
  if (
    $null -eq $script:latestQuota -or
    [string]::IsNullOrWhiteSpace([string]$script:latestQuota.capturedAt)
  ) {
    return [pscustomobject]@{
      IsStale = $true
      AgeSeconds = $null
      Label = Get-UiText -Key 'NoData'
      CapturedAt = $null
    }
  }

  try {
    $capturedAt = [DateTimeOffset]::Parse(
      [string]$script:latestQuota.capturedAt,
      [Globalization.CultureInfo]::InvariantCulture
    ).LocalDateTime
    $ageSeconds = [math]::Max(
      0,
      [int][math]::Round(([DateTime]::Now - $capturedAt).TotalSeconds)
    )
    $staleAfterSeconds = [math]::Max(600, $RefreshSeconds * 2)
    $ageLabel = if ($ageSeconds -lt 60) {
      Get-UiText -Key 'SecondsAgo' -Arguments @($ageSeconds)
    } elseif ($ageSeconds -lt 3600) {
      Get-UiText `
        -Key 'MinutesAgo' `
        -Arguments @([math]::Floor($ageSeconds / 60))
    } else {
      Get-UiText `
        -Key 'HoursAgo' `
        -Arguments @([math]::Floor($ageSeconds / 3600))
    }
    return [pscustomobject]@{
      IsStale = ($ageSeconds -ge $staleAfterSeconds)
      AgeSeconds = $ageSeconds
      Label = $ageLabel
      CapturedAt = $capturedAt
    }
  } catch {
    return [pscustomobject]@{
      IsStale = $true
      AgeSeconds = $null
      Label = Get-UiText -Key 'InvalidTime'
      CapturedAt = $null
    }
  }
}

function Set-MeasuredLabelHeight {
  param(
    [Parameter(Mandatory = $true)]
    [System.Windows.Forms.Label]$Label,
    [int]$MinimumHeight = 18,
    [int]$BottomPadding = 4
  )

  $flags = (
    [System.Windows.Forms.TextFormatFlags]::TextBoxControl -bor
    [System.Windows.Forms.TextFormatFlags]::WordBreak -bor
    [System.Windows.Forms.TextFormatFlags]::NoPrefix
  )
  $measured = [System.Windows.Forms.TextRenderer]::MeasureText(
    $Label.Text,
    $Label.Font,
    (New-Object System.Drawing.Size $Label.Width, 4096),
    $flags
  )
  $Label.Height = [math]::Max(
    $MinimumHeight,
    [int]$measured.Height + $BottomPadding
  )
  return [int]$Label.Height
}

function Update-QuotaUi {
  foreach ($bar in $quotaBars) {
    $panel.Controls.Remove($bar)
    $bar.Dispose()
  }
  $quotaBars.Clear()
  $baseControl.TokenHeader = Get-UiText -Key 'WeekTokens'

  if ($null -ne $latestError) {
    $baseControl.State = 2
    $baseControl.WindowCode = Get-UiText -Key 'Offline'
    $baseControl.ResetDate = Get-UiText -Key 'Retry'
    $baseControl.ResetTime = Get-UiText -Key 'ClickBase'
    $baseControl.TokenLabel = '--'
    $panelStatus.Text = $latestError
    $panelStatus.Visible = $true
    $panel.Height = 126
    Set-RoundedRegion -Control $panel -Radius 16
    return
  }

  if ($null -eq $latestQuota) {
    $baseControl.State = 0
    $baseControl.WindowCode = Get-UiText -Key 'Limit'
    $baseControl.ResetDate = '--'
    $baseControl.ResetTime = '--:--'
    $baseControl.TokenLabel = '--'
    $panelStatus.Text = Get-UiText -Key 'Loading'
    $panelStatus.Visible = $true
    return
  }

  $buckets = @($latestQuota.buckets)
  $remainingValues = @(
    $buckets |
      Where-Object { $null -ne $_.remainingPercent } |
      ForEach-Object { [int][math]::Round([double]$_.remainingPercent) }
  )
  $baseControl.State = 1
  if ($remainingValues.Count -gt 0) {
    $baseControl.Remaining = [int](($remainingValues | Measure-Object -Minimum).Minimum)
  } else {
    $baseControl.State = 0
  }

  $baseBucket = @(
    $buckets |
      Where-Object { $null -ne $_.remainingPercent } |
      Sort-Object { [double]$_.remainingPercent }
  ) | Select-Object -First 1
  if ($null -ne $baseBucket) {
    $windowMinutes = [double]$baseBucket.windowDurationMins
    if ([math]::Abs($windowMinutes - 300) -le 15) {
      $baseControl.WindowCode = Get-UiText -Key 'FiveHourLeft'
    } elseif ([math]::Abs($windowMinutes - 1440) -le 72) {
      $baseControl.WindowCode = Get-UiText -Key 'DayLeft'
    } elseif ([math]::Abs($windowMinutes - 10080) -le 504) {
      $baseControl.WindowCode = Get-UiText -Key 'WeekLeft'
    } else {
      $baseControl.WindowCode = Get-UiText -Key 'LimitLeft'
    }

    try {
      $baseReset = [DateTimeOffset]::FromUnixTimeSeconds(
        [long]$baseBucket.resetsAt
      ).LocalDateTime
      $baseControl.ResetDate = $baseReset.ToString(
        (Get-UiText -Key 'ResetDateFormat')
      ).ToUpperInvariant()
      $baseControl.ResetTime = $baseReset.ToString('HH:mm')
    } catch {
      $baseControl.ResetDate = Get-UiText -Key 'Unknown'
      $baseControl.ResetTime = '--:--'
    }
  }
  $baseControl.PlanCode = ([string]$latestQuota.planType).ToUpperInvariant()
  $baseControl.TokenLabel = Format-TokenCount `
    -TokenCount $latestQuota.tokenStats.weeklyTokens
  $freshness = Get-QuotaFreshness
  if ($freshness.IsStale) {
    $baseControl.State = 0
    $baseControl.WindowCode = Get-UiText -Key 'StaleData'
  }

  $panelStatus.Visible = $false
  $top = 44
  foreach ($bucket in $buckets) {
    $bar = New-Object CodexPetQuota.QuotaBar
    $bar.Tag = 'quota-bucket'
    $bar.Location = New-Object System.Drawing.Point 16, $top
    $bar.Width = 328
    $bar.Caption = Get-WindowLabel -Bucket $bucket
    $bar.Value = [int][math]::Round([double]$bucket.remainingPercent)
    $bar.Detail = Get-UiText `
      -Key 'PercentLeft' `
      -Arguments @(
        [string]$bar.Value,
        (Format-ResetTime -UnixSeconds $bucket.resetsAt)
      )
    $panel.Controls.Add($bar)
    $quotaBars.Add($bar)
    $top += 66
  }

  if ($buckets.Count -eq 0) {
    $panelStatus.Text = Get-UiText -Key 'NoActiveWindow'
    $panelStatus.Visible = $true
    $top = 96
  }

  if ($null -ne $latestQuota.tokenStats.weeklyTokens) {
    $tokenHeaderLabel = New-Object System.Windows.Forms.Label
    $tokenHeaderLabel.Tag = 'token-header'
    $tokenHeaderLabel.Location = New-Object System.Drawing.Point 16, $top
    $tokenHeaderLabel.Size = New-Object System.Drawing.Size 328, 20
    $tokenHeaderLabel.Font = [System.Drawing.Font]::new(
      'Segoe UI Semibold',
      12,
      [System.Drawing.FontStyle]::Regular,
      [System.Drawing.GraphicsUnit]::Pixel
    )
    $tokenHeaderLabel.ForeColor = [System.Drawing.Color]::FromArgb(
      205,
      218,
      240
    )
    $tokenHeaderLabel.Text = Get-UiText `
      -Key 'LocalWeekTokens' `
      -Arguments @(
        ([long]$latestQuota.tokenStats.weeklyTokens).ToString('N0')
      )
    $tokenHeaderHeight = Set-MeasuredLabelHeight `
      -Label $tokenHeaderLabel `
      -MinimumHeight 18 `
      -BottomPadding 2
    $panel.Controls.Add($tokenHeaderLabel)
    $quotaBars.Add($tokenHeaderLabel)
    $top += $tokenHeaderHeight

    $tokenDetailLabel = New-Object System.Windows.Forms.Label
    $tokenDetailLabel.Tag = 'token-detail'
    $tokenDetailLabel.Location = New-Object System.Drawing.Point 16, $top
    $tokenDetailLabel.Size = New-Object System.Drawing.Size 328, 38
    $tokenDetailLabel.Font = [System.Drawing.Font]::new(
      'Segoe UI',
      11,
      [System.Drawing.FontStyle]::Regular,
      [System.Drawing.GraphicsUnit]::Pixel
    )
    $tokenDetailLabel.ForeColor = [System.Drawing.Color]::FromArgb(
      166,
      181,
      207
    )
    $tokenDetailLabel.Text = Get-UiText `
      -Key 'TokenDetails' `
      -Arguments @(
        ([double]$latestQuota.tokenStats.cachedPercent).ToString('0.0'),
        (Format-TokenCount -TokenCount $latestQuota.tokenStats.freshInputTokens),
        (Format-TokenCount -TokenCount $latestQuota.tokenStats.outputTokens),
        [Environment]::NewLine,
        [string]$latestQuota.tokenStats.scannedSessions
      )
    $tokenDetailHeight = Set-MeasuredLabelHeight `
      -Label $tokenDetailLabel `
      -MinimumHeight 30 `
      -BottomPadding 3
    $panel.Controls.Add($tokenDetailLabel)
    $quotaBars.Add($tokenDetailLabel)
    $top += $tokenDetailHeight + 6
  }

  if ([int]$latestQuota.resetCreditsAvailable -gt 0) {
    $resetLabel = New-Object System.Windows.Forms.Label
    $resetLabel.Tag = 'reset-credits'
    $resetLabel.Location = New-Object System.Drawing.Point 16, $top
    $resetLabel.Size = New-Object System.Drawing.Size 328, 24
    $resetLabel.Font = [System.Drawing.Font]::new(
      'Segoe UI',
      11,
      [System.Drawing.FontStyle]::Regular,
      [System.Drawing.GraphicsUnit]::Pixel
    )
    $resetLabel.ForeColor = [System.Drawing.Color]::FromArgb(166, 174, 197)
    $resetLabel.Text = Get-UiText `
      -Key 'AvailableResets' `
      -Arguments @([string]$latestQuota.resetCreditsAvailable)
    $resetLabelHeight = Set-MeasuredLabelHeight `
      -Label $resetLabel `
      -MinimumHeight 18 `
      -BottomPadding 2
    $panel.Controls.Add($resetLabel)
    $quotaBars.Add($resetLabel)
    $top += $resetLabelHeight + 6
  }

  $freshnessLabel = New-Object System.Windows.Forms.Label
  $freshnessLabel.Tag = 'freshness'
  $freshnessLabel.Location = New-Object System.Drawing.Point 16, $top
  $freshnessLabel.Size = New-Object System.Drawing.Size 328, 22
  $freshnessLabel.Font = [System.Drawing.Font]::new(
    'Segoe UI Semibold',
    11,
    [System.Drawing.FontStyle]::Regular,
    [System.Drawing.GraphicsUnit]::Pixel
  )
  $freshnessLabel.ForeColor = if ($freshness.IsStale) {
    [System.Drawing.Color]::FromArgb(245, 184, 87)
  } else {
    [System.Drawing.Color]::FromArgb(111, 232, 188)
  }
  $freshnessLabel.Text = if ($freshness.IsStale) {
    Get-UiText -Key 'StaleUpdated' -Arguments @([string]$freshness.Label)
  } else {
    Get-UiText -Key 'LiveUpdated' -Arguments @([string]$freshness.Label)
  }
  $freshnessHeight = Set-MeasuredLabelHeight `
    -Label $freshnessLabel `
    -MinimumHeight 18 `
    -BottomPadding 2
  $panel.Controls.Add($freshnessLabel)
  $quotaBars.Add($freshnessLabel)
  $top += $freshnessHeight + 6

  $capturedAt = $freshness.CapturedAt
  $planLabel = ''
  if (-not [string]::IsNullOrWhiteSpace([string]$latestQuota.planType)) {
    $planLabel = (
      ' - ' +
      ([string]$latestQuota.planType).ToUpperInvariant()
    )
  }
  $panelTitle.Text = (
    (Get-UiText -Key 'PanelTitle') +
    $planLabel +
    ' - ' +
    $(if ($null -ne $capturedAt) {
      $capturedAt.ToString('HH:mm:ss')
    } else {
      Get-UiText -Key 'Unknown'
    })
  )
  $panel.Height = [math]::Max(118, $top + 18)
  Set-RoundedRegion -Control $panel -Radius 16
}

if ($PanelLayoutDiagnostics) {
  $script:latestQuota = [pscustomobject]@{
    capturedAt = [DateTimeOffset]::Now.ToString('O')
    planType = 'pro'
    resetCreditsAvailable = 0
    buckets = @(
      [pscustomobject]@{
        name = 'weekly'
        windowDurationMins = 10080
        remainingPercent = 81
        resetsAt = [DateTimeOffset]::Now.AddDays(6).ToUnixTimeSeconds()
      }
    )
    tokenStats = [pscustomobject]@{
      weeklyTokens = 681764431
      cachedPercent = 95.3
      freshInputTokens = 31870000
      outputTokens = 2720000
      scannedSessions = 30
    }
  }
  Update-QuotaUi
  $flags = (
    [System.Windows.Forms.TextFormatFlags]::TextBoxControl -bor
    [System.Windows.Forms.TextFormatFlags]::WordBreak -bor
    [System.Windows.Forms.TextFormatFlags]::NoPrefix
  )
  $layoutControls = @(
    $panel.Controls |
      Where-Object { $_ -ne $panelStatus } |
      Sort-Object Top |
      ForEach-Object {
        $textFits = $true
        $measuredHeight = $null
        if ($_ -is [System.Windows.Forms.Label]) {
          $measured = [System.Windows.Forms.TextRenderer]::MeasureText(
            $_.Text,
            $_.Font,
            (New-Object System.Drawing.Size $_.Width, 4096),
            $flags
          )
          $measuredHeight = [int]$measured.Height
          $textFits = ($measuredHeight -le $_.Height)
        }
        [pscustomobject]@{
          tag = [string]$_.Tag
          type = $_.GetType().Name
          text = [string]$_.Text
          top = [int]$_.Top
          height = [int]$_.Height
          bottom = [int]$_.Bottom
          measuredTextHeight = $measuredHeight
          textFits = $textFits
          insidePanel = ($_.Bottom -le $panel.ClientSize.Height)
        }
      }
  )
  $orderedContent = @(
    $layoutControls |
      Where-Object { $_.tag -in @(
        'quota-bucket',
        'token-header',
        'token-detail',
        'reset-credits',
        'freshness'
      ) }
  )
  $overlapCount = 0
  for ($layoutIndex = 1; $layoutIndex -lt $orderedContent.Count; $layoutIndex++) {
    if (
      [int]$orderedContent[$layoutIndex].top -lt
      [int]$orderedContent[$layoutIndex - 1].bottom
    ) {
      $overlapCount += 1
    }
  }
  [pscustomobject]@{
    ok = (
      @(
        $layoutControls |
          Where-Object { -not $_.textFits -or -not $_.insidePanel }
      ).Count -eq 0 -and
      $overlapCount -eq 0 -and
      $baseControl.MetricsFontFits
    )
    language = $script:uiLanguage
    panelWidth = [int]$panel.ClientSize.Width
    panelHeight = [int]$panel.ClientSize.Height
    overlapCount = $overlapCount
    baseLeftHeader = [string]$baseControl.WindowCode
    baseRightHeader = [string]$baseControl.TokenHeader
    baseMetricsFontFits = [bool]$baseControl.MetricsFontFits
    controls = $layoutControls
  } | ConvertTo-Json -Depth 5
  $petBase.Dispose()
  $petDragSurface.Dispose()
  if ($null -ne $baseTexture) {
    $baseTexture.Dispose()
  }
  $panel.Dispose()
  if ($null -ne $appIcon) {
    $appIcon.Dispose()
  }
  exit 0
}

function Begin-QuotaRefresh {
  if (
    $null -ne $script:probeProcess -and
    -not $script:probeProcess.HasExited
  ) {
    return
  }
  $script:latestError = $null
  $script:probeProcess = Start-QuotaProbe `
    -ProbeExecutable $probeExecutable `
    -CodexExecutable $codexExecutable `
    -TokenCachePath $tokenCachePath
  $script:lastProbeStartedAt = [DateTime]::Now
  $script:nextAutomaticProbeAt = (
    $script:lastProbeStartedAt.AddSeconds($RefreshSeconds)
  )
}

function Update-NetworkRecoveryState {
  if (
    (
      [DateTime]::Now - $script:lastNetworkCheckAt
    ).TotalSeconds -lt $script:networkCheckIntervalSeconds
  ) {
    return
  }

  $script:lastNetworkCheckAt = [DateTime]::Now
  $isAvailable = $true
  try {
    $isAvailable = (
      [System.Net.NetworkInformation.NetworkInterface]::
        GetIsNetworkAvailable()
    )
  } catch {
    # If Windows cannot report link state, keep retries enabled. The quota
    # probe remains the authoritative connectivity check.
    $isAvailable = $true
  }

  if (
    $null -ne $script:lastNetworkAvailable -and
    -not [bool]$script:lastNetworkAvailable -and
    $isAvailable
  ) {
    $script:probeFailureCount = 0
    $script:nextAutomaticProbeAt = [DateTime]::Now
    Write-SidecarLog -Message (
      'Network link restored; quota refresh scheduled immediately.'
    )
  }

  $script:networkAvailable = [bool]$isAvailable
  $script:lastNetworkAvailable = [bool]$isAvailable
}

function Stop-QuotaRefresh {
  if ($null -eq $script:probeProcess) {
    return
  }
  try {
    if (-not $script:probeProcess.HasExited) {
      $script:probeProcess.Kill()
      [void]$script:probeProcess.WaitForExit(1000)
    }
  } catch {
    Write-SidecarLog -Message (
      'Quota probe stop recovered: ' + $_.Exception.Message
    )
  } finally {
    $script:probeProcess.Dispose()
    $script:probeProcess = $null
  }
}

function Toggle-QuotaPanel {
  if ($panel.Visible) {
    $panel.Hide()
  } elseif (
    $null -ne $currentPetWindow -and
    $currentPetWindow.Visible
  ) {
    $panel.Show()
    $quotaFreshness = Get-QuotaFreshness
    if (
      $null -eq $script:probeProcess -and
      (
        $null -eq $quotaFreshness.AgeSeconds -or
        [int]$quotaFreshness.AgeSeconds -ge 300
      ) -and
      ([DateTime]::Now - $script:lastProbeStartedAt).TotalSeconds -ge 60
    ) {
      Begin-QuotaRefresh
    }
  }
}

function Start-PetWindowDrag {
  param(
    $sender,
    $eventArgs,
    [switch]$FromMascotSurface
  )

  if (
    $eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left -or
    (
      -not $FromMascotSurface -and
      [int]$eventArgs.Y -ge [int]$script:petDragTop
    ) -or
    $null -eq $script:currentPetWindow -or
    -not $script:currentPetWindow.Visible
  ) {
    return
  }
  $petHandle = [IntPtr]$script:currentPetWindow.Handle
  if (-not [CodexPetQuota.NativeMethods]::IsWindow($petHandle)) {
    return
  }

  $petRect = New-Object CodexPetQuota.NativeMethods+RECT
  if (-not [CodexPetQuota.NativeMethods]::GetWindowRect(
    $petHandle,
    [ref]$petRect
  )) {
    return
  }

  $panel.Hide()
  $script:petWindowDrag = [pscustomobject]@{
    Handle = $petHandle
    CursorX = [System.Windows.Forms.Cursor]::Position.X
    CursorY = [System.Windows.Forms.Cursor]::Position.Y
    WindowLeft = [int]$petRect.Left
    WindowTop = [int]$petRect.Top
    WindowWidth = [int]($petRect.Right - $petRect.Left)
    WindowHeight = [int]($petRect.Bottom - $petRect.Top)
    BaseLeft = [int]$petBase.Left
    BaseTop = [int]$petBase.Top
    SurfaceLeft = [int]$petDragSurface.Left
    SurfaceTop = [int]$petDragSurface.Top
    CaptureControl = $sender
    Moved = $false
  }
  $sender.Capture = $true
}

function Move-PetWindowDrag {
  param($sender, $eventArgs)

  if (
    $null -eq $script:petWindowDrag -or
    $eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left
  ) {
    return
  }
  $cursor = [System.Windows.Forms.Cursor]::Position
  $deltaX = [int]$cursor.X - [int]$script:petWindowDrag.CursorX
  $deltaY = [int]$cursor.Y - [int]$script:petWindowDrag.CursorY
  if ($deltaX -eq 0 -and $deltaY -eq 0) {
    return
  }

  $newLeft = [int]$script:petWindowDrag.WindowLeft + $deltaX
  $newTop = [int]$script:petWindowDrag.WindowTop + $deltaY
  [void][CodexPetQuota.NativeMethods]::SetWindowPos(
    [IntPtr]$script:petWindowDrag.Handle,
    [IntPtr]::Zero,
    $newLeft,
    $newTop,
    0,
    0,
    0x0015
  )
  if ($petBase.Visible) {
    [void][CodexPetQuota.NativeMethods]::SetWindowPos(
      $petBase.Handle,
      [IntPtr]$script:petWindowDrag.Handle,
      ([int]$script:petWindowDrag.BaseLeft + $deltaX),
      ([int]$script:petWindowDrag.BaseTop + $deltaY),
      0,
      0,
      0x0011
    )
  }
  if ($petDragSurface.Visible) {
    [void][CodexPetQuota.NativeMethods]::SetWindowPos(
      $petDragSurface.Handle,
      [IntPtr](-1),
      ([int]$script:petWindowDrag.SurfaceLeft + $deltaX),
      ([int]$script:petWindowDrag.SurfaceTop + $deltaY),
      0,
      0,
      0x0011
    )
  }
  $script:petWindowDrag.Moved = $true
  Extend-FastTracking -Milliseconds 1200
}

function Stop-PetWindowDrag {
  if ($null -eq $script:petWindowDrag) {
    return
  }
  $captureControl = $script:petWindowDrag.CaptureControl
  $script:petWindowDrag = $null
  if ($null -ne $captureControl) {
    $captureControl.Capture = $false
  }
}

function Test-PetPointerDragPoint {
  param($Point, $Bounds)

  $left = [int]$Bounds.Left
  $top = [int]$Bounds.Top
  $width = [math]::Max(1, [int]$Bounds.Width)
  $height = [math]::Max(1, [int]$Bounds.Height)
  if (
    [int]$Point.X -lt $left -or
    [int]$Point.X -ge $left + $width -or
    [int]$Point.Y -lt $top -or
    [int]$Point.Y -ge $top + $height
  ) {
    return $false
  }
  $protectedTop = $top + [int][math]::Floor($height * 0.72)
  $protectedHalfWidth = [math]::Max(
    22,
    [int][math]::Ceiling($width * 0.23)
  )
  $centerX = $left + [int][math]::Floor($width / 2)
  return -not (
    [int]$Point.Y -ge $protectedTop -and
    [int]$Point.X -ge $centerX - $protectedHalfWidth -and
    [int]$Point.X -le $centerX + $protectedHalfWidth
  )
}

function Update-PetPointerDrag {
  param(
    [bool]$LeftButtonDown,
    $MascotBounds
  )

  if (-not $LeftButtonDown) {
    $script:petPointerDrag = $null
    $script:petPointerWasDown = $false
    return
  }
  if (
    $null -eq $script:currentPetWindow -or
    $null -eq $MascotBounds
  ) {
    $script:petPointerWasDown = $true
    return
  }

  $cursor = [System.Windows.Forms.Cursor]::Position
  if ($null -eq $script:petPointerDrag) {
    if ($script:petPointerWasDown) {
      return
    }
    $script:petPointerWasDown = $true
    if (
      -not (Test-PetPointerDragPoint -Point $cursor -Bounds $MascotBounds)
    ) {
      return
    }
    $petHandle = [IntPtr]$script:currentPetWindow.Handle
    $petRect = New-Object CodexPetQuota.NativeMethods+RECT
    if (
      -not [CodexPetQuota.NativeMethods]::IsWindow($petHandle) -or
      -not [CodexPetQuota.NativeMethods]::GetWindowRect(
        $petHandle,
        [ref]$petRect
      )
    ) {
      return
    }
    $script:petPointerDrag = [pscustomobject]@{
      Handle = $petHandle
      CursorX = [int]$cursor.X
      CursorY = [int]$cursor.Y
      PetLeft = [int]$petRect.Left
      PetTop = [int]$petRect.Top
      BaseLeft = [int]$petBase.Left
      BaseTop = [int]$petBase.Top
      SurfaceLeft = [int]$petDragSurface.Left
      SurfaceTop = [int]$petDragSurface.Top
      Active = $false
    }
    Extend-FastTracking -Milliseconds 800
    return
  }

  $deltaX = [int]$cursor.X - [int]$script:petPointerDrag.CursorX
  $deltaY = [int]$cursor.Y - [int]$script:petPointerDrag.CursorY
  if (
    -not $script:petPointerDrag.Active -and
    [math]::Max([math]::Abs($deltaX), [math]::Abs($deltaY)) -lt 4
  ) {
    return
  }
  $script:petPointerDrag.Active = $true
  $panel.Hide()
  [void][CodexPetQuota.NativeMethods]::SetWindowPos(
    [IntPtr]$script:petPointerDrag.Handle,
    [IntPtr]::Zero,
    ([int]$script:petPointerDrag.PetLeft + $deltaX),
    ([int]$script:petPointerDrag.PetTop + $deltaY),
    0,
    0,
    0x0015
  )
  [void][CodexPetQuota.NativeMethods]::SetWindowPos(
    $petBase.Handle,
    [IntPtr]$script:petPointerDrag.Handle,
    ([int]$script:petPointerDrag.BaseLeft + $deltaX),
    ([int]$script:petPointerDrag.BaseTop + $deltaY),
    0,
    0,
    0x0011
  )
  Extend-FastTracking -Milliseconds 1200
}

function Hide-PetDragSurface {
  if (
    $null -ne $script:petWindowDrag -and
    $script:petWindowDrag.CaptureControl -eq $petDragSurface
  ) {
    Stop-PetWindowDrag
  }
  if ($petDragSurface.Visible) {
    $petDragSurface.Hide()
  }
  $script:lastPetDragSurfaceSignature = ''
}

function Update-PetDragSurface {
  param([Parameter(Mandatory = $true)]$MascotBounds)

  $left = [int]$MascotBounds.Left
  $top = [int]$MascotBounds.Top
  $width = [math]::Max(40, [int]$MascotBounds.Width)
  $height = [math]::Max(40, [int]$MascotBounds.Height)
  $signature = (
    [string]$left + ',' +
    [string]$top + ',' +
    [string]$width + ',' +
    [string]$height
  )
  $geometryChanged = (
    $signature -ne $script:lastPetDragSurfaceSignature
  )
  if ($geometryChanged) {
    $protectedTop = [int][math]::Floor($height * 0.72)
    $protectedHalfWidth = [math]::Max(
      22,
      [int][math]::Ceiling($width * 0.23)
    )
    $protectedLeft = [math]::Max(
      0,
      [int][math]::Floor($width / 2) - $protectedHalfWidth
    )
    $protectedWidth = [math]::Min(
      $width - $protectedLeft,
      $protectedHalfWidth * 2
    )
    $surfaceRegion = New-Object System.Drawing.Region (
      New-Object System.Drawing.Rectangle 0, 0, $width, $height
    )
    $surfaceRegion.Exclude(
      (
        New-Object System.Drawing.Rectangle `
          $protectedLeft, `
          $protectedTop, `
          $protectedWidth, `
          ($height - $protectedTop)
      )
    )
    $oldRegion = $petDragSurface.Region
    $petDragSurface.Region = $surfaceRegion
    if ($null -ne $oldRegion) {
      $oldRegion.Dispose()
    }
    $petDragSurface.Bounds = New-Object System.Drawing.Rectangle `
      $left, `
      $top, `
      $width, `
      $height
    $script:lastPetDragSurfaceSignature = $signature
  }

  if (-not $petDragSurface.Visible) {
    $petDragSurface.Show()
  }
  $zOrderDue = (
    [DateTime]::Now - $script:lastPetDragSurfaceZOrderAt
  ).TotalMilliseconds -ge 500
  if (
    $geometryChanged -or
    $zOrderDue
  ) {
    [void][CodexPetQuota.NativeMethods]::SetWindowPos(
      $petDragSurface.Handle,
      [IntPtr](-1),
      $left,
      $top,
      $width,
      $height,
      0x0010
    )
    $script:lastPetDragSurfaceZOrderAt = [DateTime]::Now
  }
}

function Complete-PetBaseMouseUp {
  param($sender, $eventArgs)

  if ($eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
    return
  }
  if ($null -ne $script:petWindowDrag) {
    Stop-PetWindowDrag
    return
  }
  if ([int]$eventArgs.Y -ge [int]$script:petDragTop) {
    Toggle-QuotaPanel
  }
}

$baseControl.Add_MouseDown({ Start-PetWindowDrag $this $_ })
$baseControl.Add_MouseMove({
  if ([int]$_.Y -lt [int]$script:petDragTop) {
    $baseControl.Cursor = [System.Windows.Forms.Cursors]::Arrow
  } else {
    $baseControl.Cursor = [System.Windows.Forms.Cursors]::Hand
  }
  Move-PetWindowDrag $this $_
  if (
    $null -ne $script:petWindowDrag -and
    $script:petWindowDrag.Moved
  ) {
    $baseControl.Cursor = [System.Windows.Forms.Cursors]::SizeAll
  }
})
$baseControl.Add_MouseUp({
  Complete-PetBaseMouseUp $this $_
  if ([int]$_.Y -lt [int]$script:petDragTop) {
    $baseControl.Cursor = [System.Windows.Forms.Cursors]::Arrow
  } else {
    $baseControl.Cursor = [System.Windows.Forms.Cursors]::Hand
  }
})
$baseControl.Add_MouseCaptureChanged({
  if (-not $baseControl.Capture) {
    Stop-PetWindowDrag
    $baseControl.Cursor = [System.Windows.Forms.Cursors]::Arrow
  }
})
$baseControl.Add_MouseLeave({
  $baseControl.Cursor = [System.Windows.Forms.Cursors]::Arrow
})
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$statusMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusMenuItem.Text = Get-UiText -Key 'StartingStatus'
$statusMenuItem.Enabled = $false
[void]$trayMenu.Items.Add($statusMenuItem)
[void]$trayMenu.Items.Add(
  (New-Object System.Windows.Forms.ToolStripSeparator)
)
$refreshMenuItem = $trayMenu.Items.Add((Get-UiText -Key 'Refresh'))
$themeMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$themeMenuItem.Text = Get-UiText -Key 'BaseTheme'
[void]$trayMenu.Items.Add($themeMenuItem)

$createWithCodexItem = New-Object System.Windows.Forms.ToolStripMenuItem
$createWithCodexItem.Text = Get-UiText -Key 'CreateWithCodex'
$createWithCodexItem.Add_Click({
  try {
    $creatorScript = Join-Path `
      $PSScriptRoot `
      'Start-CodexPetThemeCreator.ps1'
    if (-not (Test-Path -LiteralPath $creatorScript)) {
      throw 'The Codex theme creator is missing from this installation.'
    }
    & $creatorScript `
      -Language $script:uiLanguage `
      -ProjectRootOverride $projectRoot
  } catch {
    Write-SidecarLog -Message (
      'Could not open the Codex theme creator: ' +
      $_.Exception.Message
    )
    [void][System.Windows.Forms.MessageBox]::Show(
      $_.Exception.Message,
      'Codex Pet Dock',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )
  }
})

$reloadCustomThemesItem = New-Object System.Windows.Forms.ToolStripMenuItem
$reloadCustomThemesItem.Text = Get-UiText -Key 'ReloadThemes'

function Rebuild-ThemeMenu {
  $themeMenuItem.DropDownItems.Clear()
  $script:themeMenuItems = @{}
  foreach ($themeId in @($script:themeCatalog.Keys)) {
    $definition = $script:themeCatalog[$themeId]
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = if (
      $null -ne $definition.IsCustom -and
      [bool]$definition.IsCustom
    ) {
      Get-UiText `
        -Key 'CustomThemePrefix' `
        -Arguments @([string]$definition.Name)
    } else {
      [string]$definition.Name
    }
    $item.Tag = [string]$themeId
    $item.Checked = ([string]$themeId -eq $script:selectedThemeId)
    $item.Add_Click({
      param($sender, $eventArgs)
      [void](Invoke-PetBaseThemeSwitch `
        -ThemeId ([string]$sender.Tag) `
        -Persist)
    })
    [void]$themeMenuItem.DropDownItems.Add($item)
    $script:themeMenuItems[[string]$themeId] = $item
  }
  [void]$themeMenuItem.DropDownItems.Add(
    (New-Object System.Windows.Forms.ToolStripSeparator)
  )
  [void]$themeMenuItem.DropDownItems.Add($createWithCodexItem)
  [void]$themeMenuItem.DropDownItems.Add(
    (New-Object System.Windows.Forms.ToolStripSeparator)
  )
  [void]$themeMenuItem.DropDownItems.Add($reloadCustomThemesItem)
}

function Invoke-CustomThemeReload {
  $previousThemeId = [string]$script:selectedThemeId
  Reload-CustomThemeCatalog
  if (-not $script:themeCatalog.Contains($previousThemeId)) {
    $previousThemeId = 'holo-cyan'
  }
  [void](Invoke-PetBaseThemeSwitch `
    -ThemeId $previousThemeId `
    -Persist)
  Rebuild-ThemeMenu
  return @(
    $script:themeCatalog.Keys |
      Where-Object {
        $definition = $script:themeCatalog[[string]$_]
        $null -ne $definition.IsCustom -and [bool]$definition.IsCustom
      }
  ).Count
}

$reloadCustomThemesItem.Add_Click({
  try {
    $customThemeCount = Invoke-CustomThemeReload
    $trayIcon.ShowBalloonTip(
      2500,
      'Codex Pet Dock',
      (
        Get-UiText `
          -Key 'CustomThemesLoaded' `
          -Arguments @([string]$customThemeCount)
      ),
      [System.Windows.Forms.ToolTipIcon]::Info
    )
  } catch {
    Write-SidecarLog -Message (
      'Custom theme reload recovered: ' + $_.Exception.Message
    )
  }
})
Rebuild-ThemeMenu

$languageMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$languageMenuItem.Text = Get-UiText -Key 'Language'
$englishLanguageItem = New-Object System.Windows.Forms.ToolStripMenuItem
$englishLanguageItem.Text = Get-UiText -Key 'English'
$englishLanguageItem.Tag = 'en-US'
$chineseLanguageItem = New-Object System.Windows.Forms.ToolStripMenuItem
$chineseLanguageItem.Text = Get-UiText -Key 'SimplifiedChinese'
$chineseLanguageItem.Tag = 'zh-CN'
$englishLanguageItem.Checked = ($script:uiLanguage -eq 'en-US')
$chineseLanguageItem.Checked = ($script:uiLanguage -eq 'zh-CN')
[void]$languageMenuItem.DropDownItems.Add($englishLanguageItem)
[void]$languageMenuItem.DropDownItems.Add($chineseLanguageItem)

function Apply-UiLanguage {
  $refreshMenuItem.Text = Get-UiText -Key 'Refresh'
  $themeMenuItem.Text = Get-UiText -Key 'BaseTheme'
  $createWithCodexItem.Text = Get-UiText -Key 'CreateWithCodex'
  $reloadCustomThemesItem.Text = Get-UiText -Key 'ReloadThemes'
  $languageMenuItem.Text = Get-UiText -Key 'Language'
  $englishLanguageItem.Text = Get-UiText -Key 'English'
  $chineseLanguageItem.Text = Get-UiText -Key 'SimplifiedChinese'
  $checkForUpdatesMenuItem.Text = Get-UiText -Key 'CheckForUpdates'
  $launchAtSignInMenuItem.Text = Get-UiText -Key 'LaunchAtSignIn'
  $exitMenuItem.Text = Get-UiText -Key 'Exit'
  $englishLanguageItem.Checked = ($script:uiLanguage -eq 'en-US')
  $chineseLanguageItem.Checked = ($script:uiLanguage -eq 'zh-CN')
  Rebuild-ThemeMenu
  Update-QuotaUi
  $script:lastTrayStatusKey = ''
  Update-TrayStatus
}

$languageClickHandler = {
  param($sender, $eventArgs)
  $requestedUiLanguage = [string]$sender.Tag
  if ($requestedUiLanguage -notin @('en-US', 'zh-CN')) {
    return
  }
  $script:uiLanguage = $requestedUiLanguage
  Save-PetQuotaConfig
  Apply-UiLanguage
}
$englishLanguageItem.Add_Click($languageClickHandler)
$chineseLanguageItem.Add_Click($languageClickHandler)
[void]$trayMenu.Items.Add($languageMenuItem)

$checkForUpdatesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$checkForUpdatesMenuItem.Text = Get-UiText -Key 'CheckForUpdates'
$checkForUpdatesMenuItem.Add_Click({
  try {
    $releasePage = New-Object System.Diagnostics.ProcessStartInfo
    $releasePage.FileName = (
      'https://github.com/hjxccc/codex-pet-dock/releases'
    )
    $releasePage.UseShellExecute = $true
    [void][System.Diagnostics.Process]::Start($releasePage)
  } catch {
    Write-SidecarLog -Message (
      'Could not open the release page: ' + $_.Exception.Message
    )
  }
})
[void]$trayMenu.Items.Add($checkForUpdatesMenuItem)

$launchAtSignInMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$launchAtSignInMenuItem.Text = Get-UiText -Key 'LaunchAtSignIn'
$launchAtSignInMenuItem.Checked = Get-LaunchAtSignInEnabled
$launchAtSignInMenuItem.Add_Click({
  param($sender, $eventArgs)
  try {
    $enableStartup = -not (Get-LaunchAtSignInEnabled)
    Set-LaunchAtSignIn -Enabled $enableStartup
    $sender.Checked = Get-LaunchAtSignInEnabled
  } catch {
    $sender.Checked = Get-LaunchAtSignInEnabled
    Write-SidecarLog -Message (
      'Could not update launch-at-sign-in: ' + $_.Exception.Message
    )
  }
})
[void]$trayMenu.Items.Add(
  (New-Object System.Windows.Forms.ToolStripSeparator)
)
[void]$trayMenu.Items.Add($launchAtSignInMenuItem)
[void]$trayMenu.Items.Add(
  (New-Object System.Windows.Forms.ToolStripSeparator)
)
$exitMenuItem = $trayMenu.Items.Add((Get-UiText -Key 'Exit'))
$refreshMenuItem.Add_Click({ Begin-QuotaRefresh })
$exitMenuItem.Add_Click({
  $script:isExiting = $true
  [System.Windows.Forms.Application]::Exit()
})

if ($ThemeSwitchDiagnostics) {
  try {
    $themeResults = @()
    foreach ($diagnosticThemeId in @($script:themeCatalog.Keys)) {
      $switched = Invoke-PetBaseThemeSwitch `
        -ThemeId ([string]$diagnosticThemeId) `
        -Persist
      $savedThemeId = Get-SavedThemeId
      $definition = $script:themeCatalog[[string]$diagnosticThemeId]
      $contactGap = (
        [int]$definition.ContactSurfaceY -
        [int]$script:themeAnchorLift
      )
      $themeResults += [pscustomobject]@{
        theme = [string]$diagnosticThemeId
        switched = [bool]$switched
        persisted = ([string]$savedThemeId -eq [string]$diagnosticThemeId)
        dragHandleTop = [int]$script:petDragTop
        dragDelegatesToPet = (
          [int]$script:petDragTop -gt 0 -and
          [int]$script:petDragTop -lt [int]$baseControl.MetricsBottom
        )
        metricsBottom = [int]$baseControl.MetricsBottom
        height = [int]$petBase.Height
        layoutFits = (
          [int]$baseControl.MetricsBottom -le [int]$petBase.Height - 2
        )
        controlSizeFits = (
          [int]$baseControl.Width -eq [int]$petBase.ClientSize.Width -and
          [int]$baseControl.Height -eq [int]$petBase.ClientSize.Height
        )
        fontFits = [bool]$baseControl.MetricsFontFits
        alphaCoverage = [math]::Round(
          [double]$baseControl.MetricsAlphaCoverage,
          4
        )
        contactGap = $contactGap
        contactFits = ($contactGap -le 0 -and $contactGap -ge -10)
      }
    }
    [pscustomobject]@{
      ok = (@(
        $themeResults |
          Where-Object {
            -not $_.switched -or
            -not $_.persisted -or
            -not $_.layoutFits -or
            -not $_.controlSizeFits -or
            -not $_.fontFits -or
            [double]$_.alphaCoverage -lt 0.95 -or
            -not $_.contactFits -or
            -not $_.dragDelegatesToPet
          }
      ).Count -eq 0)
      themes = @($themeResults)
    } | ConvertTo-Json -Depth 4
  } catch {
    [pscustomobject]@{
      ok = $false
      error = $_.Exception.Message
      stack = $_.ScriptStackTrace
    } | ConvertTo-Json -Depth 4
    exit 1
  }
  $petBase.Dispose()
  if ($null -ne $baseTexture) {
    $baseTexture.Dispose()
  }
  $panel.Dispose()
  $trayMenu.Dispose()
  if ($null -ne $appIcon) {
    $appIcon.Dispose()
  }
  exit 0
}

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = if ($null -ne $appIcon) {
  $appIcon
} else {
  [System.Drawing.SystemIcons]::Information
}
$trayIcon.Text = 'Codex Pet Dock'
$trayIcon.Visible = $true
$trayIcon.ContextMenuStrip = $trayMenu
$trayIcon.Add_DoubleClick({ Toggle-QuotaPanel })

function Update-TrayStatus {
  $statusKey = ''
  $statusText = ''
  $toolTipText = 'Codex Pet Dock'
  if (
    $null -eq $script:currentPetWindow -or
    -not $script:currentPetWindow.Visible
  ) {
    $statusKey = 'waiting'
    $statusText = Get-UiText -Key 'WaitingStatus'
    $toolTipText = Get-UiText -Key 'WaitingTooltip'
  } elseif ($null -ne $script:latestError) {
    $statusKey = 'quota-error'
    $statusText = Get-UiText -Key 'QuotaUnavailableStatus'
    $toolTipText = Get-UiText -Key 'QuotaUnavailableTooltip'
  } elseif ($null -eq $script:latestQuota) {
    $statusKey = 'loading'
    $statusText = Get-UiText -Key 'LoadingStatus'
    $toolTipText = Get-UiText -Key 'LoadingTooltip'
  } else {
    $freshness = Get-QuotaFreshness
    if ($freshness.IsStale) {
      $statusKey = 'stale-' + [string][math]::Floor(
        [double]$freshness.AgeSeconds / 300
      )
      $statusText = Get-UiText -Key 'StaleStatus'
      $toolTipText = Get-UiText -Key 'StaleTooltip'
    } else {
      $statusKey = 'live-' + [string][math]::Floor(
        [double]$freshness.AgeSeconds / 60
      )
      $statusText = Get-UiText `
        -Key 'UpdatedStatus' `
        -Arguments @([string]$freshness.Label)
      $toolTipText = Get-UiText -Key 'ConnectedTooltip'
    }
  }
  if ($statusKey -eq $script:lastTrayStatusKey) {
    return
  }
  $script:lastTrayStatusKey = $statusKey
  $statusMenuItem.Text = $statusText
  $trayIcon.Text = $toolTipText
}

Update-TrayStatus
if (-not (Test-Path -LiteralPath $welcomeMarkerPath)) {
  try {
    [void][System.IO.Directory]::CreateDirectory($configDirectory)
    [System.IO.File]::WriteAllText(
      $welcomeMarkerPath,
      [DateTime]::Now.ToString('O'),
      (New-Object System.Text.UTF8Encoding($false))
    )
    $trayIcon.ShowBalloonTip(
      5000,
      (Get-UiText -Key 'WelcomeTitle'),
      (Get-UiText -Key 'WelcomeBody'),
      [System.Windows.Forms.ToolTipIcon]::Info
    )
  } catch {
    Write-SidecarLog -Message (
      'Welcome hint recovered: ' + $_.Exception.Message
    )
  }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 64
$timer.Add_Tick({
  try {
  if ($script:isExiting) {
    return
  }
  if (
    $null -ne $script:instanceActivationEvent -and
    $script:instanceActivationEvent.WaitOne(0)
  ) {
    Update-TrayStatus
    $trayIcon.ShowBalloonTip(
      3000,
      (Get-UiText -Key 'AlreadyRunning'),
      $statusMenuItem.Text,
      [System.Windows.Forms.ToolTipIcon]::Info
    )
  }
  if (
    $null -ne $script:themeReloadEvent -and
    $script:themeReloadEvent.WaitOne(0)
  ) {
    try {
      $customThemeCount = Invoke-CustomThemeReload
      $trayIcon.ShowBalloonTip(
        2500,
        (Get-UiText -Key 'CustomBasesReloaded'),
        (
          Get-UiText `
            -Key 'CustomBasesAvailable' `
            -Arguments @([string]$customThemeCount)
        ),
        [System.Windows.Forms.ToolTipIcon]::Info
      )
    } catch {
      Write-SidecarLog -Message (
        'Custom theme reload recovered: ' + $_.Exception.Message
      )
    }
  }
  if (
    $RunSeconds -gt 0 -and
    ([DateTime]::Now - $script:startedAt).TotalSeconds -ge $RunSeconds
  ) {
    $script:isExiting = $true
    [System.Windows.Forms.Application]::Exit()
    return
  }

  $previousPetHandle = if ($null -ne $script:currentPetWindow) {
    [Int64]$script:currentPetWindow.Handle
  } else {
    0
  }
  $trackedPetWindow = Get-TrackedPetWindow `
    -PetWindow $script:currentPetWindow
  $petSearchIntervalSeconds = if (
    $null -eq $trackedPetWindow -or
    -not $trackedPetWindow.Visible
  ) {
    1.0
  } else {
    0.5
  }
  $shouldSearchForPetWindow = (
    $null -eq $trackedPetWindow -or
    -not $trackedPetWindow.Visible -or
    $null -eq $script:mascotAutomationElement
  )
  if (
    $shouldSearchForPetWindow -and
    (
      [DateTime]::Now - $script:lastPetSearchAt
    ).TotalSeconds -ge $petSearchIntervalSeconds
  ) {
    $script:lastPetSearchAt = [DateTime]::Now
    $replacementPetWindow = Get-PetWindow
    if ($null -ne $replacementPetWindow) {
      $replacementPetWindow | Add-Member `
        -NotePropertyName Visible `
        -NotePropertyValue $true `
        -Force
      if (
        $null -eq $trackedPetWindow -or
        -not $trackedPetWindow.Visible -or
        [Int64]$replacementPetWindow.Handle -ne
          [Int64]$trackedPetWindow.Handle
      ) {
        $trackedPetWindow = $replacementPetWindow
      }
    }
  }
  $nextPetHandle = if ($null -ne $trackedPetWindow) {
    [Int64]$trackedPetWindow.Handle
  } else {
    0
  }
  if ($nextPetHandle -ne $previousPetHandle) {
    $script:petPointerDrag = $null
    $script:petPointerWasDown = $true
    Hide-PetDragSurface
    Reset-PetMascotTracking -ClearLastBounds
    $script:lastBaseTargetSignature = ''
    $script:baseIsSettling = $false
    $script:snapDockToMascotAtNextFrame = $true
    Extend-FastTracking -Milliseconds 1500
  }
  $script:currentPetWindow = $trackedPetWindow

  if (
    $null -ne $script:currentPetWindow -and
    $script:currentPetWindow.Visible
  ) {
    $script:lastPetVisibleAt = [DateTime]::Now
  }
  $leftButtonCurrentlyDown = (
    [CodexPetQuota.NativeMethods]::GetAsyncKeyState(0x01) -band 0x8000
  ) -ne 0
  $petTemporarilyUnavailable = (
    $null -ne $script:currentPetWindow -and
    -not $script:currentPetWindow.Visible -and
    $leftButtonCurrentlyDown -and
    ([DateTime]::Now - $script:lastPetVisibleAt).TotalSeconds -le 2
  )

  if (
    $null -eq $script:currentPetWindow -or
    (
      -not $script:currentPetWindow.Visible -and
      -not $petTemporarilyUnavailable
    )
  ) {
    $script:petPointerDrag = $null
    $script:petPointerWasDown = $leftButtonCurrentlyDown
    Hide-PetDragSurface
    $petBase.Hide()
    $panel.Hide()
    $script:baseIsSettling = $false
    $script:lastBaseTargetSignature = ''
    Stop-QuotaRefresh
  } else {
    $mascotBounds = Get-PetMascotBounds `
      -PetWindow $script:currentPetWindow
    $lastMascotGraceSeconds = if (
      [DateTime]::Now -lt $script:fastTrackingUntil
    ) {
      0.35
    } else {
      1.25
    }
    if ($null -ne $mascotBounds) {
      $script:lastMascotBounds = $mascotBounds
      $script:lastMascotSeenAt = [DateTime]::Now
      $mascotSignature = (
        [string]$mascotBounds.Left + ',' +
        [string]$mascotBounds.Top + ',' +
        [string]$mascotBounds.Width + ',' +
        [string]$mascotBounds.Height
      )
      if ($mascotSignature -ne $script:lastMascotSignature) {
        $script:lastMascotSignature = $mascotSignature
        # Continuous movement keeps extending this short burst. Once the pet
        # stops, high-frequency tracking falls back in well under a second.
        Extend-FastTracking -Milliseconds 400
      }
    } elseif (
      $null -ne $script:lastMascotBounds -and
      (
        [DateTime]::Now - $script:lastMascotSeenAt
      ).TotalSeconds -le $lastMascotGraceSeconds
    ) {
      $mascotBounds = $script:lastMascotBounds
    }

    if ($null -ne $mascotBounds) {
      Update-PetDragSurface -MascotBounds $mascotBounds
    } else {
      Hide-PetDragSurface
    }
    Update-PetPointerDrag `
      -LeftButtonDown $leftButtonCurrentlyDown `
      -MascotBounds $mascotBounds

    if ($null -eq $mascotBounds) {
      $anchorLeft = $script:currentPetWindow.Left
      $anchorWidth = $script:currentPetWindow.Width
      $anchorBottom = (
        $script:currentPetWindow.Bottom - $petBase.Height
      )
    } else {
      $anchorLeft = $mascotBounds.Left
      $anchorWidth = $mascotBounds.Width
      # Overlap the raised rear pad beneath the mascot. The base window is
      # explicitly kept behind the official pet window below, so the pet
      # occludes the pad edge and gains a convincing contact relationship.
      $anchorBottom = (
        $mascotBounds.Top +
        $mascotBounds.Height -
        $script:themeAnchorLift
      )
    }

    $baseLeft = (
      $anchorLeft +
      [math]::Floor(($anchorWidth - $petBase.Width) / 2) +
      $BaseOffsetX
    )
    $baseTop = (
      $anchorBottom +
      $BaseOffsetY
    )
    $baseWorkingArea = Get-MonitorWorkArea `
      -WindowHandle $script:currentPetWindow.Handle
    if ($null -eq $baseWorkingArea) {
      Hide-PetDragSurface
      $petBase.Hide()
      $panel.Hide()
      $script:currentPetWindow = $null
      $script:baseIsSettling = $false
      $script:lastBaseTargetSignature = ''
      Reset-PetMascotTracking -ClearLastBounds
    } else {
      $baseLeft = [math]::Max(
        $baseWorkingArea.Left,
        [math]::Min($baseLeft, $baseWorkingArea.Right - $petBase.Width)
      )
      $baseTop = [math]::Max(
        $baseWorkingArea.Top,
        [math]::Min($baseTop, $baseWorkingArea.Bottom - $petBase.Height)
      )
      $targetSignature = (
        [string][Int64]$script:currentPetWindow.Handle + ',' +
        [string]$baseLeft + ',' +
        [string]$baseTop
      )
      if ($targetSignature -ne $script:lastBaseTargetSignature) {
        $script:lastBaseTargetSignature = $targetSignature
        Extend-FastTracking -Milliseconds 400
      }

      $nextBaseLeft = $baseLeft
      $nextBaseTop = $baseTop
      if (-not $petBase.Visible) {
        $petBase.Location = New-Object System.Drawing.Point $baseLeft, $baseTop
        $petBase.Show()
        $script:baseIsSettling = $false
        $script:snapDockToMascotAtNextFrame = $false
      } elseif ($script:snapDockToMascotAtNextFrame) {
        # A confirmed mascot replacement gets one atomic attachment frame.
        # Smoothing from the previous pet would make the base visibly lag and
        # create the impression that the pet itself changed position.
        $nextBaseLeft = $baseLeft
        $nextBaseTop = $baseTop
        $script:baseIsSettling = $false
        $script:snapDockToMascotAtNextFrame = $false
      } else {
        $nextBaseLeft = Get-SmoothedDockCoordinate `
          -Current $petBase.Left `
          -Target $baseLeft
        $nextBaseTop = Get-SmoothedDockCoordinate `
          -Current $petBase.Top `
          -Target $baseTop
        $script:baseIsSettling = (
          $nextBaseLeft -ne $baseLeft -or
          $nextBaseTop -ne $baseTop
        )
      }
      $basePositionChanged = (
        $nextBaseLeft -ne $petBase.Left -or
        $nextBaseTop -ne $petBase.Top
      )
      $zOrderMaintenanceDue = (
        [DateTime]::Now - $script:lastBaseZOrderAt
      ).TotalMilliseconds -ge 1000
      if ($basePositionChanged -or $zOrderMaintenanceDue) {
        [void][CodexPetQuota.NativeMethods]::SetWindowPos(
          $petBase.Handle,
          [IntPtr]$script:currentPetWindow.Handle,
          $nextBaseLeft,
          $nextBaseTop,
          0,
          0,
          0x0011
        )
        $script:lastBaseZOrderAt = [DateTime]::Now
      }

      if ($panel.Visible) {
        $panelLeft = $petBase.Left - $panel.Width - 8
        if ($panelLeft -lt $baseWorkingArea.Left) {
          $panelLeft = $petBase.Right + 8
        }
        $panelTop = $petBase.Bottom - $panel.Height
        $panelLeft = [math]::Max(
          $baseWorkingArea.Left,
          [math]::Min(
            $panelLeft,
            $baseWorkingArea.Right - $panel.Width
          )
        )
        $panelTop = [math]::Max(
          $baseWorkingArea.Top,
          [math]::Min(
            $panelTop,
            $baseWorkingArea.Bottom - $panel.Height
          )
        )
        $panel.Location = New-Object System.Drawing.Point $panelLeft, $panelTop
      }
    }
  }

  if ($null -ne $script:probeProcess -and $script:probeProcess.HasExited) {
    try {
      $script:latestQuota = Read-QuotaProbe -Process $script:probeProcess
      $script:latestError = $null
      $script:probeFailureCount = 0
      $script:nextAutomaticProbeAt = (
        [DateTime]::Now.AddSeconds($RefreshSeconds)
      )
    } catch {
      $script:latestError = $_.Exception.Message
      $script:probeFailureCount = [math]::Min(
        6,
        [int]$script:probeFailureCount + 1
      )
      $retrySeconds = [math]::Min(
        $probeFailureMaxSeconds,
        $probeFailureBaseSeconds * [math]::Pow(
          2,
          [int]$script:probeFailureCount - 1
        )
      )
      $script:nextAutomaticProbeAt = (
        [DateTime]::Now.AddSeconds([int]$retrySeconds)
      )
    } finally {
      $script:probeProcess = $null
      Update-QuotaUi
    }
  }

  Update-NetworkRecoveryState

  if (
    $null -ne $script:currentPetWindow -and
    $script:currentPetWindow.Visible -and
    $script:networkAvailable -and
    $null -eq $script:probeProcess -and
    [DateTime]::Now -ge $script:nextAutomaticProbeAt
  ) {
    Begin-QuotaRefresh
  }

  Update-TrayStatus

  $leftButtonDown = (
    [CodexPetQuota.NativeMethods]::GetAsyncKeyState(0x01) -band 0x8000
  ) -ne 0
  if (
    $null -eq $script:currentPetWindow
  ) {
    if ($timer.Interval -ne 1000) {
      $timer.Interval = 1000
    }
  } elseif (-not $script:currentPetWindow.Visible) {
    if ($timer.Interval -ne 1000) {
      $timer.Interval = 1000
    }
  } elseif (
    $leftButtonDown -or
    $script:baseIsSettling -or
    [DateTime]::Now -lt $script:fastTrackingUntil
  ) {
    if ($timer.Interval -ne 16) {
      $timer.Interval = 16
    }
  } elseif ($timer.Interval -ne 64) {
    $timer.Interval = 64
  }
  } catch {
    $petBase.Hide()
    Hide-PetDragSurface
    $panel.Hide()
    $script:currentPetWindow = $null
    $script:baseIsSettling = $false
    $script:lastBaseTargetSignature = ''
    Reset-PetMascotTracking -ClearLastBounds
    Write-SidecarLog -Message (
      'Tracking frame recovered: ' + $_.Exception.Message
    )
  }
})

$applicationContext = New-Object System.Windows.Forms.ApplicationContext
$applicationContext.add_ThreadExit({
  $script:isExiting = $true
})

try {
  $timer.Start()
  [System.Windows.Forms.Application]::Run($applicationContext)
} finally {
  $timer.Stop()
  $trayIcon.Visible = $false
  $trayIcon.Dispose()
  if ($null -ne $probeProcess -and -not $probeProcess.HasExited) {
    $probeProcess.Kill()
  }
  $petBase.Dispose()
  $petDragSurface.Dispose()
  $petDragSurface.Dispose()
  if ($null -ne $baseTexture) {
    $baseTexture.Dispose()
  }
  $panel.Dispose()
  $trayMenu.Dispose()
  if ($null -ne $appIcon) {
    $appIcon.Dispose()
  }
  if ($null -ne $instanceMutex) {
    if ($ownsInstanceMutex) {
      try {
        $instanceMutex.ReleaseMutex()
      } catch {
      }
    }
    $instanceMutex.Dispose()
  }
  if ($null -ne $instanceActivationEvent) {
    $instanceActivationEvent.Dispose()
  }
  if ($null -ne $themeReloadEvent) {
    $themeReloadEvent.Dispose()
  }
}
