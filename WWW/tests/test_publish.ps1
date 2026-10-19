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

# test_refuses_plain_ftp
$ok = [pscustomobject]@{ Protocol = 'ftps'; Host = 'h'; Port = 21; User = 'u'
    Password = (ConvertTo-SecureString 'p' -AsPlainText -Force); RemoteRoot = '/'; TlsFingerprint = 'aa:bb' }
Assert-True (Test-PublishCredential $ok) 'ftps credentials accepted'
$ftp = $ok.PSObject.Copy(); $ftp.Protocol = 'ftp'
Assert-Throws { Test-PublishCredential $ftp } '*ftp*'
$nofp = $ok.PSObject.Copy(); $nofp.TlsFingerprint = ''
Assert-Throws { Test-PublishCredential $nofp } '*TlsFingerprint*'
