. "$PSScriptRoot\..\lib\Config.ps1"
. "$PSScriptRoot\..\lib\Check.ps1"

$c = Read-SiteConfig "$PSScriptRoot\..\site.json"
$good = '<html><head><link rel="canonical" href="https://www.delphi-rag-lint.com/x/"><link rel="stylesheet" href="/assets/s.css"></head>' +
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
$base = @{ 'x\index.html' = $good; 'assets\s.css' = ''; 'assets\r.js' = '' }

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
}
foreach ($k in $cases.Keys) {
    $pages = $base.Clone(); $pages['bad\index.html'] = $cases[$k]
    $r = @(Test-SiteOutput (New-Site $pages) $c)
    Assert-Equal 1 $r.Count "case $k gives exactly one problem: $($r -join '; ')"
    Assert-True ($r[0] -like "bad\index.html:*$k*") "case $k message: $($r[0])"
}
