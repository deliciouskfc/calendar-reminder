param([int]$Size = 512, [string]$Out = "icon-512.png", [switch]$Crest)

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
public static class IconDraw {
  public static GraphicsPath Rounded(float x, float y, float w, float h, float r) {
    GraphicsPath p = new GraphicsPath();
    float d = r * 2;
    p.AddArc(x, y, d, d, 180, 90);
    p.AddArc(x + w - d, y, d, d, 270, 90);
    p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
    p.AddArc(x, y + h - d, d, d, 90, 90);
    p.CloseFigure();
    return p;
  }
}
"@

$bmp = New-Object System.Drawing.Bitmap($Size, $Size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

$s = $Size / 512.0
$purple = [System.Drawing.Color]::FromArgb(255, 95, 44, 130)
$purpleLight = [System.Drawing.Color]::FromArgb(255, 142, 68, 173)

if (-not $Crest) {
  # purple gradient rounded background
  $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point($Size, $Size)),
    [System.Drawing.Color]::FromArgb(255, 82, 36, 118), $purpleLight)
  $bgPath = [IconDraw]::Rounded(0, 0, $Size, $Size, 110 * $s)
  $g.FillPath($bgBrush, $bgPath)
} else {
  # badge: white circle + purple ring (absolute geometry, not scaled)
  $whiteB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $g.FillEllipse($whiteB, 8, 8, ($Size - 16), ($Size - 16))
  $ringP = New-Object System.Drawing.Pen($purple, (12 * $s))
  $g.DrawEllipse($ringP, 20, 20, ($Size - 40), ($Size - 40))
}

# calendar body geometry
$calX = 104 * $s; $calY = 148 * $s; $calW = 304 * $s; $calH = 264 * $s
$headH = 84 * $s
if ($Crest) { $calX = 138 * $s; $calY = 168 * $s; $calW = 236 * $s; $calH = 200 * $s; $headH = 66 * $s }

# white calendar body
$whiteB2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$bodyPath = [IconDraw]::Rounded($calX, $calY, $calW, $calH, 22 * $s)
$g.FillPath($whiteB2, $bodyPath)

# purple header band
$headPath = [IconDraw]::Rounded($calX, $calY, $calW, ($headH + 24 * $s), 22 * $s)
$headBrush = New-Object System.Drawing.SolidBrush($purple)
$g.FillPath($headBrush, $headPath)

# hanger rings
$ringPen = New-Object System.Drawing.Pen($purple, (14 * $s))
$ringPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$ringPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($ringPen, ($calX + $calW * 0.28), ($calY - 14 * $s), ($calX + $calW * 0.28), ($calY + 12 * $s))
$g.DrawLine($ringPen, ($calX + $calW * 0.72), ($calY - 14 * $s), ($calX + $calW * 0.72), ($calY + 12 * $s))

# SZ text on header
$fontSZ = New-Object System.Drawing.Font("Arial", (38 * $s), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$whiteB3 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$fSize = $g.MeasureString("SZ", $fontSZ)
$g.DrawString("SZ", $fontSZ, $whiteB3, ($calX + ($calW - $fSize.Width) / 2), ($calY + ($headH - $fSize.Height) / 2))

# date dots grid
$dotA = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 205, 186, 224))
$dotB = New-Object System.Drawing.SolidBrush($purpleLight)
$hiB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 231, 76, 60))
$cols = 5; $rows = 3
$gridW = $calW - 56 * $s; $gridH = $calH - $headH - 36 * $s
$gx = $calX + 28 * $s; $gy = $calY + $headH + 20 * $s
$dotD = 18 * $s
$stepX = ($gridW - $dotD) / ($cols - 1); $stepY = ($gridH - $dotD) / ($rows - 1)
for ($r = 0; $r -lt $rows; $r++) {
  for ($c = 0; $c -lt $cols; $c++) {
    $dx = $gx + $c * $stepX; $dy = $gy + $r * $stepY
    if ($r -eq 1 -and $c -eq 3) { $g.FillEllipse($hiB, $dx - 8 * $s, $dy - 8 * $s, $dotD + 16 * $s, $dotD + 16 * $s) }
    elseif (($r * $cols + $c) % 4 -eq 1) { $g.FillEllipse($dotB, $dx, $dy, $dotD, $dotD) }
    else { $g.FillEllipse($dotA, $dx, $dy, $dotD, $dotD) }
  }
}

$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "saved $Out ($Size x $Size)"
