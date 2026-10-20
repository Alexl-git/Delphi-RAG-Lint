# Product page reader. A product page is WWW\products\<id>\index.html: a metadata comment
# block, then the body fragment. {{fact:<name>}} in the body is filled from
# site.json products[<id>].facts, so a number like the rule count lives in one place.

$script:ProductKeys = 'id', 'title', 'summary'

function Get-LineAt([string]$Text, [int]$Index) { ($Text.Substring(0, $Index) -split "`n").Count }

function Read-ProductPage([string]$Path, $Config) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -gt 0x7F) {
            $line = 1 + @($bytes[0..([Math]::Max(0, $i - 1))] | Where-Object { $_ -eq 10 }).Count
            throw "${Path}:${line}: non-ASCII byte 0x$('{0:X2}' -f $bytes[$i]) (write it as an HTML entity)"
        }
    }
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $m = [regex]::Match($text, '\A<!--product\r?\n(?<meta>[\s\S]*?)\r?\n-->\r?\n?')
    if (-not $m.Success) { throw "${Path}:1: missing <!--product ... --> block on line 1" }
    $meta = @{}
    foreach ($l in $m.Groups['meta'].Value -split '\r?\n') {
        if ($l -match '^(?<k>[a-z]+):\s*(?<v>.*?)\s*$') { $meta[$Matches.k] = $Matches.v }
    }
    foreach ($k in $script:ProductKeys) {
        if (-not $meta[$k]) { throw "${Path}:1: $k missing in the product block" }
    }
    $dir = Split-Path $Path -Parent
    if ((Split-Path $dir -Leaf) -ne $meta.id) { throw "${Path}:1: folder must be named $($meta.id) (the product id)" }
    $product = @($Config.products | Where-Object { $_.id -eq $meta.id })[0]
    if (-not $product) { throw "${Path}:1: product id '$($meta.id)' is not in site.json products" }
    $body = $text.Substring($m.Length)
    $bad = [regex]::Match($body, '<script|<style|\sstyle\s*=', 'IgnoreCase')
    if ($bad.Success) {
        throw "${Path}:$(Get-LineAt $text ($m.Length + $bad.Index)): forbidden markup '$($bad.Value.Trim())' (no scripts, <style> or style= in product pages)"
    }
    # Anywhere in the body: the approved product pages carry it in their "Built for our own work" section.
    if (-not $body.Contains('href="https://www.htrmicronite.com')) {
        throw "${Path}: no Micronite mention (a link to https://www.htrmicronite.com)"
    }
    if ($meta.image -and ($meta.image -notmatch '^[a-z0-9][a-z0-9-]*\.(png|jpe?g)$' -or -not (Test-Path -LiteralPath (Join-Path $dir $meta.image)))) {
        throw "${Path}:1: image '$($meta.image)' must be a .png or .jpg file in the product folder"
    }
    # Facts fill the body and the title / summary lines of the block alike; scanning the whole
    # text gives every unknown fact its own line number.
    foreach ($f in [regex]::Matches($text, '\{\{fact:(\w+)\}\}')) {
        $name = $f.Groups[1].Value
        if ($null -eq $product.facts -or $null -eq $product.facts.$name) {
            throw "${Path}:$(Get-LineAt $text $f.Index): unknown fact '$name' (add it to site.json products[$($meta.id)].facts)"
        }
    }
    $fill = { param([string]$s) [regex]::Replace($s, '\{\{fact:(\w+)\}\}', { param($x) [string]$product.facts.($x.Groups[1].Value) }) }
    [pscustomobject]@{
        Id = $meta.id; Title = (& $fill $meta.title); Summary = (& $fill $meta.summary); Image = $meta.image; Body = (& $fill $body); Dir = $dir
    }
}

# One page per site.json product, in site.json order; a product without a page is an error,
# and so is a product folder with no site.json product (it would never be published).
function Get-ProductPages([string]$Root, $Config) {
    $ids = @($Config.products | ForEach-Object { $_.id })
    foreach ($d in Get-ChildItem -LiteralPath $Root -Directory) {
        if ($d.Name -notin $ids) { throw "products: folder '$($d.Name)' has no site.json product (add it to site.json products, or remove $($d.FullName))" }
    }
    foreach ($p in $Config.products) {
        $f = Join-Path (Join-Path $Root $p.id) 'index.html'
        if (-not (Test-Path -LiteralPath $f)) { throw "products: no page for site.json product '$($p.id)' (expected $f)" }
        Read-ProductPage $f $Config
    }
}
