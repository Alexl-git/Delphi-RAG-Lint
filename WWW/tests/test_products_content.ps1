# The real product pages (WWW\products) with the real site.json: approved wording, facts filled, pictures sized.
. (Join-Path $PSScriptRoot '..\lib\Config.ps1')
. (Join-Path $PSScriptRoot '..\lib\Products.ps1')
$cfg = Read-SiteConfig (Join-Path $PSScriptRoot '..\site.json')

$dl = Read-ProductPage (Join-Path $PSScriptRoot '..\products\dl\index.html') $cfg
$b = $dl.Body
foreach ($s in 'Delphi RAG lint knows your code.',
               'Embarcadero RAD Studio 13 Florence, VS Code, plus any editor that speaks LSP or MCP',
               '190 rules', '16 categories',
               # ENGINE fact-check 2026-10-20 (docs\www-dl-page-factcheck-2026-10-20.md):
               # 7 of the 23 fixable rules are fix_opt_in; the VS Code extension is
               # source-only; 37.0 binds the plugin, not the engine; the library
               # index is a snapshot.
               '23 rules can fix the code for you (some only when you opt in)',
               'extension in the repository over the DL language server; build the .vsix from source',
               'RAD Studio 13 Florence (37.0) plugin &middot; the engine indexes older Delphi source too',
               'Built per platform; rebuild it when you install new components.',
               'href="https://www.htrmicronite.com',
               'It also tells you that there <i>is</i> a needle in there',
               'Free and open source &middot; written in Delphi') {
    Assert-True ($b.Contains($s)) "DL page contains '$s'"
}
foreach ($h in [regex]::Matches($b, '(?s)<h2[^>]*>(.*?)</h2>')) {
    Assert-True (-not ($h.Groups[1].Value -match '\b(eight|nine|ten|\d+) things\b')) "no counted heading: $($h.Groups[1].Value)"
}
foreach ($img in [regex]::Matches($b, '<img\b[^>]*>')) {
    foreach ($a in 'alt=', 'width=', 'height=') { Assert-True ($img.Value.Contains($a)) "$($img.Value) has $a" }
}

# YADF: its own facts (1.0.20.0), nothing YADF told us never to claim
$yadf = Read-ProductPage (Join-Path $PSScriptRoot '..\products\yadf\index.html') $cfg
$y = $yadf.Body
foreach ($s in 'Smart column alignment', 'Set F / Set R', 'Ctrl+Shift+Alt+R', 'In YADFSetup or on the IDE settings page',
               'href="https://www.htrmicronite.com',
               # yadf-6c read-back 2026-10-20 (.dpk: owner 2026-10-20)
               'reformats .pas, .dpr, .dpk and .inc source',
               'Free and open source &middot; written in Delphi',
               'Help &gt; Tools &gt; YADFOT: Format Current Buffer',
               'so code from 11-13 can build on 10.2.3. Best effort: ambiguous cases are left marked for you to finish.') {
    Assert-True ($y.Contains($s)) "YADF page contains '$s'"
}
foreach ($bad in '13\.2', 'Castalia', 'GExperts', 'pasfmt', 'faster', '\bLF\b', 'MIT') {
    Assert-True (-not ($y -match $bad)) "YADF page must not match '$bad'"
}
$notYet = [regex]::Match($y, '<div><b>Not yet</b>.*?</div>')
Assert-True ($notYet.Success -and $notYet.Value.Contains('VS Code')) 'VS Code named under Not yet'
Assert-True (-not $y.Replace($notYet.Value, '').Contains('VS Code')) 'VS Code only under Not yet'

# the two Micronite paragraphs are written separately, not pasted
function Get-MicroniteSentences([string]$Body) {
    $p = [regex]::Match($Body, '(?s)<p>(?:(?!</p>).)*htrmicronite(?:(?!</p>).)*</p>').Value
    Assert-True ($p.Length -gt 0) 'Micronite paragraph found'
    ($p -replace '<[^>]+>', '') -split '\. ' | ForEach-Object { $_.Trim().TrimEnd('.') } | Where-Object { $_ }
}
$shared = @(Get-MicroniteSentences $b | Where-Object { $_ -in @(Get-MicroniteSentences $y) })
Assert-Equal 0 $shared.Count "DL and YADF Micronite paragraphs share: $($shared -join ' | ')"
