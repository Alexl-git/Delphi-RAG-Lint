# Output checker: the build refuses to publish a site that breaks a site rule.
# Returns "<relative file>: <problem>" strings; empty means clean.

function Test-SiteOutput([string]$Dir, $Config) {
    $root = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\')
    $problems = [Collections.Generic.List[string]]::new()
    $text = Get-ChildItem -LiteralPath $root -Recurse -File |
        Where-Object { $_.Extension -in '.html', '.css', '.js', '.xml', '.txt', '.config' }
    foreach ($f in $text) {
        $rel = $f.FullName.Substring($root.Length + 1)
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        if (@($bytes | Where-Object { $_ -gt 0x7F } | Select-Object -First 1).Count) {
            $problems.Add("${rel}: non-ASCII byte"); continue
        }
        if ($f.Extension -ne '.html') { continue }
        $h = [Text.Encoding]::ASCII.GetString($bytes)
        if (-not $h.Contains($Config.micronite.url)) { $problems.Add("${rel}: no micronite link") }
        if ($h -notmatch '<link rel="canonical" href="https://www\.delphi-rag-lint\.com/') { $problems.Add("${rel}: no canonical link") }
        if ($h.Contains('{{')) { $problems.Add("${rel}: placeholder left") }
        # share-preview rule (owner 2026-10-20): every page but the 404 has a complete card
        if ($rel -ne '404.html') {
            $og = @{}
            foreach ($m in [regex]::Matches($h, '<meta property="og:(\w+)" content="([^"]*)">')) { $og[$m.Groups[1].Value] = $m.Groups[2].Value }
            $missing = @('title', 'description', 'url', 'image' | Where-Object { -not $og[$_] })
            $canon = [regex]::Match($h, '<link rel="canonical" href="([^"]*)">').Groups[1].Value
            if ($missing.Count) { $problems.Add("${rel}: no share preview (og:$($missing -join ', og:'))") }
            elseif ($canon -and $og.url -ne $canon) { $problems.Add("${rel}: share url $($og.url) is not the canonical $canon") }
            elseif (-not $og.image.StartsWith("$($Config.baseUrl)/") -or
                    -not (Test-Path -LiteralPath (Join-Path $root $og.image.Substring($Config.baseUrl.Length + 1).Replace('/', '\')))) {
                $problems.Add("${rel}: share image not found: $($og.image)")
            }
        }
        if ($h -match '<style|\sstyle\s*=|<script(?![^>]*\ssrc=)[^>]*>') { $problems.Add("${rel}: inline style or script") }
        foreach ($m in [regex]::Matches($h, '<link\b[^>]*>|\ssrc="[^"]*"')) {
            $tag = $m.Value
            if ($tag -match 'rel="canonical"') { continue }
            if ($tag -match '(href|src)="(https?:)?//') { $problems.Add("${rel}: off-site resource $tag") }
        }
        foreach ($m in [regex]::Matches($h, '\s(?:href|src)="(/[^/"][^"]*|/)"')) {
            $path = ($m.Groups[1].Value -split '[?#]')[0]
            $local = Join-Path $root ($path.TrimStart('/').Replace('/', '\'))
            $target = if ($path.EndsWith('/')) { Join-Path $local 'index.html' } else { $local }
            if (-not (Test-Path -LiteralPath $target)) { $problems.Add("${rel}: dangling link $path") }
        }
        # relative links resolve against the page's own folder (anchors, schemes, // skipped)
        foreach ($m in [regex]::Matches($h, '\s(?:href|src)="(?![a-zA-Z][\w+.-]*:|/|#)([^"]+)"')) {
            $path = ($m.Groups[1].Value -split '[?#]')[0]
            if (-not $path) { continue }
            $local = [IO.Path]::GetFullPath((Join-Path (Split-Path $f.FullName -Parent) $path.Replace('/', '\')))
            $target = if ($path.EndsWith('/')) { Join-Path $local 'index.html' } else { $local }
            if (-not $local.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $target)) {
                $problems.Add("${rel}: dangling link $path")
            }
        }
    }
    $problems.ToArray()
}
