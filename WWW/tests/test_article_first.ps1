# Test: the first article is valid, styled by the site CSS, and the real site builds clean
$ErrorActionPreference = 'Stop'

$articlePath = Join-Path $PSScriptRoot '..\articles\2026-10-19-three-ways-to-read-delphi\index.html'
Assert-True (Test-Path $articlePath) "article file exists at $articlePath"

. (Join-Path $PSScriptRoot '..\lib\Articles.ps1')
$article = Read-Article $articlePath
Assert-Equal 'Three Ways to Read Delphi' $article.Title 'title'
Assert-Equal '2026-10-19' $article.Date 'date'
Assert-Equal 'three-ways-to-read-delphi' $article.Slug 'slug'
Assert-Equal 'A raw lexer, DelphiAST, and tree-sitter-delphi13 are not three grades of the same tool.' $article.Summary 'summary = the standfirst''s first sentence'

$body = $article.Body
Assert-True ($body.Substring(0, [Math]::Min(3000, $body.Length)).Contains('https://www.htrmicronite.com')) 'Micronite link within the first 3000 chars'
foreach ($bad in '<title', '<link', '<style', 'fonts.googleapis') {
    Assert-True (-not $body.Contains($bad)) "body contains $bad"
}

# every class the article uses must be defined in the site stylesheet
$css = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\assets\style.css'))
$classes = [regex]::Matches($body, 'class="([^"]+)"') | ForEach-Object { $_.Groups[1].Value -split '\s+' } | Sort-Object -Unique
foreach ($c in $classes) {
    Assert-True ($css -match "\.$([regex]::Escape($c))(?![\w-])") "class '$c' is not defined in style.css"
}

$out = New-TestDir
& (Join-Path $PSScriptRoot '..\build.ps1') -Out $out -ProductsRoot "$PSScriptRoot\fixtures\products" | Out-Null
Assert-Equal 0 $LASTEXITCODE 'build.ps1 exit code'
. (Join-Path $PSScriptRoot '..\lib\Config.ps1')
. (Join-Path $PSScriptRoot '..\lib\Check.ps1')
$problems = @(Test-SiteOutput $out (Read-SiteConfig "$PSScriptRoot\..\site.json"))
Assert-Equal 0 $problems.Count "site check: $($problems -join '; ')"
