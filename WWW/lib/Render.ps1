# Page renderer: escaping, menu, sidebar, footer and the page template.

# The full policy is sent as an HTTP header by web.config. The <meta> copy drops
# frame-ancestors, which browsers ignore (with a console warning) in <meta>.
$script:Csp = "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; connect-src https://api.github.com; frame-ancestors 'none'; base-uri 'self'; form-action 'none'; object-src 'none'"
$script:CspMeta = ($script:Csp -replace "frame-ancestors 'none'; ", '')
$script:TemplateDir = Join-Path $PSScriptRoot '..\templates'

function ConvertTo-HtmlText([string]$Text) {
    # Raw text in, safe HTML text out; every non-ASCII character becomes a numeric entity
    # (HtmlEncode alone leaves characters above U+00FF, e.g. smart quotes, as they are).
    $e = [Net.WebUtility]::HtmlEncode($Text)
    [regex]::Replace($e, '[\uD800-\uDBFF][\uDC00-\uDFFF]|[^\x00-\x7F]', { param($m) "&#$([char]::ConvertToUtf32($m.Value, 0));" })
}

# 7-bit ASCII bytes of a built file; throws "<source>:<line>: non-ASCII character U+XXXX"
# instead of letting an encoder write '?' in its place.
function ConvertTo-AsciiBytes([string]$Text, [string]$Source) {
    $m = [regex]::Match($Text, '[^\x00-\x7F]')
    if ($m.Success) {
        $line = 1 + ($Text.Substring(0, $m.Index).Split("`n").Count - 1)
        throw "${Source}:${line}: non-ASCII character U+$('{0:X4}' -f [int]$Text[$m.Index]) (write it as an HTML entity)"
    }
    [Text.Encoding]::ASCII.GetBytes($Text)
}

# web.config text from the source file. $NoRewrite is the HTTP 500 fallback: it drops the
# sections a shared IIS may lack or lock -- <rewrite> (URL Rewrite module) and <security>
# (removeServerHeader, IIS 10+) -- while the headers, errors and MIME map stay.
function New-WebConfigText([string]$Source, [bool]$NoRewrite) {
    [xml]$wc = $Source
    if ($NoRewrite) {
        foreach ($s in 'rewrite', 'security') {
            $n = $wc.configuration.'system.webServer'.$s
            if ($n) { [void]$n.ParentNode.RemoveChild($n) }
        }
    }
    $sw = [IO.StringWriter]::new()
    $wc.Save($sw)
    $sw.ToString() -replace 'encoding="utf-16"', 'encoding="us-ascii"'
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

# Open Graph + Twitter card tags: the preview LinkedIn, Slack etc. show for a shared link.
# Page keys: Title, Description, Path; optional Type ('article'), Image (site path).
function New-ShareTags($Config, [hashtable]$Page) {
    $t = ConvertTo-HtmlText $(if ($Page.Title) { $Page.Title } else { $Config.siteName })
    $img = $Config.baseUrl + $(if ($Page.Image) { $Page.Image } else { '/assets/share/default.png' })
    @(
        "<meta property=""og:site_name"" content=""$(ConvertTo-HtmlText $Config.siteName)"">"
        "<meta property=""og:type"" content=""$(if ($Page.Type -eq 'article') { 'article' } else { 'website' })"">"
        "<meta property=""og:title"" content=""$t"">"
        "<meta property=""og:description"" content=""$(ConvertTo-HtmlText $Page.Description)"">"
        "<meta property=""og:url"" content=""$($Config.baseUrl + $Page.Path)"">"
        "<meta property=""og:image"" content=""$img"">"
        '<meta name="twitter:card" content="summary_large_image">'
    ) -join "`n"
}

function Render-Page($Config, [hashtable]$Page) {
    $tpl = [IO.File]::ReadAllText((Join-Path $script:TemplateDir 'page.html'))
    $vals = @{
        share       = if ($Page.NoShare) { '' } else { New-ShareTags $Config $Page }
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
