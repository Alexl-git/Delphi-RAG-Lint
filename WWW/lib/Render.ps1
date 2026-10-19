# Page renderer: escaping, menu, sidebar, footer and the page template.

# The full policy is sent as an HTTP header by web.config. The <meta> copy drops
# frame-ancestors, which browsers ignore (with a console warning) in <meta>.
$script:Csp = "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; connect-src https://api.github.com; frame-ancestors 'none'; base-uri 'self'; form-action 'none'; object-src 'none'"
$script:CspMeta = ($script:Csp -replace "frame-ancestors 'none'; ", '')
$script:TemplateDir = Join-Path $PSScriptRoot '..\templates'

function ConvertTo-HtmlText([string]$Text) {
    # Raw text in, safe HTML text out; non-ASCII becomes numeric entities.
    [Net.WebUtility]::HtmlEncode($Text)
}

function Get-ShortName($Product) { if ($Product.short) { $Product.short } else { $Product.name } }

function New-Menu($Config) {
    $m = $Config.micronite
    '<nav class="menu"><a href="/articles/">Articles</a><a href="/downloads/">Downloads</a>' +
    '<a href="/help/">Help</a><a href="/community/">Community</a>' +
    "<a class=""htr"" href=""$($m.url)"">$(ConvertTo-HtmlText $m.name)</a></nav>"
}

function New-ReleaseBox($Product, $Release) {
    "<div class=""dl"" data-repo=""$($Product.repo)""><a class=""dl-name"" href=""$($Release.Url)"">$(ConvertTo-HtmlText $Product.name)</a>" +
    "<span class=""meta""><span class=""rel-tag"">$(ConvertTo-HtmlText $Release.Tag)</span> - <span class=""rel-date"">$($Release.Date)</span></span>" +
    "<a class=""meta"" href=""$($Release.Changelog)"">Change log</a></div>"
}

function New-Sidebar($Config, $Releases, $Articles, [string]$Skip = '') {
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append('<h4>Download</h4>')
    for ($i = 0; $i -lt $Config.products.Count; $i++) {
        [void]$sb.Append((New-ReleaseBox $Config.products[$i] $Releases[$i]))
    }
    [void]$sb.Append('<h4>Help</h4><ul>')
    foreach ($h in $Config.help) { [void]$sb.Append("<li><a href=""$($h.url)"">$(ConvertTo-HtmlText $h.title)</a></li>") }
    [void]$sb.Append('</ul><h4>Community</h4><ul>')
    foreach ($p in $Config.products) {
        $s = ConvertTo-HtmlText (Get-ShortName $p)
        [void]$sb.Append("<li><a href=""https://github.com/$($p.repo)/discussions"">$s discussions</a></li>")
        [void]$sb.Append("<li><a href=""https://github.com/$($p.repo)/issues"">$s bug reports</a></li>")
    }
    [void]$sb.Append('</ul><h4>Articles</h4><ul>')
    foreach ($a in @($Articles | Where-Object { $_.Slug -ne $Skip }) | Select-Object -First $Config.sidebarArticles) {
        [void]$sb.Append("<li><a href=""/articles/$($a.Slug)/"">$(ConvertTo-HtmlText $a.Title)</a><span class=""meta"">$($a.Date)</span></li>")
    }
    [void]$sb.Append('<li><a href="/articles/">All articles</a></li></ul>')
    $m = $Config.micronite
    [void]$sb.Append("<div class=""htr-box"">Our main product: <a href=""$($m.url)"">$($m.url -replace '^https?://', '')</a></div>")
    $sb.ToString()
}

function New-Footer($Config) {
    $m = $Config.micronite
    "<footer class=""site-foot""><span>(c) 2026 $(ConvertTo-HtmlText $m.name)</span><a href=""$($m.url)"">$($m.url -replace '^https?://', '')</a></footer>"
}

function Render-Page($Config, [hashtable]$Page) {
    $tpl = [IO.File]::ReadAllText((Join-Path $script:TemplateDir 'page.html'))
    $vals = @{
        title       = if ($Page.Title) { "$(ConvertTo-HtmlText $Page.Title) - $($Config.siteName)" } else { $Config.siteName }
        description = ConvertTo-HtmlText $Page.Description
        canonical   = $Config.baseUrl + $Page.Path
        csp         = $script:CspMeta
        menu        = New-Menu $Config
        main        = $Page.Main
        sidebar     = $Page.Sidebar
        footer      = New-Footer $Config
    }
    # One pass, so placeholder-like text inside content is never substituted.
    [regex]::Replace($tpl, '\{\{(\w+)\}\}', { param($m) $vals[$m.Groups[1].Value] })
}
