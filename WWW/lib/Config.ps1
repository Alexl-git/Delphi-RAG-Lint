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
        # optional named numbers/strings for {{fact:<name>}} in the product page
        if ($null -ne $p.facts -and ($p.facts.GetType().Name -ne 'PSCustomObject' -or
                @($p.facts.PSObject.Properties | Where-Object { $_.Value -isnot [string] -and $_.Value -isnot [ValueType] }).Count)) {
            throw "site.json: products[].facts must be an object of numbers or strings"
        }
    }
    $c.baseUrl = $c.baseUrl.TrimEnd('/')
    $c
}
