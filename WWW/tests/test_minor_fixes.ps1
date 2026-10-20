# Final-review minors M1, M2, M5, M6, M7, M9 (feat/www-base): each assertion failed before its fix.
. "$PSScriptRoot\..\lib\Config.ps1"
. "$PSScriptRoot\..\lib\Articles.ps1"
. "$PSScriptRoot\..\lib\Render.ps1"
. "$PSScriptRoot\..\lib\Check.ps1"
. "$PSScriptRoot\..\lib\Publish.ps1"
$cfg = Read-SiteConfig "$PSScriptRoot\..\site.json"

# M1: the manifest is saved after every put and delete, so a partial publish is still recorded
$plan = [pscustomobject]@{ Upload = @('a.html', 'b.html'); Delete = @('old.html') }
$script:saved = $null
$save = { param($f) $script:saved = $f.Clone() }
$put = { param($rel) if ($rel -eq 'b.html') { throw 'link dropped' } }
Assert-Throws { Invoke-PublishPlan $plan @{ 'old.html' = 'O' } @{ 'a.html' = 'A'; 'b.html' = 'B' } $put { param($rel) } $save } '*link dropped*'
Assert-Equal 'A' $script:saved['a.html'] 'a.html recorded after its put'
Assert-True (-not $script:saved.ContainsKey('b.html')) 'b.html not recorded'
Assert-Equal 'O' $script:saved['old.html'] 'old.html still recorded (not deleted yet)'
$final = Invoke-PublishPlan $plan @{ 'old.html' = 'O' } @{ 'a.html' = 'A'; 'b.html' = 'B' } { param($rel) } { param($rel) } $save
Assert-Equal 'a.html,b.html' ((@($final.Keys) | Sort-Object) -join ',') 'full run: manifest = new set'
Assert-Equal 'a.html,b.html' ((@($script:saved.Keys) | Sort-Object) -join ',') 'last save = new set'

# M2: a network failure in a live check is a status, not an abort
$r = Get-HttpStatus 'https://no-such-host.invalid/'
Assert-Equal 0 $r.Status 'DNS failure -> Status 0'

# M5: folders emptied by the deletes, deepest first, never one that still holds a file
Assert-Equal 'a/b' ((Get-EmptiedRemoteDirs @('a/b/c.html', 'a/x.html') @('a/y.html')) -join ',') 'a still holds y.html'
Assert-Equal 'old/p,old' ((Get-EmptiedRemoteDirs @('old/p/q.html') @('index.html')) -join ',') 'deepest first'
Assert-Equal '' ((Get-EmptiedRemoteDirs @('top.html') @()) -join ',') 'root is never removed'

# M6: the Server header is removed, and the 500 fallback drops that optional section too
[xml]$wc = [IO.File]::ReadAllText("$PSScriptRoot\..\web.config")
Assert-Equal 'true' $wc.configuration.'system.webServer'.security.requestFiltering.removeServerHeader 'removeServerHeader'
[xml]$plain = New-WebConfigText ([IO.File]::ReadAllText("$PSScriptRoot\..\web.config")) $true
Assert-True ($null -eq $plain.configuration.'system.webServer'.security) 'fallback drops <security>'

# M7: every article mentions Micronite near the top, enforced by the build
$d = New-TestDir
$art = Join-Path $d '2026-10-20-nomic'
[void][IO.Directory]::CreateDirectory($art)
[IO.File]::WriteAllText("$art\index.html", "<!--article`r`ntitle: T`r`ndate: 2026-10-20`r`nslug: nomic`r`nsummary: S.`r`n-->`r`n<p>x</p>`r`n")
Assert-Throws { Read-Article "$art\index.html" } '*Micronite*'

# M9: relative links are resolved against their page
$site = New-TestDir
$page = "<link rel=""canonical"" href=""https://www.delphi-rag-lint.com/a/""><a href=""$($cfg.micronite.url)"">m</a><img src=""img/x.png""><a href=""../b/"">b</a><a href=""#top"">t</a><a href=""mailto:x@y.z"">m</a>"
[void][IO.Directory]::CreateDirectory("$site\a")
[IO.File]::WriteAllText("$site\a\index.html", $page)
$p = @(Test-SiteOutput $site $cfg)
Assert-True (@($p | Where-Object { $_ -like '*dangling link img/x.png*' }).Count -eq 1) "relative img flagged: $($p -join '; ')"
Assert-True (@($p | Where-Object { $_ -like '*dangling link ../b/*' }).Count -eq 1) 'relative dir flagged'
Assert-True (@($p | Where-Object { $_ -like '*#top*' -or $_ -like '*mailto*' }).Count -eq 0) 'anchors and mailto ignored'
[void][IO.Directory]::CreateDirectory("$site\a\img"); [IO.File]::WriteAllText("$site\a\img\x.png", 'x')
[void][IO.Directory]::CreateDirectory("$site\b"); [IO.File]::WriteAllText("$site\b\index.html", $page.Replace('/a/', '/b/').Replace(' src="img/x.png"', ''))
Assert-Equal 0 @(Test-SiteOutput $site $cfg | Where-Object { $_ -like '*dangling*' }).Count 'resolved once the files exist'
