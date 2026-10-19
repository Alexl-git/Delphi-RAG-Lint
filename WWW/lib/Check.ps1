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
    }
    $problems.ToArray()
}
