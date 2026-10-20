. "$PSScriptRoot\..\lib\Config.ps1"

$c = Read-SiteConfig "$PSScriptRoot\..\site.json"
Assert-Equal 'https://www.delphi-rag-lint.com' $c.baseUrl 'baseUrl'
Assert-Equal 2 $c.products.Count 'product count'
Assert-Equal 'dl' $c.products[0].id 'first product'
Assert-Equal 'Alexl-git/YADF' $c.products[1].repo 'yadf repo'
Assert-Equal 'https://www.htrmicronite.com' $c.micronite.url 'micronite url'
Assert-Equal 8 $c.sidebarArticles 'sidebarArticles'

$d = New-TestDir
$j = Get-Content "$PSScriptRoot\..\site.json" -Raw | ConvertFrom-Json
$j.PSObject.Properties.Remove('products')
$p = Join-Path $d 'site.json'
$j | ConvertTo-Json -Depth 5 | Set-Content $p
Assert-Throws { Read-SiteConfig $p } '*products missing*'
