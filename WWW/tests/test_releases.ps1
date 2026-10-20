. "$PSScriptRoot\..\lib\Config.ps1"
. "$PSScriptRoot\..\lib\Releases.ps1"

$c = Read-SiteConfig "$PSScriptRoot\..\site.json"
$dl = $c.products[0]

$ok = { param($argv) $global:LASTEXITCODE = 0; '{"tagName":"v1.31.5-alpha","publishedAt":"2026-10-19T07:22:12Z"}' }
$r = Get-ReleaseInfo $dl $ok
Assert-Equal 'v1.31.5-alpha' $r.Tag 'tag'
Assert-Equal '2026-10-19' $r.Date 'date'
Assert-Equal 'https://github.com/Alexl-git/Delphi-RAG-Lint/releases/latest' $r.Url 'url'
Assert-Equal $dl.changelog $r.Changelog 'changelog'

$fail = { param($argv) $global:LASTEXITCODE = 1; '' }
Assert-Throws { Get-ReleaseInfo $dl $fail } '*release lookup failed for DL (drag-lint)*'

$partial = { param($argv) $global:LASTEXITCODE = 0; '{"tagName":"x"}' }
Assert-Throws { Get-ReleaseInfo $dl $partial } '*publishedAt*'

# the real gh call asks for exactly this repo and these fields
$script:seen = $null
$spy = { param($argv) $script:seen = $argv -join ' '; $global:LASTEXITCODE = 0; '{"tagName":"t","publishedAt":"2026-01-02T00:00:00Z"}' }
[void](Get-ReleaseInfo $dl $spy)
Assert-Equal 'release view --repo Alexl-git/Delphi-RAG-Lint --json tagName,publishedAt' $script:seen 'gh argv'
