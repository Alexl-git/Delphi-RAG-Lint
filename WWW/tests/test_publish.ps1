. "$PSScriptRoot\..\lib\Publish.ps1"

# test_publish_plan_first
$p = Get-PublishPlan @() @{ 'a.html' = '1'; 'b.css' = '2' }
Assert-Equal 'a.html,b.css' ((@($p.Upload) | Sort-Object) -join ',') 'first: upload all'
Assert-Equal 0 @($p.Delete).Count 'first: delete none'

# test_publish_plan_changed_and_removed (old manifest with hashes, as saved by publish)
$p = Get-PublishPlan @{ 'a.html' = '1'; 'old.html' = '9' } @{ 'a.html' = 'changed' }
Assert-Equal 'a.html' (@($p.Upload) -join ',') 'changed: upload a.html'
Assert-Equal 'old.html' (@($p.Delete) -join ',') 'removed: delete old.html'

# an unchanged file is not uploaded again
$p = Get-PublishPlan @{ 'a.html' = '1'; 'b.css' = '2' } @{ 'a.html' = '1'; 'b.css' = '3' }
Assert-Equal 'b.css' (@($p.Upload) -join ',') 'unchanged a.html skipped'

# a path-only manifest (string[]) has no hashes: every surviving path is re-uploaded
$p = Get-PublishPlan @('a.html', 'old.html') @{ 'a.html' = 'changed' }
Assert-Equal 'a.html' (@($p.Upload) -join ',') 'path-only: upload a.html'
Assert-Equal 'old.html' (@($p.Delete) -join ',') 'path-only: delete old.html'

# test_publish_plan_never_deletes_unknown
$old = @{ 'a.html' = '1'; 'x/y.css' = '2'; 'gone.txt' = '3' }
foreach ($new in @{}, @{ 'a.html' = '1' }, @{ 'z.html' = '5'; 'x/y.css' = '2' }) {
    $p = Get-PublishPlan $old $new
    foreach ($d in @($p.Delete)) { Assert-True $old.ContainsKey($d) "deleted '$d' is not in the old manifest" }
    foreach ($d in @($p.Delete)) { Assert-True (-not $new.ContainsKey($d)) "deleted '$d' is still in the new set" }
}

# test_first_publish_guard
Assert-True (Test-FirstPublishTarget @('index.html')) 'index.html placeholder'
Assert-True (Test-FirstPublishTarget @('Default.htm')) 'Default.htm placeholder'
Assert-True (-not (Test-FirstPublishTarget @('index.html', 'cgi-bin'))) 'cgi-bin is real content'
Assert-True (Test-FirstPublishTarget @()) 'empty root'
# what publish.ps1 really passes for an empty folder: a function returning @() yields $null
$emptyDir = [pscustomobject]@{} | Add-Member -PassThru ScriptMethod ListDirectory { param($p) [pscustomobject]@{ Files = @() } }
$names = Get-RemoteNames $emptyDir '/x'
Assert-True (Test-FirstPublishTarget $names) 'empty root as returned by Get-RemoteNames'
Assert-True (Test-FirstPublishTarget $null) 'empty root passed as $null'

# test_refuses_plain_ftp
$ok = [pscustomobject]@{ Protocol = 'ftps'; Host = 'h'; Port = 21; User = 'u'
    Password = (ConvertTo-SecureString 'p' -AsPlainText -Force); RemoteRoot = '/'; TlsFingerprint = 'aa:bb' }
Assert-True (Test-PublishCredential $ok) 'ftps credentials accepted'
$ftp = $ok.PSObject.Copy(); $ftp.Protocol = 'ftp'
Assert-Throws { Test-PublishCredential $ftp } '*ftp*'
$nofp = $ok.PSObject.Copy(); $nofp.TlsFingerprint = ''
Assert-Throws { Test-PublishCredential $nofp } '*TlsFingerprint*'

# test_live_redirect: IONOS's .htaccess add-on only answers 302 (owner 2026-10-20: accept it)
$b = 'https://www.delphi-rag-lint.com'
Assert-True (Test-LiveRedirect ([pscustomobject]@{ Status = 301; Location = "$b/" }) $b) '301 to base'
Assert-True (Test-LiveRedirect ([pscustomobject]@{ Status = 302; Location = "$b/" }) $b) '302 to base accepted'
Assert-True (-not (Test-LiveRedirect ([pscustomobject]@{ Status = 302; Location = 'https://evil.example/' }) $b)) '302 elsewhere refused'
Assert-True (-not (Test-LiveRedirect ([pscustomobject]@{ Status = 302; Location = "$b.evil.example/" }) $b)) 'look-alike host refused'
Assert-True (-not (Test-LiveRedirect ([pscustomobject]@{ Status = 200; Location = '' }) $b)) 'no redirect refused'

# test_http_status_sees_redirect: pwsh 7.6 Invoke-WebRequest -MaximumRedirection 0 THROWS on a 302,
# which made the live redirect check read 0 although the redirect worked (2026-10-20)
$port = Get-Random -Minimum 20000 -Maximum 40000
$l = [Net.HttpListener]::new(); $l.Prefixes.Add("http://localhost:$port/"); $l.Start()
$job = Start-ThreadJob { param($l)
    $c = $l.GetContext(); $c.Response.StatusCode = 302; $c.Response.RedirectLocation = 'https://www.example.com/x'; $c.Response.Close()
    $c = $l.GetContext(); $b = [Text.Encoding]::ASCII.GetBytes('<p>hi</p>'); $c.Response.OutputStream.Write($b, 0, $b.Length); $c.Response.Close()
} -ArgumentList $l
try {
    $r = Get-HttpStatus "http://localhost:$port/"
    Assert-Equal 302 $r.Status 'redirect status, not followed'
    Assert-Equal 'https://www.example.com/x' $r.Location 'redirect location'
    $r = Get-HttpStatus "http://localhost:$port/"
    Assert-Equal 200 $r.Status 'plain 200'
    Assert-Equal '<p>hi</p>' $r.Content '200 body'
} finally { $job | Wait-Job -Timeout 5 | Out-Null; $l.Close(); $job | Wait-Job -Timeout 5 | Out-Null; $job | Remove-Job -Force }
