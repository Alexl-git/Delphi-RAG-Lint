# Test: first article is valid and builds
$ErrorActionPreference = 'Stop'

$articlePath = Join-Path $PSScriptRoot '..\articles\2026-10-19-three-ways-to-read-delphi\index.html'

Assert-True (Test-Path $articlePath) "article file exists at $articlePath"

$content = [IO.File]::ReadAllText($articlePath, [Text.Encoding]::ASCII)
. (Join-Path $PSScriptRoot '..\lib\Articles.ps1')
$article = Read-Article $articlePath
Assert-Equal 'Three Ways to Read Delphi' $article.Title "Title mismatch"
Assert-Equal '2026-10-19' $article.Date "Date mismatch"
Assert-Equal 'three-ways-to-read-delphi' $article.Slug "Slug mismatch"

$firstThousand = $content.Substring(0, [Math]::Min(3000, $content.Length))
Assert-True ($firstThousand -match 'https://www\.htrmicronite\.com') "Body must contain htrmicronite.com in first 3000 chars"

Assert-True ($content -notmatch '<title') "Body must have no <title tag"
Assert-True ($content -notmatch '<link\s+rel="stylesheet"\s+href="https://fonts\.googleapis') "Body must have no Google Fonts link"
Assert-True ($content -notmatch '<style') "Body must have no inline <style tag"

$tempDir = New-TestDir
try {
    $config = Get-Content (Join-Path $PSScriptRoot '..\site.json') | ConvertFrom-Json
    & (Join-Path $PSScriptRoot '..\build.ps1') -Out $tempDir -WarnOnly:$false -NoRewrite:$false
    . (Join-Path $PSScriptRoot '..\lib\Check.ps1')
    $problems = @(Test-SiteOutput $tempDir $config)
    Assert-Equal 0 $problems.Count "build check failed: $($problems -join '; ')"
} finally {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
}
