# Builds the demo vault: notes and review history (tool/demo_vault.dart) plus
# two diagrams, so the vault also shows off embedded images.
#
#   powershell -ExecutionPolicy Bypass -File tool\make_demo_vault.ps1 [-Path D:\...\FPTU-Demo-Vault]

param([string]$Path = 'D:\Project\FPT\FPTU-Demo-Vault')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot
Push-Location $root
try {
  & 'C:\src\flutter\bin\dart.bat' run tool/demo_vault.dart $Path
} finally {
  Pop-Location
}

$orange = [System.Drawing.Color]::FromArgb(242, 112, 36)
$ink = [System.Drawing.Color]::FromArgb(40, 34, 30)
$panel = [System.Drawing.Color]::FromArgb(255, 243, 235)

# Draws labelled boxes connected by arrows, top to bottom.
function New-FlowDiagram([string[]]$steps, [string]$title, [string]$file) {
  $w = 900
  $boxH = 84
  $gap = 34
  $h = 120 + $steps.Count * ($boxH + $gap)
  $bmp = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
  $g.Clear([System.Drawing.Color]::White)

  $titleFont = New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)
  $font = New-Object System.Drawing.Font('Segoe UI', 20)
  $inkBrush = New-Object System.Drawing.SolidBrush($ink)
  $panelBrush = New-Object System.Drawing.SolidBrush($panel)
  $orangePen = New-Object System.Drawing.Pen($orange, 4)
  $orangePen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
  $borderPen = New-Object System.Drawing.Pen($orange, 3)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = [System.Drawing.StringAlignment]::Center
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center

  $g.DrawString($title, $titleFont, $inkBrush, (New-Object System.Drawing.RectangleF(0, 20, $w, 50)), $fmt)

  $y = 100
  foreach ($s in $steps) {
    $rect = New-Object System.Drawing.Rectangle(150, $y, ($w - 300), $boxH)
    $g.FillRectangle($panelBrush, $rect)
    $g.DrawRectangle($borderPen, $rect)
    $g.DrawString($s, $font, $inkBrush, (New-Object System.Drawing.RectangleF($rect.X, $rect.Y, $rect.Width, $rect.Height)), $fmt)
    if ($s -ne $steps[-1]) {
      $g.DrawLine($orangePen, ($w / 2), ($y + $boxH + 4), ($w / 2), ($y + $boxH + $gap - 6))
    }
    $y += $boxH + $gap
  }

  $dest = Join-Path $Path 'attachments'
  New-Item -ItemType Directory -Force $dest | Out-Null
  $bmp.Save((Join-Path $dest $file), [System.Drawing.Imaging.ImageFormat]::Png)
  $titleFont.Dispose(); $font.Dispose(); $inkBrush.Dispose(); $panelBrush.Dispose()
  $orangePen.Dispose(); $borderPen.Dispose(); $g.Dispose(); $bmp.Dispose()
}

New-FlowDiagram @(
  'createState()',
  'initState() - khởi tạo controller',
  'build() - vẽ giao diện',
  'setState() - đánh dấu cần vẽ lại',
  'dispose() - giải phóng tài nguyên'
) 'Vòng đời State trong Flutter' 'vong-doi-widget.png'

New-FlowDiagram @(
  'Request tới Controller (Servlet)',
  'Controller gọi Model (DAO, Entity)',
  'Model truy vấn database',
  'Controller chọn View (JSP)',
  'View trả HTML về trình duyệt'
) 'Luồng xử lý MVC' 'mvc.png'

Write-Host "Đã thêm 2 sơ đồ vào $Path\attachments" -ForegroundColor Green
