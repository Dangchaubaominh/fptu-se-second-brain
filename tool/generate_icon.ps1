# Draws the app icon (a small network of linked notes on FPT orange) and writes:
#   assets/icon/fptu-brain.png          1024x1024, used for the MSIX logo
#   windows/runner/resources/app_icon.ico   multi-size icon for the Windows build
# Run from the project root:  powershell -ExecutionPolicy Bypass -File tool\generate_icon.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$orange = [System.Drawing.Color]::FromArgb(242, 112, 36)
$orangeDark = [System.Drawing.Color]::FromArgb(206, 74, 18)
$white = [System.Drawing.Color]::White

# Node positions and edges in a 0..1 square; drawn the same at every size.
$nodes = @(
  @{ x = 0.50; y = 0.34; r = 0.115 },  # hub
  @{ x = 0.23; y = 0.24; r = 0.062 },
  @{ x = 0.78; y = 0.27; r = 0.070 },
  @{ x = 0.20; y = 0.62; r = 0.070 },
  @{ x = 0.52; y = 0.72; r = 0.085 },
  @{ x = 0.81; y = 0.63; r = 0.062 }
)
$edges = @(@(0, 1), @(0, 2), @(0, 3), @(0, 4), @(0, 5), @(3, 4), @(4, 5))

function New-IconBitmap([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

  # Rounded square background with a vertical orange gradient.
  $radius = $size * 0.22
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $radius * 2
  $path.AddArc(0, 0, $d, $d, 180, 90)
  $path.AddArc($size - $d, 0, $d, $d, 270, 90)
  $path.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
  $path.AddArc(0, $size - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $orange, $orangeDark, 90)
  $g.FillPath($brush, $path)

  # Links first, so the nodes sit on top of them.
  $pen = New-Object System.Drawing.Pen($white, [float]($size * 0.035))
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  foreach ($e in $edges) {
    $a = $nodes[$e[0]]; $b = $nodes[$e[1]]
    $g.DrawLine($pen, [float]($a.x * $size), [float]($a.y * $size), [float]($b.x * $size), [float]($b.y * $size))
  }

  $fill = New-Object System.Drawing.SolidBrush($white)
  foreach ($n in $nodes) {
    $r = $n.r * $size
    $g.FillEllipse($fill, [float]($n.x * $size - $r), [float]($n.y * $size - $r), [float]($r * 2), [float]($r * 2))
  }

  $pen.Dispose(); $fill.Dispose(); $brush.Dispose(); $path.Dispose(); $g.Dispose()
  return $bmp
}

function Save-Png([System.Drawing.Bitmap]$bmp, [string]$path) {
  New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}

# PNG-compressed ICO (supported since Windows Vista).
function Save-Ico([int[]]$sizes, [string]$path) {
  $images = foreach ($s in $sizes) {
    $bmp = New-IconBitmap $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    @{ size = $s; bytes = $ms.ToArray() }
  }
  New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
  $fs = [System.IO.File]::Create($path)
  $w = New-Object System.IO.BinaryWriter($fs)
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$images.Count)
  $offset = 6 + 16 * $images.Count
  foreach ($img in $images) {
    $dim = if ($img.size -ge 256) { 0 } else { $img.size }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$img.bytes.Length); $w.Write([uint32]$offset)
    $offset += $img.bytes.Length
  }
  foreach ($img in $images) { $w.Write($img.bytes) }
  $w.Dispose(); $fs.Dispose()
}

$root = Split-Path $PSScriptRoot
$png = New-IconBitmap 1024
Save-Png $png (Join-Path $root 'assets\icon\fptu-brain.png')
$png.Dispose()
Save-Ico @(16, 24, 32, 48, 64, 128, 256) (Join-Path $root 'windows\runner\resources\app_icon.ico')

Write-Host 'Đã tạo assets\icon\fptu-brain.png và windows\runner\resources\app_icon.ico' -ForegroundColor Green
