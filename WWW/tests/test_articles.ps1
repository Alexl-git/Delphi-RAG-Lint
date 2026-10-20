. "$PSScriptRoot\..\lib\Articles.ps1"

$fx = "$PSScriptRoot\fixtures\articles"

# test_article_reads_metadata
$a = Read-Article "$fx\2026-10-05-newest\index.html"
Assert-Equal 'Newest fixture & friends' $a.Title 'title is raw text'
Assert-Equal '2026-10-05' $a.Date 'date'
Assert-Equal 'newest' $a.Slug 'slug'
Assert-Equal 'The newest fixture article.' $a.Summary 'summary'
Assert-True ($a.Body.TrimStart().StartsWith('<header class="masthead">')) 'body starts after the block'
Assert-True (-not $a.Body.Contains('<!--article')) 'block not in body'

# test_articles_sorted_stably
$all = Get-Articles $fx
Assert-Equal 'newest,a-one,b-two' (($all | ForEach-Object Slug) -join ',') 'date desc, slug asc'

function New-BadArticle([string]$Folder, [string]$Text, [byte[]]$Bytes) {
    $root = New-TestDir
    $dir = Join-Path $root $Folder
    [void][IO.Directory]::CreateDirectory($dir)
    $p = Join-Path $dir 'index.html'
    if ($Bytes) { [IO.File]::WriteAllBytes($p, $Bytes) }
    else { [IO.File]::WriteAllText($p, $Text, [Text.ASCIIEncoding]::new()) }
    $p
}
$head = "<!--article`r`ntitle: T`r`ndate: 2026-10-07`r`nslug: ok-slug`r`nsummary: S`r`n-->`r`n"

# test_article_rejects_non_ascii (U+2019 on line 9)
$txt = $head + "<p>one</p>`r`n<p>two</p>`r`n<p>don"
$bytes = [Text.Encoding]::ASCII.GetBytes($txt) + [byte[]](0xE2, 0x80, 0x99) + [Text.Encoding]::ASCII.GetBytes("t</p>`r`n")
$p = New-BadArticle '2026-10-07-ok-slug' $null $bytes
Assert-Throws { Read-Article $p } '*:9:*non-ASCII*'

# test_article_rejects_bad_slug
$p = New-BadArticle '2026-10-07-Bad_Slug' ($head -replace 'ok-slug', 'Bad_Slug')
Assert-Throws { Read-Article $p } '*slug*'

# folder must be <date>-<slug>
$p = New-BadArticle '2026-10-08-ok-slug' $head
Assert-Throws { Read-Article $p } '*folder*'

# missing key
$p = New-BadArticle '2026-10-07-ok-slug' ($head -replace "summary: S`r`n", '')
Assert-Throws { Read-Article $p } '*summary*missing*'

# bad date
$p = New-BadArticle '2026-10-7-ok-slug' ($head -replace '2026-10-07', '2026-10-7')
Assert-Throws { Read-Article $p } '*date*'

# test_article_rejects_inline_style / script / style element
foreach ($bad in '<p style="color:red">x</p>', '<script>alert(1)</script>', '<style>p{}</style>') {
    $p = New-BadArticle '2026-10-07-ok-slug' ($head + $bad + "`r`n")
    Assert-Throws { Read-Article $p } '*forbidden*'
}
