$out = New-TestDir
$fake = { param($argv) $global:LASTEXITCODE = 0; '{"tagName":"v1.2.3-alpha","publishedAt":"2026-10-19T07:00:00Z"}' }
& "$PSScriptRoot\..\build.ps1" -Out $out -ArticlesRoot "$PSScriptRoot\fixtures\articles" -ProductsRoot "$PSScriptRoot\fixtures\products" -Gh $fake | Out-Null
Assert-Equal 0 $LASTEXITCODE 'build exit'

foreach ($f in 'index.html', 'articles\index.html', 'articles\newest\index.html', 'articles\a-one\index.html',
               'downloads\index.html', 'help\index.html', 'community\index.html', '404.html', 'sitemap.xml',
               'products\dl\index.html', 'products\dl\pic.png', 'products\yadf\index.html',
               'robots.txt', 'web.config', '.htaccess', 'assets\style.css', 'assets\releases.js') {
    Assert-True (Test-Path (Join-Path $out $f)) "missing $f"
}
# IONOS IIS has no URL Rewrite module but honours .htaccess: http and the bare host go to baseUrl
$ht = [IO.File]::ReadAllText("$out\.htaccess")
Assert-True ($ht.Contains('RewriteCond %{SERVER_PORT} !=443 [OR]')) '.htaccess: http redirected'
Assert-True ($ht.Contains('RewriteCond %{HTTP_HOST} !^www\. [NC]')) '.htaccess: bare host redirected (short pattern: the full one looped live)'
Assert-True ($ht.Contains('RewriteRule ^/?(.*)$ https://www.delphi-rag-lint.com/$1 [L,R=301]')) '.htaccess: target keeps the path'
$idx = [IO.File]::ReadAllText("$out\index.html")
Assert-True ($idx.Contains('Newest fixture &amp; friends')) 'home shows newest article'
Assert-True ($idx.Contains('<title>Delphi-RAG-Lint</title>')) 'home title'
Assert-True ([IO.File]::ReadAllText("$out\sitemap.xml").Contains('<loc>https://www.delphi-rag-lint.com/downloads/</loc>')) 'sitemap'
Assert-True ([IO.File]::ReadAllText("$out\robots.txt").Contains('Sitemap: https://www.delphi-rag-lint.com/sitemap.xml')) 'robots'
$dlp = [IO.File]::ReadAllText("$out\downloads\index.html")
Assert-True ($dlp.Contains('href="https://github.com/Alexl-git/YADF/releases/latest"')) 'download link'
Assert-True ($dlp.Contains('v1.2.3-alpha')) 'version on downloads'
Assert-True ($idx.Contains('<nav class="menu"><a href="/products/">Products</a><a href="/articles/">')) 'Products first in the menu'
Assert-True (Test-Path "$out\products\index.html") 'products index exists'
Assert-True ([IO.File]::ReadAllText("$out\products\index.html").Contains('href="/products/yadf/"')) 'products index lists yadf'
Assert-True ($dlp.Contains('<h2><a href="/products/dl/">DL (drag-lint)</a></h2>')) 'downloads name links to product page'
Assert-True ($idx.Contains('class="dl-name" href="/products/dl/"')) 'sidebar name links to product page'
Assert-True ($idx.Contains('<a class="meta" href="https://github.com/Alexl-git/YADF/releases/latest">Download</a>')) 'sidebar Download link'
Assert-True ([IO.File]::ReadAllText("$out\sitemap.xml").Contains('<loc>https://www.delphi-rag-lint.com/products/</loc>')) 'sitemap has products index'

[xml]$w = [IO.File]::ReadAllText("$out\web.config")
$csp = $w.configuration.'system.webServer'.httpProtocol.customHeaders.add | Where-Object name -eq 'Content-Security-Policy'
Assert-Equal "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; connect-src https://api.github.com; frame-ancestors 'none'; base-uri 'self'; form-action 'none'; object-src 'none'" $csp.value 'CSP header'
Assert-True ($null -ne $w.configuration.'system.webServer'.rewrite) 'rewrite present'

$out2 = New-TestDir
& "$PSScriptRoot\..\build.ps1" -Out $out2 -ArticlesRoot "$PSScriptRoot\fixtures\articles" -ProductsRoot "$PSScriptRoot\fixtures\products" -Gh $fake -NoRewrite | Out-Null
[xml]$w2 = [IO.File]::ReadAllText("$out2\web.config")
Assert-True ($null -eq $w2.configuration.'system.webServer'.rewrite) '-NoRewrite strips rewrite'

# a failing release lookup aborts the build
$out3 = New-TestDir
$bad = { param($argv) $global:LASTEXITCODE = 1; '' }
& "$PSScriptRoot\..\build.ps1" -Out $out3 -ArticlesRoot "$PSScriptRoot\fixtures\articles" -ProductsRoot "$PSScriptRoot\fixtures\products" -Gh $bad *>$null
Assert-Equal 1 $LASTEXITCODE 'build fails when gh fails'
Assert-True ([IO.File]::ReadAllText("$out\sitemap.xml").Contains('<loc>https://www.delphi-rag-lint.com/products/dl/</loc>')) 'sitemap has product page'
Assert-True ([IO.File]::ReadAllText("$out\products\dl\index.html").Contains('<title>DL fixture - Delphi-RAG-Lint</title>')) 'product page title'

# a product page whose picture is missing fails the build (dangling-link check)
$pr = New-TestDir
Copy-Item "$PSScriptRoot\fixtures\products\*" $pr -Recurse
[IO.File]::Delete("$pr\dl\pic.png")
$out4 = New-TestDir
& "$PSScriptRoot\..\build.ps1" -Out $out4 -ArticlesRoot "$PSScriptRoot\fixtures\articles" -ProductsRoot $pr -Gh $fake *>$null
Assert-Equal 1 $LASTEXITCODE 'build fails on a missing product picture'

# a product folder with no site.json product fails the build (it would otherwise never be published)
$pr2 = New-TestDir
Copy-Item "$PSScriptRoot\fixtures\products\*" $pr2 -Recurse
Copy-Item "$pr2\yadf" "$pr2\zzz" -Recurse
$out5 = New-TestDir
$msg = & "$PSScriptRoot\..\build.ps1" -Out $out5 -ArticlesRoot "$PSScriptRoot\fixtures\articles" -ProductsRoot $pr2 -Gh $fake *>&1
Assert-Equal 1 $LASTEXITCODE 'build fails on a product folder not in site.json'
Assert-True ("$msg" -like '*zzz*') "failure names the folder: $msg"
