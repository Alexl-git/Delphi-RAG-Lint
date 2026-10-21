# Builds the static site into -Out (default WWW\_site) and checks it.
# Exit 0 = clean site; exit 1 = a lookup failed or the checker found problems.
param(
    [string]$Out = (Join-Path $PSScriptRoot '_site'),
    [string]$ArticlesRoot = (Join-Path $PSScriptRoot 'articles'),
    [string]$ProductsRoot = (Join-Path $PSScriptRoot 'products'),
    [string]$HelpRoot = (Join-Path $PSScriptRoot 'help'),
    [switch]$NoRewrite,
    [scriptblock]$Gh = { param($argv) & gh @argv }
)
$ErrorActionPreference = 'Stop'
foreach ($l in 'Config', 'Releases', 'Articles', 'Products', 'Render', 'Help', 'Check') { . (Join-Path $PSScriptRoot "lib\$l.ps1") }

function Write-SiteFile([string]$RelPath, [string]$Text) {
    $p = Join-Path $Out $RelPath
    [void][IO.Directory]::CreateDirectory((Split-Path $p -Parent))
    [IO.File]::WriteAllBytes($p, (ConvertTo-AsciiBytes ($Text -replace "\r?\n", "`r`n") $RelPath))
}

try {
    $cfg = Read-SiteConfig (Join-Path $PSScriptRoot 'site.json')
    $releases = @($cfg.products | ForEach-Object { Get-ReleaseInfo $_ $Gh })
    $articles = @(Get-Articles $ArticlesRoot)
    if ($articles.Count -eq 0) { throw "no articles under $ArticlesRoot" }
    $products = @(Get-ProductPages $ProductsRoot $cfg)

    if (Test-Path -LiteralPath $Out) { [IO.Directory]::Delete($Out, $true) }
    [void][IO.Directory]::CreateDirectory($Out)
    $pages = [Collections.Generic.List[string]]::new()

    function Add-Page([string]$Path, [string]$Title, [string]$Description, [string]$Main, [string]$Skip = '', [hashtable]$More = @{}) {
        $page = @{ Title = $Title; Description = $Description; Path = $Path; Main = $Main
                   Sidebar = (New-Sidebar $cfg $releases $articles -Skip $Skip); NoShare = ($Path -eq '/404.html') }
        foreach ($k in $More.Keys) { $page[$k] = $More[$k] }
        $html = Render-Page $cfg $page
        $file = if ($Path.EndsWith('/')) { $Path.TrimStart('/') + 'index.html' } else { $Path.TrimStart('/') }
        Write-SiteFile $file.Replace('/', '\') $html
        if ($Path -ne '/404.html') { $pages.Add($Path) }
    }

    $newest = $articles[0]
    Add-Page '/' '' $newest.Summary $newest.Body $newest.Slug
    foreach ($a in $articles) {
        $more = @{ Type = 'article' }
        if ($a.Image) { $more.Image = "/articles/$($a.Slug)/$($a.Image)" }
        Add-Page "/articles/$($a.Slug)/" $a.Title $a.Summary $a.Body $a.Slug $more
        if ($a.Image) { Copy-Item -LiteralPath (Join-Path $a.Dir $a.Image) -Destination (Join-Path $Out "articles\$($a.Slug)\") }
    }

    foreach ($p in $products) {
        $more = @{}
        if ($p.Image) { $more.Image = "/products/$($p.Id)/$($p.Image)" }
        Add-Page "/products/$($p.Id)/" $p.Title $p.Summary $p.Body '' $more
        Get-ChildItem -LiteralPath $p.Dir -File | Where-Object { $_.Extension -in '.png', '.jpg', '.jpeg' } |
            Copy-Item -Destination (Join-Path $Out "products\$($p.Id)\")
    }
    $pl = foreach ($p in $cfg.products) {
        "<li><a class=""title"" href=""/products/$($p.id)/"">$(ConvertTo-HtmlText $p.name)</a><p>$(ConvertTo-HtmlText $p.blurb)</p></li>"
    }
    Add-Page '/products/' 'Products' 'DL (drag-lint) and YADF.' "<div class=""page""><h1>Products</h1><ul class=""list"">$($pl -join "`n")</ul></div>"
    $li = foreach ($a in $articles) {
        "<li><a class=""title"" href=""/articles/$($a.Slug)/"">$(ConvertTo-HtmlText $a.Title)</a><span class=""meta"">$($a.Date)</span><p>$(ConvertTo-HtmlText $a.Summary)</p></li>"
    }
    Add-Page '/articles/' 'Articles' 'All articles, newest first.' "<div class=""page""><h1>Articles</h1><ul class=""list"">$($li -join "`n")</ul></div>"

    $prod = for ($i = 0; $i -lt $cfg.products.Count; $i++) {
        $p = $cfg.products[$i]; $r = $releases[$i]
        "<div class=""product"" data-repo=""$($p.repo)""><h2><a href=""/products/$($p.id)/"">$(ConvertTo-HtmlText $p.name)</a></h2><p>$(ConvertTo-HtmlText $p.blurb)</p>" +
        "<span class=""meta"">Latest: <span class=""rel-tag"">$(ConvertTo-HtmlText $r.Tag)</span> - <span class=""rel-date"">$($r.Date)</span></span>" +
        "<a class=""btn"" href=""$($r.Url)"">Download (GitHub release)</a><a class=""btn"" href=""$($r.Changelog)"">Change log</a></div>"
    }
    Add-Page '/downloads/' 'Downloads' 'Latest releases of DL (drag-lint) and YADF.' "<div class=""page""><h1>Downloads</h1>$($prod -join "`n")</div>"

    $trees = @(Get-HelpTrees $HelpRoot)
    foreach ($t in $trees) {
        foreach ($pg in $t.Pages) { Add-Page $pg.Path $pg.Title $pg.Summary $pg.Main }
        foreach ($f in $t.Files) {
            $dest = Join-Path $Out ('help\' + $f.Rel.Replace('/', '\'))
            [void][IO.Directory]::CreateDirectory((Split-Path $dest -Parent))
            Copy-Item -LiteralPath $f.SrcFull -Destination $dest
        }
    }
    $hl = @(foreach ($t in $trees) {
        "<li><a class=""title"" href=""/help/$($t.Product)/"">$(ConvertTo-HtmlText $t.Title)</a>$(if ($t.Summary) { '<p>' + (ConvertTo-HtmlText $t.Summary) + '</p>' })</li>"
    }) + @(foreach ($h in $cfg.help) { "<li><a class=""title"" href=""$($h.url)"">$(ConvertTo-HtmlText $h.title)</a></li>" })
    Add-Page '/help/' 'Help' 'Manuals and wikis.' "<div class=""page""><h1>Help</h1><ul class=""list"">$($hl -join "`n")</ul></div>"

    $cl = foreach ($p in $cfg.products) {
        $s = ConvertTo-HtmlText (Get-ShortName $p)
        "<li><a class=""title"" href=""https://github.com/$($p.repo)/discussions"">$s discussions</a><p>Questions, ideas and show-and-tell, on GitHub.</p></li>" +
        "<li><a class=""title"" href=""https://github.com/$($p.repo)/issues"">$s bug reports</a><p>Report a bug or ask for a feature, on GitHub.</p></li>"
    }
    Add-Page '/community/' 'Community' 'Discussions and bug reports.' "<div class=""page""><h1>Community</h1><ul class=""list"">$($cl -join "`n")</ul></div>"

    Add-Page '/404.html' 'Page not found' 'Page not found.' ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'templates\404.html')))

    $urls = foreach ($p in $pages) { "  <url><loc>$($cfg.baseUrl)$p</loc></url>" }
    Write-SiteFile 'sitemap.xml' ("<?xml version=""1.0"" encoding=""UTF-8""?>`n<urlset xmlns=""http://www.sitemaps.org/schemas/sitemap/0.9"">`n" + ($urls -join "`n") + "`n</urlset>`n")
    Write-SiteFile 'robots.txt' "User-agent: *`nAllow: /`nSitemap: $($cfg.baseUrl)/sitemap.xml`n"

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'assets') -Destination $Out -Recurse
    $wcSrc = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'web.config'))
    Write-SiteFile 'web.config' (New-WebConfigText $wcSrc $NoRewrite)
    # IONOS IIS lacks URL Rewrite but runs an .htaccess add-on (it answers 302 whatever the flag).
    # Keep the host test to ^www\. : the full host pattern made www redirect to itself (live, 2026-10-20).
    Write-SiteFile '.htaccess' ("RewriteEngine On`nRewriteCond %{SERVER_PORT} !=443 [OR]`nRewriteCond %{HTTP_HOST} !^www\. [NC]`n" +
        "RewriteRule ^/?(.*)$ $($cfg.baseUrl)/`$1 [L,R=301]`n")

    $problems = @(Test-SiteOutput $Out $cfg)
    if ($problems.Count) { $problems | ForEach-Object { Write-Host "CHECK $_" }; throw "$($problems.Count) site check problem(s)" }
    Write-Host "built $($pages.Count) pages + 404 into $Out"
    exit 0
} catch {
    Write-Host "BUILD FAILED: $($_.Exception.Message)"
    exit 1
}
