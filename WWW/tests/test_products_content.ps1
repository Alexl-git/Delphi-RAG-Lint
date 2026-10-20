# The real product pages (WWW\products) with the real site.json: approved wording, facts filled, pictures sized.
. (Join-Path $PSScriptRoot '..\lib\Config.ps1')
. (Join-Path $PSScriptRoot '..\lib\Products.ps1')
$cfg = Read-SiteConfig (Join-Path $PSScriptRoot '..\site.json')

$dl = Read-ProductPage (Join-Path $PSScriptRoot '..\products\dl\index.html') $cfg
$b = $dl.Body
foreach ($s in 'Delphi RAG lint knows your code.',
               'Embarcadero RAD Studio 13 Florence, VS Code, plus any editor that speaks LSP or MCP',
               '190 rules', '16 categories', '23 rules fix the code for you',
               'href="https://www.htrmicronite.com',
               'It also tells you that there <i>is</i> a needle in there') {
    Assert-True ($b.Contains($s)) "DL page contains '$s'"
}
foreach ($h in [regex]::Matches($b, '(?s)<h2[^>]*>(.*?)</h2>')) {
    Assert-True (-not ($h.Groups[1].Value -match '\b(eight|nine|ten|\d+) things\b')) "no counted heading: $($h.Groups[1].Value)"
}
foreach ($img in [regex]::Matches($b, '<img\b[^>]*>')) {
    foreach ($a in 'alt=', 'width=', 'height=') { Assert-True ($img.Value.Contains($a)) "$($img.Value) has $a" }
}
