. "$PSScriptRoot\..\lib\Config.ps1"
. "$PSScriptRoot\..\lib\Articles.ps1"
. "$PSScriptRoot\..\lib\Render.ps1"

$c = Read-SiteConfig "$PSScriptRoot\..\site.json"
$rel = @(
    [pscustomobject]@{ Tag = 'v9.9.9-alpha'; Date = '2026-10-19'; Url = 'https://github.com/Alexl-git/Delphi-RAG-Lint/releases/latest'; Changelog = $c.products[0].changelog },
    [pscustomobject]@{ Tag = '1.0.99.0'; Date = '2026-10-18'; Url = 'https://github.com/Alexl-git/YADF/releases/latest'; Changelog = $c.products[1].changelog }
)
$arts = Get-Articles "$PSScriptRoot\fixtures\articles"
$tricky = [pscustomobject]@{ Title = 'A & B <c> "d"'; Date = '2026-10-04'; Slug = 'tricky'; Summary = 'S & T'; Body = '<p>x</p>'; Dir = '' }
$arts2 = @($arts[0], $tricky) + $arts[1..2]

# test_render_escapes
Assert-Equal 'A &amp; B &lt;c&gt; &quot;d&quot;' (ConvertTo-HtmlText 'A & B <c> "d"') 'escape'
$side = New-Sidebar $c $rel $arts2 -Skip 'newest'
Assert-True ($side.Contains('A &amp; B &lt;c&gt; &quot;d&quot;')) 'sidebar escapes the title'
Assert-True (-not $side.Contains('A & B <c>')) 'no raw title in sidebar'
$page = Render-Page $c @{ Title = $tricky.Title; Description = $tricky.Summary; Path = '/articles/tricky/'; Main = '<p>m</p>'; Sidebar = $side }
Assert-True ($page.Contains('<title>A &amp; B &lt;c&gt; &quot;d&quot; - Delphi-RAG-Lint</title>')) 'title escaped'
Assert-True ($page.Contains('content="S &amp; T"')) 'description escaped'

# test_page_has_micronite_and_canonical
$n = ([regex]::Matches($page, [regex]::Escape('href="https://www.htrmicronite.com"'))).Count
Assert-True ($n -ge 2) "micronite links: $n"
Assert-True ($page.Contains('<link rel="canonical" href="https://www.delphi-rag-lint.com/articles/tricky/">')) 'canonical'
$homePage = Render-Page $c @{ Title = ''; Description = 'd'; Path = '/'; Main = ''; Sidebar = '' }
Assert-True ($homePage.Contains('<title>Delphi-RAG-Lint</title>')) 'home title is the site name'

# test_sidebar_has_four_community_links
foreach ($u in 'https://github.com/Alexl-git/Delphi-RAG-Lint/discussions', 'https://github.com/Alexl-git/Delphi-RAG-Lint/issues',
               'https://github.com/Alexl-git/YADF/discussions', 'https://github.com/Alexl-git/YADF/issues') {
    Assert-True ($side.Contains("href=""$u""")) "community link $u"
}

# test_sidebar_release_markup
Assert-True ($side.Contains('data-repo="Alexl-git/YADF"')) 'data-repo'
Assert-True ($side -match 'class="rel-tag">1\.0\.99\.0<') 'yadf tag'
Assert-True ($side -match 'class="rel-date">2026-10-19<') 'dl date'
Assert-True ($side.Contains($c.products[0].changelog)) 'change log link'
Assert-True (-not $side.Contains('/articles/newest/')) 'article shown in main is skipped'
Assert-True ($side.Contains('href="/articles/"')) 'all articles link'

# sidebar respects sidebarArticles
$many = 1..12 | ForEach-Object { [pscustomobject]@{ Title = "T$_"; Date = '2026-01-01'; Slug = "s$_"; Summary = ''; Body = ''; Dir = '' } }
$s2 = New-Sidebar $c $rel $many
Assert-Equal 8 ([regex]::Matches($s2, 'href="/articles/s\d+/"')).Count 'sidebar article count'

# test_no_placeholder_left + menu
Assert-True (-not $page.Contains('{{')) 'no placeholder'
foreach ($m in 'Articles', 'Downloads', 'Help', 'Community', 'HTR Micronite') {
    Assert-True ($page -match ">$m</a>") "menu item $m"
}
Assert-True ($page.Contains('(c) 2026 HTR Micronite')) 'footer'
