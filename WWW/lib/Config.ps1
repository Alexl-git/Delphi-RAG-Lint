# Site configuration: reads and validates WWW\site.json.

function Read-SiteConfig([string]$Path) {
    $c = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($k in 'baseUrl', 'siteName', 'micronite', 'products', 'help', 'sidebarArticles') {
        if ($null -eq $c.$k) { throw "site.json: $k missing" }
    }
    foreach ($p in $c.products) {
        foreach ($k in 'id', 'name', 'repo', 'changelog', 'blurb') {
            if (-not $p.$k) { throw "site.json: products[].$k missing" }
        }
    }
    $c.baseUrl = $c.baseUrl.TrimEnd('/')
    $c
}
