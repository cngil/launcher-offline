<#
.SYNOPSIS
Draws the app icon and writes assets\icon.ico (and icon.png for docs).
The icon is plain vector drawing code, so it can be tweaked and regenerated:

    powershell -STA -ExecutionPolicy Bypass -File assets\New-Icon.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase

function New-IconDrawing {
    # Designed on a 256 x 256 grid.
    $gradient = New-Object Windows.Media.LinearGradientBrush(
        [Windows.Media.Color]::FromRgb(0x3B, 0x82, 0xF6), [Windows.Media.Color]::FromRgb(0x1E, 0x40, 0xAF), 55.0)
    $white = [Windows.Media.Brushes]::White

    $group = New-Object Windows.Media.DrawingGroup
    $add = { param($brush, $geometry) $group.Children.Add((New-Object Windows.Media.GeometryDrawing($brush, $null, $geometry))) }

    # Rounded square background.
    & $add $gradient (New-Object Windows.Media.RectangleGeometry((New-Object Windows.Rect 8, 8, 240, 240), 56, 56))

    # Controller body.
    & $add $white ([Windows.Media.Geometry]::Parse(
            'M 88,76 H 168 C 198,76 210,96 214,120 L 222,166 C 226,192 200,206 182,190 L 163,170 H 93 L 74,190 C 56,206 30,192 34,166 L 42,120 C 46,96 58,76 88,76 Z'))

    # D-pad and buttons are cut out in the background colour.
    & $add $gradient (New-Object Windows.Media.RectangleGeometry((New-Object Windows.Rect 68, 116, 42, 15), 4, 4))
    & $add $gradient (New-Object Windows.Media.RectangleGeometry((New-Object Windows.Rect 81.5, 102.5, 15, 42), 4, 4))
    & $add $gradient (New-Object Windows.Media.EllipseGeometry((New-Object Windows.Point 162, 110), 11, 11))
    & $add $gradient (New-Object Windows.Media.EllipseGeometry((New-Object Windows.Point 186, 134), 11, 11))
    $group
}

function New-IconBitmap([Windows.Media.Drawing]$Drawing, [int]$Size) {
    $visual = New-Object Windows.Media.DrawingVisual
    $dc = $visual.RenderOpen()
    $dc.PushTransform((New-Object Windows.Media.ScaleTransform ($Size / 256.0), ($Size / 256.0)))
    $dc.DrawDrawing($Drawing)
    $dc.Close()
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap $Size, $Size, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    # Icons store straight (not premultiplied) alpha.
    New-Object Windows.Media.Imaging.FormatConvertedBitmap $bitmap, ([Windows.Media.PixelFormats]::Bgra32), $null, 0
}

function ConvertTo-Png($Bitmap) {
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
    $stream = New-Object IO.MemoryStream
    $encoder.Save($stream)
    , $stream.ToArray()
}

function ConvertTo-IconDib($Bitmap) {
    # Classic icon entry: BITMAPINFOHEADER, bottom-up 32-bit BGRA, then a 1-bit AND mask.
    # GDI and older shell code only read this format for sizes below 256.
    $size   = $Bitmap.PixelWidth
    $pixels = New-Object byte[] ($size * $size * 4)
    $Bitmap.CopyPixels($pixels, $size * 4, 0)
    $maskStride = [int]([Math]::Ceiling($size / 32.0) * 4)

    $stream = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter $stream
    $w.Write([uint32]40); $w.Write([int32]$size); $w.Write([int32]($size * 2))
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
    $w.Write([uint32]($pixels.Length + $maskStride * $size))
    $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    for ($row = $size - 1; $row -ge 0; $row--) { $w.Write($pixels, $row * $size * 4, $size * 4) }
    $w.Write((New-Object byte[] ($maskStride * $size)))  # alpha channel does the masking
    $w.Flush()
    , $stream.ToArray()
}

$drawing = New-IconDrawing
$sizes   = 16, 20, 24, 32, 40, 48, 64, 128, 256
$images  = foreach ($size in $sizes) {
    $bitmap = New-IconBitmap $drawing $size
    if ($size -ge 256) { , (ConvertTo-Png $bitmap) } else { , (ConvertTo-IconDib $bitmap) }
}

# ICO container: DIB entries for small sizes, PNG for 256 px (the usual layout).
$out    = New-Object IO.MemoryStream
$writer = New-Object IO.BinaryWriter $out
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dimension = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($image in $images) { $writer.Write($image) }
$writer.Flush()

[IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'icon.ico'), $out.ToArray())
[IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'icon.png'), $images[-1])
Write-Host "Wrote icon.ico ($($sizes -join ', ') px) and icon.png"
