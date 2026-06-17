param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\NotesApp\NotesApp\Assets')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Этот скрипт нужен не как часть логики приложения, а как воспроизводимый
# способ собрать фирменный значок для Windows. Мы рисуем его программно,
# чтобы не хранить зависимость от внешнего графического редактора.
Add-Type -AssemblyName System.Drawing

function New-RoundedPath {
    param(
        [Parameter(Mandatory)]
        [System.Drawing.RectangleF]$Rect,

        [Parameter(Mandatory)]
        [float]$Radius
    )

    # Округлые углы дают более современный вид, а также лучше читаются в
    # маленьком размере, где острые детали быстро "шумят".
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2

    $path.StartFigure()
    $path.AddArc($Rect.X, $Rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()

    return $path
}

function Write-IcoFromPng {
    param(
        [Parameter(Mandatory)]
        [string]$PngPath,

        [Parameter(Mandatory)]
        [string]$IcoPath
    )

    # Windows допускает ICO-контейнер, внутри которого лежит PNG-изображение.
    # Это позволяет сохранить качество одного 256px-арта без ручной сборки
    # набора из нескольких размеров.
    $pngBytes = [System.IO.File]::ReadAllBytes($PngPath)

    $stream = [System.IO.File]::Open($IcoPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $writer = [System.IO.BinaryWriter]::new($stream)
        try {
            # ICO header:
            # 0..1 reserved, 2..3 type, 4..5 image count
            $writer.Write([byte[]](0, 0))
            $writer.Write([byte[]](1, 0))
            $writer.Write([byte[]](1, 0))

            # Directory entry for a single 256x256 PNG image.
            # Width/height are stored as 0 when the dimension is 256.
            $writer.Write([byte]0)   # width
            $writer.Write([byte]0)   # height
            $writer.Write([byte]0)   # color count
            $writer.Write([byte]0)   # reserved
            $writer.Write([UInt16]1) # planes
            $writer.Write([UInt16]32) # bit depth
            $writer.Write([UInt32]$pngBytes.Length)
            $writer.Write([UInt32]22) # header (6) + directory entry (16)
            $writer.Write($pngBytes)
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$pngPath = Join-Path $OutputDirectory 'NotebookPurple.png'
$icoPath = Join-Path $OutputDirectory 'NotebookPurple.ico'

$bitmap = [System.Drawing.Bitmap]::new(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    # Тень нужна не для "красоты ради красоты", а для отделения иконки от
    # светлых обоев и ярких плиток, где плоский силуэт теряется.
    $shadowRect = [System.Drawing.RectangleF]::new(36, 42, 184, 180)
    $shadowPath = New-RoundedPath -Rect $shadowRect -Radius 28
    $shadowBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(54, 0, 0, 0))
    $graphics.TranslateTransform(0, 8)
    $graphics.FillPath($shadowBrush, $shadowPath)
    $graphics.ResetTransform()

    # Основной фиолетовый блокнот.
    $coverRect = [System.Drawing.RectangleF]::new(32, 32, 184, 184)
    $coverPath = New-RoundedPath -Rect $coverRect -Radius 28
    $coverBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $coverRect,
        [System.Drawing.Color]::FromArgb(150, 90, 255),
        [System.Drawing.Color]::FromArgb(91, 33, 182),
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
    )
    $graphics.FillPath($coverBrush, $coverPath)

    # Левая полоса делает силуэт читаемым как у переплёта блокнота.
    $spineRect = [System.Drawing.RectangleF]::new(32, 32, 46, 184)
    $spinePath = New-RoundedPath -Rect $spineRect -Radius 28
    $spineBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $spineRect,
        [System.Drawing.Color]::FromArgb(110, 44, 189),
        [System.Drawing.Color]::FromArgb(66, 25, 120),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $graphics.FillPath($spineBrush, $spinePath)

    # Светлая страница внутри блокнота повышает контраст для линий заметок.
    $pageRect = [System.Drawing.RectangleF]::new(80, 44, 116, 160)
    $pagePath = New-RoundedPath -Rect $pageRect -Radius 18
    $pageBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(236, 229, 255))
    $graphics.FillPath($pageBrush, $pagePath)

    # Узкая полоска рядом со спиралью подчёркивает глубину.
    $pageEdgeBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(220, 200, 255))
    $graphics.FillRectangle($pageEdgeBrush, 78, 44, 10, 160)

    # Кольца переплёта помогают распознать именно блокнот, а не абстрактную плитку.
    $ringBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(240, 232, 255))
    foreach ($y in 70, 96, 122, 148, 174) {
        $graphics.FillEllipse($ringBrush, 49, $y, 10, 10)
    }

    # Линии страницы повторяют визуальный язык бумажной записной книжки.
    $linePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(175, 135, 235), 4)
    $linePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $linePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    foreach ($y in 78, 104, 130, 156) {
        $graphics.DrawLine($linePen, 92, $y, 184, $y)
    }

    # Закладка сверху добавляет узнаваемость и не перегружает малый размер.
    $bookmarkPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $bookmarkPath.StartFigure()
    $bookmarkPoints = [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(181, 44),
        [System.Drawing.Point]::new(198, 44),
        [System.Drawing.Point]::new(198, 79),
        [System.Drawing.Point]::new(190, 71),
        [System.Drawing.Point]::new(181, 79)
    )
    $bookmarkPath.AddPolygon($bookmarkPoints)
    $bookmarkBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(244, 239, 255))
    $graphics.FillPath($bookmarkBrush, $bookmarkPath)

    # Короткая светлая плашка работает как заголовок блока заметок.
    $titleBandBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(120, 255, 255, 255))
    $graphics.FillRectangle($titleBandBrush, 90, 54, 70, 10)
}
finally {
    $graphics.Dispose()
}

$bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

Write-IcoFromPng -PngPath $pngPath -IcoPath $icoPath

Get-ChildItem $OutputDirectory | Select-Object Name, Length
