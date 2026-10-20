# Draws the default share-preview card WWW\assets\share\default.png (1200x630, the size
# LinkedIn / Facebook / Slack expect). Run by hand after a branding change; the PNG is committed.
# A product card: -Out WWW\products\<id>\share.png -Title <name> -Line1 <H1> -Line2 <tagline>.
param(
    [string]$Out = (Join-Path $PSScriptRoot '..\assets\share\default.png'),
    [string]$Title = 'Delphi-RAG-Lint',
    [string]$Line1 = 'Index, query and lint Delphi code -',
    [string]$Line2 = 'from the command line and inside RAD Studio.'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$w = 1200; $h = 630
$bmp = [Drawing.Bitmap]::new($w, $h)
$g = [Drawing.Graphics]::FromImage($bmp)
try {
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    function C([string]$Hex) { [Drawing.ColorTranslator]::FromHtml($Hex) }
    $g.Clear((C '#141C24'))                                   # --ink
    # three stripes: the lexer / AST / tree-sitter colours of the site
    $x = 0
    foreach ($hex in '#9A6B0F', '#9E3535', '#176E5F') { $g.FillRectangle([Drawing.SolidBrush]::new((C $hex)), $x, 0, 18, $h); $x += 18 }

    # font names must not reuse the parameter names: PowerShell variables ignore case
    $fTitle = [Drawing.Font]::new('Georgia', 84, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $fBody  = [Drawing.Font]::new('Segoe UI', 38, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    $small = [Drawing.Font]::new('Segoe UI', 28, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
    $g.DrawString($Title, $fTitle, [Drawing.SolidBrush]::new((C '#EFF2F5')), 110, 150)
    $g.FillRectangle([Drawing.SolidBrush]::new((C '#2B4C82')), 114, 268, 140, 6)   # --accent rule
    $soft = [Drawing.SolidBrush]::new((C '#C3CDD7'))
    $g.DrawString($Line1, $fBody, $soft, 110, 310)
    $g.DrawString($Line2, $fBody, $soft, 110, 362)
    $muted = [Drawing.SolidBrush]::new((C '#8D9AA7'))
    $g.DrawString('www.delphi-rag-lint.com', $small, $muted, 110, 520)
    $by = 'by HTR Micronite'
    $g.DrawString($by, $small, $muted, $w - 70 - $g.MeasureString($by, $small).Width, 520)

    [void][IO.Directory]::CreateDirectory((Split-Path $Out -Parent))
    $bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png)
    Write-Host "wrote $Out"
} finally { $g.Dispose(); $bmp.Dispose() }
