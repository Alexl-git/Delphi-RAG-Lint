. "$PSScriptRoot\..\lib\Config.ps1"
. "$PSScriptRoot\..\lib\Check.ps1"

$c = Read-SiteConfig "$PSScriptRoot\..\site.json"
$share = '<meta property="og:title" content="X"><meta property="og:description" content="About x.">' +
         '<meta property="og:url" content="https://www.delphi-rag-lint.com/x/">' +
         '<meta property="og:image" content="https://www.delphi-rag-lint.com/assets/share/default.png">'
$good = '<html><head><link rel="canonical" href="https://www.delphi-rag-lint.com/x/"><link rel="stylesheet" href="/assets/s.css">' + $share + '</head>' +
        '<body><a href="/x/">x</a><a href="https://www.htrmicronite.com">m</a><script src="/assets/r.js" defer></script></body></html>'

function New-Site([hashtable]$Pages) {
    $d = New-TestDir
    foreach ($k in $Pages.Keys) {
        $p = Join-Path $d $k
        [void][IO.Directory]::CreateDirectory((Split-Path $p -Parent))
        if ($Pages[$k] -is [byte[]]) { [IO.File]::WriteAllBytes($p, $Pages[$k]) }
        else { [IO.File]::WriteAllText($p, $Pages[$k], [Text.ASCIIEncoding]::new()) }
    }
    $d
}
$base = @{ 'x\index.html' = $good; 'assets\s.css' = ''; 'assets\r.js' = ''; 'assets\share\default.png' = '' }

$d = New-Site $base
$r = @(Test-SiteOutput $d $c)
Assert-Equal 0 $r.Count "clean site: $($r -join '; ')"

$cases = [ordered]@{
    'micronite'  = $good.Replace('https://www.htrmicronite.com', 'https://example.com')
    'canonical'  = $good.Replace('<link rel="canonical" href="https://www.delphi-rag-lint.com/x/">', '')
    'dangling'   = $good.Replace('href="/x/"', 'href="/nope/"')
    'off-site'   = $good.Replace('src="/assets/r.js"', 'src="https://x.example/r.js"')
    'inline'     = $good.Replace('<a href="/x/">', '<a style="color:red" href="/x/">')
    'non-ASCII'  = [byte[]]([Text.Encoding]::ASCII.GetBytes($good) + [byte[]](0xE2))
    'placeholder' = $good.Replace('<a href="/x/">x</a>', '{{main}}')
    # share-preview rule (owner 2026-10-20): every page but 404.html carries a complete preview
    'share preview' = $good.Replace('<meta property="og:description" content="About x.">', '')
    'share url'     = $good.Replace('content="https://www.delphi-rag-lint.com/x/">', 'content="https://www.delphi-rag-lint.com/y/">')
    'share image'   = $good.Replace('/assets/share/default.png', '/assets/share/missing.png')
}
foreach ($k in $cases.Keys) {
    $pages = $base.Clone(); $pages['bad\index.html'] = $cases[$k]
    $r = @(Test-SiteOutput (New-Site $pages) $c)
    Assert-Equal 1 $r.Count "case $k gives exactly one problem: $($r -join '; ')"
    Assert-True ($r[0] -like "bad\index.html:*$k*") "case $k message: $($r[0])"
}

# a screenshot copy left by tools\shoot.ps1 (_shoot.html, _shoot-frame.html) is never published
foreach ($n in '_shoot.html', '_shoot-frame.html') {
    $pages = $base.Clone(); $pages["x\$n"] = $good
    $r = @(Test-SiteOutput (New-Site $pages) $c)
    Assert-Equal 1 $r.Count "leftover $n gives exactly one problem: $($r -join '; ')"
    Assert-True ($r[0] -like "x\${n}:*shoot*") "leftover $n message: $($r[0])"
}

# the 404 page is not shared: no preview needed
$pages = $base.Clone()
$pages['404.html'] = $good.Replace($share, '')
$r = @(Test-SiteOutput (New-Site $pages) $c)
Assert-Equal 0 $r.Count "404.html needs no share preview: $($r -join '; ')"
