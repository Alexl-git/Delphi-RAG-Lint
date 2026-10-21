# Small Markdown -> HTML converter for the help trees (help\<product>\*.md).
# Subset: headings, paragraphs, fenced and indented code, tables, nested lists, block quotes,
# rules, code spans, bold, italic, links, images. Raw HTML in the source is shown as text.
# Context hashtable: ResolveHref = scriptblock (href, ctx -> final href); used for links and images.

function Get-MdSlug([string]$Text) {
    $s = ($Text.ToLowerInvariant() -replace '[^a-z0-9 _-]', '') -replace ' ', '-'
    $s
}

# Splits "---\nkey: value\n---\nbody" into @{ Meta = ordered hashtable; Body = string }.
function Split-FrontMatter([string]$Text) {
    $meta = [ordered]@{}
    $t = $Text -replace "\r\n?", "`n"
    $m = [regex]::Match($t, '\A---\n(.*?)\n---[ \t]*(?:\n|\z)', 'Singleline')
    if (-not $m.Success) { return @{ Meta = $meta; Body = $t } }
    foreach ($line in $m.Groups[1].Value.Split("`n")) {
        $kv = [regex]::Match($line, '^([A-Za-z][\w-]*):[ \t]*(.*?)[ \t]*$')
        if (-not $kv.Success) { continue }
        $v = $kv.Groups[2].Value
        if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $meta[$kv.Groups[1].Value] = $v
    }
    @{ Meta = $meta; Body = $t.Substring($m.Length) }
}

