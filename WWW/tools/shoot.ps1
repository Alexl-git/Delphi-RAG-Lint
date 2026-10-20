# Responsive check: Edge headless screenshots of one BUILT page at phone, tablet and desktop width.
#   pwsh -NoProfile -File WWW\tools\shoot.ps1 -Site WWW\_site -Page products\dl\index.html -Out <dir>
# Writes <Out>\<name>-375.png, -768.png, -1280.png (<name> = the page's folder). Serves nothing:
# the page opens over file://, so a copy beside it gets its root-relative href="/ and src="/
# rewritten to the site folder's file URL (relative picture paths keep working); the copy is
# deleted afterwards.
# Headless Edge will not make a window narrower than ~490 px (asked for 375 it lays out at 492),
# so the page is loaded in an iframe of exactly <w> px inside a wider window, and the PNG is
# cropped to <w>.
# The iframe's scrolling="no" would clip sideways overflow out of the picture, so the copy (its
# CSP meta dropped) gets a script that paints an 8 px magenta square at the top left when
# document.documentElement.scrollWidth > innerWidth; each width prints "<w> px: fits" or
# "<w> px: OVERFLOW", and the script exits 1 after the shots if any width overflowed.
param(
    [Parameter(Mandatory)][string]$Site,
    [Parameter(Mandatory)][string]$Page,
    [Parameter(Mandatory)][string]$Out,
    [int[]]$Widths = @(375, 768, 1280),
    [string]$Edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
)
$ErrorActionPreference = 'Stop'
$siteDir = (Resolve-Path -LiteralPath $Site).Path
$src = Join-Path $siteDir $Page
$siteUrl = ([Uri]($siteDir.TrimEnd('\') + '\')).AbsoluteUri
$copy = Join-Path (Split-Path $src -Parent) '_shoot.html'
$html = [IO.File]::ReadAllText($src) -replace '(href|src)="/(?!/)', "`$1=""$siteUrl"
$probe = '<script>addEventListener("load",function(){if(document.documentElement.scrollWidth>innerWidth){' +
    'var b=document.createElement("div");b.style.cssText="position:fixed;left:0;top:0;width:8px;height:8px;' +
    'background:#f0f;z-index:2147483647";document.body.appendChild(b)}})</script>'
$html = ($html -replace '<meta http-equiv="Content-Security-Policy"[^>]*>', '') -replace '</body>', "$probe</body>"
$overflow = @()
[IO.File]::WriteAllText($copy, $html, [Text.Encoding]::ASCII)
[void][IO.Directory]::CreateDirectory($Out)
$name = Split-Path (Split-Path $src -Parent) -Leaf
$frame = Join-Path (Split-Path $src -Parent) '_shoot-frame.html'
$profileDir = Join-Path ([IO.Path]::GetTempPath()) "shoot-$PID"
Add-Type -AssemblyName System.Drawing
try {
    foreach ($w in $Widths) {
        $png = Join-Path (Resolve-Path -LiteralPath $Out).Path "$name-$w.png"
        $raw = "$png.raw.png"
        [IO.File]::WriteAllText($frame, "<!doctype html><html><body style=""margin:0""><iframe src=""_shoot.html"" width=""$w"" height=""2400"" frameborder=""0"" scrolling=""no""></iframe></body></html>", [Text.Encoding]::ASCII)
        # A fresh profile per shot; Edge sometimes writes the PNG and then lingers, so wait for a
        # readable file, then stop every Edge process of this profile (by id, not by name).
        $prof = "$profileDir-$w"
        [void](Start-Process -FilePath $Edge -PassThru -WindowStyle Hidden -ArgumentList @(
            '--headless=new', '--disable-gpu', '--hide-scrollbars', "--user-data-dir=$prof",
            "--window-size=$([Math]::Max($w, 600)),2400", "--screenshot=$raw", ([Uri]$frame).AbsoluteUri))
        $deadline = [DateTime]::Now.AddSeconds(60); $ok = $false
        while (-not $ok -and [DateTime]::Now -lt $deadline) {
            Start-Sleep -Milliseconds 500
            try { if (Test-Path -LiteralPath $raw) { [IO.File]::OpenRead($raw).Dispose(); $ok = $true } } catch { }
        }
        Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        if (-not $ok) { throw "no screenshot written at $w px within 60 s" }
        Start-Sleep -Milliseconds 300   # let the writer finish the file it just released
        # from memory: a GDI+ clone of a file-backed bitmap keeps the file locked
        $img = [Drawing.Bitmap]::new([IO.MemoryStream]::new([IO.File]::ReadAllBytes($raw)))
        $cut = $img.Clone([Drawing.Rectangle]::new(0, 0, $w, $img.Height), $img.PixelFormat)
        try {
            $px = $cut.GetPixel(3, 3)
            $over = $px.R -gt 240 -and $px.G -lt 15 -and $px.B -gt 240
            $cut.Save($png, [Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $cut.Dispose(); $img.Dispose() }
        [IO.File]::Delete($raw)
        Write-Host "wrote $png"
        if ($over) { $overflow += $w; Write-Host "$w px: OVERFLOW (scrollWidth > $w; the magenta square marks it)" }
        else { Write-Host "$w px: fits" }
    }
} finally {
    [IO.File]::Delete($copy)
    [IO.File]::Delete($frame)
}
if ($overflow) { Write-Host "sideways overflow at $($overflow -join ', ') px"; exit 1 }
