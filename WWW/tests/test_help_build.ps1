# Help trees: every .md becomes a clean-URL page, links and images resolve, groups come from index.json.
$out = New-TestDir
$fake = { param($argv) $global:LASTEXITCODE = 0; '{"tagName":"v1.2.3-alpha","publishedAt":"2026-10-19T07:00:00Z"}' }
& "$PSScriptRoot\..\build.ps1" -Out $out -ArticlesRoot "$PSScriptRoot\fixtures\articles" -ProductsRoot "$PSScriptRoot\fixtures\products" -HelpRoot "$PSScriptRoot\fixtures\help" -Gh $fake | Out-Null
Assert-Equal 0 $LASTEXITCODE 'build exit (the checker found no dangling help link)'

foreach ($f in 'help\demo\index.html', 'help\demo\options\alpha\index.html', 'help\demo\options\beta\index.html', 'help\demo\options\img\p.png') {
    Assert-True (Test-Path (Join-Path $out $f)) "missing $f"
}
$root = [IO.File]::ReadAllText("$out\help\demo\index.html")
Assert-True ($root.Contains('<h2 id="g1">Group &amp; one</h2>')) 'group heading from index.json'
Assert-True ($root.Contains('<a class="title" href="/help/demo/options/alpha/">Alpha &amp; Co</a><p>The alpha option.</p>')) 'option listed with its summary'
Assert-True ($root.Contains('<img src="/help/demo/options/img/p.png"')) 'image rewritten'
$a = [IO.File]::ReadAllText("$out\help\demo\options\alpha\index.html")
Assert-True ($a.Contains('href="/help/demo/options/beta/">Beta</a>')) 'sibling .md link rewritten'
Assert-True ($a.Contains('href="/help/demo/">home</a>')) '../index.md is the tree root'
Assert-True ($a.Contains('Default: <code>1</code> &middot; INI key: <code>Alpha</code>')) 'facts line'
Assert-True ($a.Contains('<pre><code>code &lt;x&gt;</code></pre>')) 'indented code escaped'
Assert-True ($a.Contains('<link rel="canonical" href="https://www.delphi-rag-lint.com/help/demo/options/alpha/">')) 'canonical'
Assert-True ([IO.File]::ReadAllText("$out\help\index.html").Contains('href="/help/demo/">Demo help</a>')) '/help/ lists the tree'
Assert-True ([IO.File]::ReadAllText("$out\sitemap.xml").Contains('/help/demo/options/alpha/')) 'sitemap has leaf'