function Convert-MdInline([string]$Text, [hashtable]$Ctx) {
    if ($Text -notmatch '[`\\\[\]*_<>&]') { return ConvertTo-HtmlText $Text }
    $stash = [Collections.Generic.List[string]]::new()
    $mark = { param([string]$Html) $stash.Add($Html); "$([char]1)$($stash.Count - 1)$([char]1)" }
    # code spans first: their content is literal
    $t = [regex]::Replace($Text, '(`+)(.+?)(?<!`)\1(?!`)', { param($m) & $mark ("<code>" + (ConvertTo-HtmlText $m.Groups[2].Value.Trim()) + "</code>") })
    # backslash escapes
    $t = [regex]::Replace($t, '\\([\\`*_\[\]{}()#+.!|<>~-])', { param($m) & $mark (ConvertTo-HtmlText $m.Groups[1].Value) })
    $t = ConvertTo-HtmlText $t
    $res = $Ctx.ResolveHref
    $t = [regex]::Replace($t, '!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^)]*?&quot;)?\)', {
        param($m) & $mark ("<img src=""" + (& $res ([Net.WebUtility]::HtmlDecode($m.Groups[2].Value)) $Ctx) + """ alt=""" + $m.Groups[1].Value + """>") })
    $t = [regex]::Replace($t, '\[([^\]]+)\]\(([^)\s]+)(?:\s+&quot;[^)]*?&quot;)?\)', {
        param($m) "<a href=""" + (& $res ([Net.WebUtility]::HtmlDecode($m.Groups[2].Value)) $Ctx) + """>" + $m.Groups[1].Value + "</a>" })
    $t = [regex]::Replace($t, '&lt;(https?://[^\s&]+)&gt;', '<a href="$1">$1</a>')
    $t = [regex]::Replace($t, '\*\*(?=\S)(.+?)(?<=\S)\*\*', '<strong>$1</strong>')
    $t = [regex]::Replace($t, '(?<![\w])__(?=\S)(.+?)(?<=\S)__(?![\w])', '<strong>$1</strong>')
    $t = [regex]::Replace($t, '(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])', '<em>$1</em>')
    $t = [regex]::Replace($t, '(?<![\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w])', '<em>$1</em>')
    [regex]::Replace($t, "$([char]1)(\d+)$([char]1)", { param($m) $stash[[int]$m.Groups[1].Value] })
}

function Split-MdRow([string]$Line) {
    $s = $Line.Trim()
    if ($s.StartsWith('|')) { $s = $s.Substring(1) }
    if ($s.EndsWith('|') -and -not $s.EndsWith('\|')) { $s = $s.Substring(0, $s.Length - 1) }
    # split at '|' outside code spans; '\|' is a literal pipe
    $cells = [Collections.Generic.List[string]]::new()
    $cur = [Text.StringBuilder]::new(); $inCode = $false
    for ($k = 0; $k -lt $s.Length; $k++) {
        $ch = $s[$k]
        if ($ch -eq '\' -and ($k + 1) -lt $s.Length -and $s[$k + 1] -eq '|') { [void]$cur.Append('|'); $k++; continue }
        if ($ch -eq '`') { $inCode = -not $inCode }
        if ($ch -eq '|' -and -not $inCode) { $cells.Add($cur.ToString().Trim()); [void]$cur.Clear(); continue }
        [void]$cur.Append($ch)
    }
    $cells.Add($cur.ToString().Trim())
    $cells.ToArray()
}

function Test-MdBlockStart([string]$Line) {
    $Line -match '^\s{0,3}(#{1,6}\s|```|~~~|>|(-{3,}|\*{3,}|_{3,})\s*$|[-*+]\s+\S|\d{1,9}[.)]\s+\S)'
}

function Convert-MdBlocks([string[]]$Lines, [hashtable]$Ctx) {
    $out = [Text.StringBuilder]::new()
    $i = 0; $n = $Lines.Count
    while ($i -lt $n) {
        $ln = $Lines[$i]
        if ($ln -match '^\s*$') { $i++; continue }
        # fenced code
        $f = [regex]::Match($ln, '^(\s*)(```+|~~~+)\s*([\w+-]*)')
        if ($f.Success) {
            $ind = $f.Groups[1].Length; $fence = $f.Groups[2].Value; $i++
            $code = [Collections.Generic.List[string]]::new()
            while ($i -lt $n -and -not ($Lines[$i].TrimStart().StartsWith($fence))) {
                $c = $Lines[$i]; $lead = [regex]::Match($c, '^\s*').Length
                $code.Add($c.Substring([Math]::Min($ind, $lead)))
                $i++
            }
            $i++
            [void]$out.Append("<pre><code>" + (ConvertTo-HtmlText ($code -join "`n")) + "</code></pre>`n")
            continue
        }
        # heading
        $h = [regex]::Match($ln, '^\s{0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$')
        if ($h.Success) {
            $lvl = $h.Groups[1].Length
            $slug = Get-MdSlug $h.Groups[2].Value
            [void]$out.Append("<h$lvl id=""$slug"">" + (Convert-MdInline $h.Groups[2].Value $Ctx) + "</h$lvl>`n")
            $i++; continue
        }
        if ($ln -match '^\s{0,3}(-{3,}|\*{3,}|_{3,})\s*$') { [void]$out.Append("<hr>`n"); $i++; continue }
        # table
        if ($ln.TrimStart().StartsWith('|') -and ($i + 1) -lt $n -and $Lines[$i + 1] -match '^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$') {
            $head = Split-MdRow $ln
            $i += 2
            $sb = [Text.StringBuilder]::new()
            [void]$sb.Append('<div class="tablewrap"><table><thead><tr>')
            foreach ($c in $head) { [void]$sb.Append("<th>" + (Convert-MdInline $c $Ctx) + "</th>") }
            [void]$sb.Append('</tr></thead><tbody>')
            while ($i -lt $n -and $Lines[$i].TrimStart().StartsWith('|')) {
                [void]$sb.Append('<tr>')
                $cells = @(Split-MdRow $Lines[$i])
                for ($k = 0; $k -lt $head.Count; $k++) {
                    $cell = if ($k -lt $cells.Count) { $cells[$k] } else { '' }
                    [void]$sb.Append("<td>" + (Convert-MdInline $cell $Ctx) + "</td>")
                }
                [void]$sb.Append('</tr>'); $i++
            }
            [void]$sb.Append('</tbody></table></div>')
            [void]$out.Append($sb.ToString() + "`n")
            continue
        }
        # block quote
        if ($ln -match '^\s{0,3}>') {
            $q = [Collections.Generic.List[string]]::new()
            while ($i -lt $n -and $Lines[$i] -match '^\s{0,3}>') { $q.Add(($Lines[$i] -replace '^\s{0,3}>\s?', '')); $i++ }
            [void]$out.Append("<blockquote>" + (Convert-MdBlocks $q.ToArray() $Ctx) + "</blockquote>`n")
            continue
        }
        # list
        $lm = [regex]::Match($ln, '^(\s{0,3})([-*+]|\d{1,9}[.)])\s+')
        if ($lm.Success) {
            $ordered = $lm.Groups[2].Value -match '^\d'
            $start = if ($ordered) { [int]($lm.Groups[2].Value -replace '\D', '') } else { 1 }
            $baseInd = $lm.Groups[1].Length
            $items = [Collections.Generic.List[object]]::new()
            $loose = $false
            while ($i -lt $n) {
                $im = [regex]::Match($Lines[$i], '^(\s*)([-*+]|\d{1,9}[.)])(\s+)')
                if (-not $im.Success -or $im.Groups[1].Length -ne $baseInd -or (($im.Groups[2].Value -match '^\d') -ne $ordered)) { break }
                $w = $im.Length
                $body = [Collections.Generic.List[string]]::new()
                $body.Add($Lines[$i].Substring($w)); $i++
                while ($i -lt $n) {
                    $c = $Lines[$i]
                    if ($c -match '^\s*$') {
                        $j = $i; while ($j -lt $n -and $Lines[$j] -match '^\s*$') { $j++ }
                        if ($j -ge $n) { $i = $j; break }
                        $nl = [regex]::Match($Lines[$j], '^\s*').Length
                        $isSib = $Lines[$j] -match '^(\s*)([-*+]|\d{1,9}[.)])\s+' -and $Matches[1].Length -eq $baseInd
                        if ($nl -ge $w) { for ($k = $i; $k -lt $j; $k++) { $body.Add('') }; $i = $j; continue }
                        if ($isSib) { $loose = $true }
                        $i = $j; break
                    }
                    $lead = [regex]::Match($c, '^\s*').Length
                    if ($lead -ge $w) { $body.Add($c.Substring($w)); $i++; continue }
                    # lazy continuation of a paragraph line only
                    if ($c -match '^(\s*)([-*+]|\d{1,9}[.)])\s+' -or (Test-MdBlockStart $c)) { break }
                    $body.Add($c.TrimStart()); $i++
                }
                $items.Add($body.ToArray())
            }
            $tag = if ($ordered) { 'ol' } else { 'ul' }
            $open = if ($ordered -and $start -ne 1) { "<ol start=""$start"">" } else { "<$tag>" }
            [void]$out.Append($open + "`n")
            foreach ($it in $items) {
                $html = Convert-MdBlocks $it $Ctx
                if (-not $loose) { $html = [regex]::Replace($html, '^<p>(.*?)</p>\n?', '$1', 'Singleline') }
                [void]$out.Append("<li>" + $html.TrimEnd() + "</li>`n")
            }
            [void]$out.Append("</$tag>`n")
            continue
        }
        # indented code
        if ($ln -match '^( {4}|\t)') {
            $code = [Collections.Generic.List[string]]::new()
            while ($i -lt $n -and ($Lines[$i] -match '^( {4}|\t)' -or $Lines[$i] -match '^\s*$')) {
                $code.Add(($Lines[$i] -replace '^( {4}|\t)', '')); $i++
            }
            while ($code.Count -and $code[$code.Count - 1] -eq '') { $code.RemoveAt($code.Count - 1) }
            [void]$out.Append("<pre><code>" + (ConvertTo-HtmlText ($code -join "`n")) + "</code></pre>`n")
            continue
        }
        # paragraph
        $p = [Collections.Generic.List[string]]::new()
        while ($i -lt $n -and $Lines[$i] -notmatch '^\s*$' -and ($p.Count -eq 0 -or -not (Test-MdBlockStart $Lines[$i])) -and
               -not ($p.Count -gt 0 -and $Lines[$i].TrimStart().StartsWith('|') -and ($i + 1) -lt $n -and $Lines[$i + 1] -match '^\s*\|?\s*:?-{1,}:?\s*\|')) {
            $p.Add($Lines[$i].Trim()); $i++
        }
        [void]$out.Append("<p>" + (Convert-MdInline ($p -join "`n") $Ctx) + "</p>`n")
    }
    $out.ToString()
}

function ConvertFrom-SiteMarkdown([string]$Markdown, [hashtable]$Ctx) {
    Convert-MdBlocks ($Markdown -replace "\r\n?", "`n").Split("`n") $Ctx
}
