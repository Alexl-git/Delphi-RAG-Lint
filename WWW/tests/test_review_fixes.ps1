# Final-review fixes I1-I4 (feat/www-base): each assertion failed before its fix.
. "$PSScriptRoot\..\lib\Config.ps1"
. "$PSScriptRoot\..\lib\Articles.ps1"
. "$PSScriptRoot\..\lib\Render.ps1"
. "$PSScriptRoot\..\lib\Publish.ps1"

# I3: built pages can never carry a silent '?' for a non-ASCII character
Assert-Equal 'It&#8217;s caf&#233;' (ConvertTo-HtmlText "It$([char]0x2019)s caf$([char]0xE9)") 'HtmlText entity-encodes all non-ASCII'
Assert-Throws { ConvertTo-AsciiBytes "a`nIt$([char]0x2019)s" 'templates\404.html' } '*templates\404.html:2*U+2019*'
Assert-Equal 3 (ConvertTo-AsciiBytes "a`r`n" 'x').Length 'ASCII text passes through'

# I4: an entity in title/summary would be encoded twice -- refused with a clear message
$d = New-TestDir
$art = Join-Path $d '2026-10-20-ent'
[void][IO.Directory]::CreateDirectory($art)
$meta = "<!--article`r`ntitle: Caf&eacute; notes`r`ndate: 2026-10-20`r`nslug: ent`r`nsummary: R&D only.`r`n-->`r`n<p><a href=""https://www.htrmicronite.com"">Micronite</a></p>`r`n"
[IO.File]::WriteAllText("$art\index.html", $meta)
Assert-Throws { Read-Article "$art\index.html" } '*title*plain ASCII*'
[IO.File]::WriteAllText("$art\index.html", $meta.Replace('Caf&eacute;', 'Cafe'))
Assert-Equal 'R&D only.' (Read-Article "$art\index.html").Summary 'a bare & is still fine'

# I1: IIS must serve our index.html, never a leftover Default.htm / index.htm placeholder
[xml]$wc = [IO.File]::ReadAllText("$PSScriptRoot\..\web.config")
$dd = $wc.configuration.'system.webServer'.defaultDocument.files
Assert-True ($null -ne $dd.clear) 'defaultDocument clears the inherited list'
Assert-Equal 'index.html' (@($dd.add | ForEach-Object value) -join ',') 'index.html is the only default document'
$base = 'https://www.delphi-rag-lint.com'
Assert-True (Test-LiveHome ([pscustomobject]@{ Status = 200; Content = "<link rel=""canonical"" href=""$base/"">" }) $base) 'our home page'
Assert-True (-not (Test-LiveHome ([pscustomobject]@{ Status = 200; Content = '<h1>Coming soon - IONOS</h1>' }) $base)) 'placeholder served with 200 is a failure'
Assert-True (-not (Test-LiveHome ([pscustomobject]@{ Status = 500; Content = '' }) $base)) '500'

# I2: the 500 fallback uploads one prepared web.config, no rebuild; NoRewrite only if it worked
$src = [IO.File]::ReadAllText("$PSScriptRoot\..\web.config")
$plain = New-WebConfigText $src $true
Assert-True ($null -eq ([xml]$plain).configuration.'system.webServer'.rewrite) 'no-rewrite text has no <rewrite> element'
Assert-True ($plain.Contains('Strict-Transport-Security')) 'headers kept'
Assert-True ($null -ne ([xml](New-WebConfigText $src $false)).configuration.'system.webServer'.rewrite) 'rewrite kept when asked'

$files = @{ 'index.html' = 'H1'; 'web.config' = 'OLD' }
$script:puts = @()
$put = { param($local, $rel) $script:puts += , @($rel, [IO.File]::ReadAllText($local)) }
$r = Invoke-RewriteFallback $files $plain $put { 200 }
Assert-True $r.NoRewrite 'retry 200 -> NoRewrite saved'
Assert-Equal 1 $script:puts.Count 'one upload'
Assert-Equal 'web.config' $script:puts[0][0] 'uploads web.config'
Assert-Equal $plain $script:puts[0][1] 'uploads the prepared text'
Assert-Equal 'H1' $r.Files['index.html'] 'other manifest entries untouched'
Assert-True ($r.Files['web.config'] -ne 'OLD') 'web.config entry = what is on the server now'
Assert-Equal 'OLD' $files['web.config'] 'input manifest not mutated'

$script:puts = @()
$r = Invoke-RewriteFallback $files $plain $put { 500 }
Assert-True (-not $r.NoRewrite) 'still 500 -> NoRewrite NOT saved'
Assert-Equal 500 $r.Status 'status reported'
