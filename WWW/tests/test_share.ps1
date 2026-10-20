# Share previews (owner 2026-10-20): every page but 404.html has an Open Graph card; an
# article may name its own picture with "image: <file in its folder>", else the default card.
. "$PSScriptRoot\..\lib\Articles.ps1"

# an article's image must be a .png/.jpg file in its own folder
$d = New-TestDir
$art = Join-Path $d '2026-10-20-pic'
[void][IO.Directory]::CreateDirectory($art)
$head = "<!--article`r`ntitle: T`r`ndate: 2026-10-20`r`nslug: pic`r`nsummary: S.`r`nimage: card.png`r`n-->`r`n"
$body = "<p><a href=""https://www.htrmicronite.com"">M</a></p>`r`n"
[IO.File]::WriteAllText("$art\index.html", $head + $body)
Assert-Throws { Read-Article "$art\index.html" } '*image*card.png*'
[IO.File]::WriteAllBytes("$art\card.png", [byte[]](0x89, 0x50, 0x4E, 0x47))
Assert-Equal 'card.png' (Read-Article "$art\index.html").Image 'image read'
[IO.File]::WriteAllText("$art\index.html", $head.Replace('card.png', '../x.png') + $body)
Assert-Throws { Read-Article "$art\index.html" } '*image*'

# the built site: default card shipped, article card copied next to its page, 404 not shared
$out = New-TestDir
$fake = { param($argv) $global:LASTEXITCODE = 0; '{"tagName":"v1.2.3-alpha","publishedAt":"2026-10-19T07:00:00Z"}' }
& "$PSScriptRoot\..\build.ps1" -Out $out -ArticlesRoot "$PSScriptRoot\fixtures\articles" -Gh $fake | Out-Null
Assert-Equal 0 $LASTEXITCODE 'build exit'
Assert-True (Test-Path "$out\assets\share\default.png") 'default card shipped'
Assert-True (Test-Path "$out\articles\a-one\card.png") 'article card copied'
$a1 = [IO.File]::ReadAllText("$out\articles\a-one\index.html")
Assert-True ($a1.Contains('<meta property="og:image" content="https://www.delphi-rag-lint.com/articles/a-one/card.png">')) 'article og:image'
Assert-True ($a1.Contains('<meta property="og:type" content="article">')) 'article og:type'
Assert-True ([IO.File]::ReadAllText("$out\downloads\index.html").Contains('og:image')) 'downloads shared'
Assert-True (-not [IO.File]::ReadAllText("$out\404.html").Contains('og:')) '404 not shared'
