# Article reader. An article is WWW\articles\<yyyy-MM-dd>-<slug>\index.html:
# a metadata comment block, then the body fragment. Values are raw text.

$script:ArticleKeys = 'title', 'date', 'slug', 'summary'

function Read-Article([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -gt 0x7F) {
            $line = 1 + @($bytes[0..([Math]::Max(0, $i - 1))] | Where-Object { $_ -eq 10 }).Count
            throw "${Path}:${line}: non-ASCII byte 0x$('{0:X2}' -f $bytes[$i]) (write it as an HTML entity)"
        }
    }
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $m = [regex]::Match($text, '\A<!--article\r?\n(?<meta>[\s\S]*?)\r?\n-->\r?\n?')
    if (-not $m.Success) { throw "${Path}:1: missing <!--article ... --> block on line 1" }
    $meta = @{}
    foreach ($l in $m.Groups['meta'].Value -split '\r?\n') {
        if ($l -match '^(?<k>[a-z]+):\s*(?<v>.*?)\s*$') { $meta[$Matches.k] = $Matches.v }
    }
    foreach ($k in $script:ArticleKeys) {
        if (-not $meta[$k]) { throw "${Path}:1: $k missing in the article block" }
    }
    foreach ($k in 'title', 'summary') {
        if ($meta[$k] -match '&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);') {
            throw "${Path}:1: $k contains the entity '$($Matches[0])': title and summary are plain ASCII text, they are escaped for you"
        }
    }
    if ($meta.date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "${Path}:1: date must be yyyy-MM-dd" }
    if ($meta.slug -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { throw "${Path}:1: slug must be lowercase words joined by hyphens" }
    $dir = Split-Path $Path -Parent
    $folder = Split-Path $dir -Leaf
    if ($folder -ne "$($meta.date)-$($meta.slug)") { throw "${Path}:1: folder must be named $($meta.date)-$($meta.slug)" }
    $body = $text.Substring($m.Length)
    $bad = [regex]::Match($body, '<script|<style|\sstyle\s*=', 'IgnoreCase')
    if ($bad.Success) {
        $line = 1 + ($text.Substring(0, $m.Length + $bad.Index) -split "`n").Count - 1
        throw "${Path}:${line}: forbidden markup '$($bad.Value.Trim())' (no scripts, <style> or style= in articles)"
    }
    if (-not $body.Substring(0, [Math]::Min(3000, $body.Length)).Contains('href="https://www.htrmicronite.com')) {
        throw "${Path}: no Micronite mention near the top (a link to https://www.htrmicronite.com in the first 3000 characters; see ARTICLE-RULES.md)"
    }
    [pscustomobject]@{
        Title = $meta.title; Date = $meta.date; Slug = $meta.slug; Summary = $meta.summary
        Body = $body; Dir = $dir
    }
}

function Get-Articles([string]$Root) {
    $list = foreach ($d in Get-ChildItem -LiteralPath $Root -Directory) {
        $p = Join-Path $d.FullName 'index.html'
        if (Test-Path -LiteralPath $p) { Read-Article $p }
    }
    @($list | Sort-Object @{ Expression = 'Date'; Descending = $true }, @{ Expression = 'Slug'; Descending = $false })
}
