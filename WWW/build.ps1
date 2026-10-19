# Builds the static site into -Out (default WWW\_site) and checks it.
# Exit 0 = clean site; exit 1 = a lookup failed or the checker found problems.
param(
    [string]$Out = (Join-Path $PSScriptRoot '_site'),
    [string]$ArticlesRoot = (Join-Path $PSScriptRoot 'articles'),
    [switch]$NoRewrite,
    [scriptblock]$Gh = { param($argv) & gh @argv }
)
$ErrorActionPreference = 'Stop'
foreach ($l in 'Config', 'Releases', 'Articles', 'Render', 'Check') { . (Join-Path $PSScriptRoot "lib\$l.ps1") }

function Write-SiteFile([string]$RelPath, [string]$Text) {
    $p = Join-Path $Out $RelPath
    [void][IO.Directory]::CreateDirectory((Split-Path $p -Parent))
    [IO.File]::WriteAllText($p, ($Text -replace "\r?\n", "`r`n"), [Text.ASCIIEncoding]::new())
}

try {
    $cfg = Read-SiteConfig (Join-Path $PSScriptRoot 'site.json')
    $releases = @($cfg.products | ForEach-Object { Get-ReleaseInfo $_ $Gh })
    $articles = @(Get-Articles $ArticlesRoot)
    if ($articles.Count -eq 0) { throw "no articles under $ArticlesRoot" }

    if (Test-Path -LiteralPath $Out) { [IO.Directory]::Delete($Out, $true) }
    [void][IO.Directory]::CreateDirectory($Out)
    $pages = [Collections.Generic.List[string]]::new()

    function Add-Page([string]$Path, [string]$Title, [string]$Description, [string]$Main, [string]$Skip = '') {
        $html = Render-Page $cfg @{ Title = $Title; Description = $Description; Path = $Path; Main = $Main
                                    Sidebar = (New-Sidebar $cfg $releases $articles -Skip $Skip) }
        $file = if ($Path.EndsWith('/')) { $Path.TrimStart('/') + 'index.html' } else { $Path.TrimStart('/') }
        Write-SiteFile $file.Replace('/', '\') $html
        if ($Path -ne '/404.html') { $pages.Add($Path) }
    }

    $newest = $articles[0]
    Add-Page '/' '' $newest.Summary $newest.Body $newest.Slug
    foreach ($a in $articles) { Add-Page "/articles/$($a.Slug)/" $a.Title $a.Summary $a.Body $a.Slug }

    $li = foreach ($a in $articles) {
        "<li><a class=""title"" href=""/articles/$($a.Slug)/"">$(ConvertTo-HtmlText $a.Title)</a><span class=""meta"">$($a.Date)</span><p>$(ConvertTo-HtmlText $a.Summary)</p></li>"
    }
    Add-Page '/articles/' 'Articles' 'All articles, newest first.' "<div class=""page""><h1>Articles</h1><ul class=""list"">$($li -join "`n")</ul></div>"

    $prod = for ($i = 0; $i -lt $cfg.products.Count; $i++) {
        $p = $cfg.products[$i]; $r = $releases[$i]
        "<div class=""product"" data-repo=""$($p.repo)""><h2>$(ConvertTo-HtmlText $p.name)</h2><p>$(ConvertTo-HtmlText $p.blurb)</p>" +
        "<span class=""meta"">Latest: <span class=""rel-tag"">$(ConvertTo-HtmlText $r.Tag)</span> - <span class=""rel-date"">$($r.Date)</span></span>" +
        "<a class=""btn"" href=""$($r.Url)"">Download (GitHub release)</a><a class=""btn"" href=""$($r.Changelog)"">Change log</a></div>"
    }
    Add-Page '/downloads/' 'Downloads' 'Latest releases of DL (drag-lint) and YADF.' "<div class=""page""><h1>Downloads</h1>$($prod -join "`n")</div>"

    $hl = foreach ($h in $cfg.help) { "<li><a class=""title"" href=""$($h.url)"">$(ConvertTo-HtmlText $h.title)</a></li>" }
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
    [xml]$wc = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'web.config'))
    if ($NoRewrite) { $n = $wc.configuration.'system.webServer'.rewrite; [void]$n.ParentNode.RemoveChild($n) }
    $wc.Save((Join-Path $Out 'web.config'))

    $problems = @(Test-SiteOutput $Out $cfg)
    if ($problems.Count) { $problems | ForEach-Object { Write-Host "CHECK $_" }; throw "$($problems.Count) site check problem(s)" }
    Write-Host "built $($pages.Count) pages + 404 into $Out"
    exit 0
} catch {
    Write-Host "BUILD FAILED: $($_.Exception.Message)"
    exit 1
}
