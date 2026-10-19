# Builds the site and uploads it to the IONOS webspace over FTPS/SFTP (WinSCP .NET).
#   pwsh -File WWW\publish.ps1 [-DryRun] [-SetCredentials] [-AcceptExistingRemote]
# Deletes only files the last publish uploaded (manifest); the first publish refuses a
# remote root that holds anything but the IONOS placeholder, unless -AcceptExistingRemote.
param(
    [switch]$DryRun,
    [switch]$SetCredentials,
    [switch]$AcceptExistingRemote
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Config.ps1')
. (Join-Path $PSScriptRoot 'lib\Render.ps1')
. (Join-Path $PSScriptRoot 'lib\Publish.ps1')
$base = (Read-SiteConfig (Join-Path $PSScriptRoot 'site.json')).baseUrl
$site = Join-Path $PSScriptRoot '_site'
$session = $null

try {
    # 1. credentials
    $cred = if ($SetCredentials) { $null } else { Read-PublishCredential }
    if (-not $cred) { $cred = Request-PublishCredential }
    [void](Test-PublishCredential $cred)
    Write-Host "target: $($cred.Protocol)://$($cred.User)@$($cred.Host):$($cred.Port)$($cred.RemoteRoot)"

    # 2. build (the build runs the site checks and fails on any problem)
    $manifest = Read-PublishManifest $cred
    $noRewrite = [bool]($manifest -and $manifest.NoRewrite)
    & (Join-Path $PSScriptRoot 'build.ps1') -Out $site -NoRewrite:$noRewrite
    if ($LASTEXITCODE -ne 0) { throw 'build failed; nothing published' }

    # 3. hash the output
    $files = Get-SiteHashes $site

    # 4. manifest, or the first-publish guard
    $session = if ($DryRun -and $manifest) { $null } else { Open-PublishSession $cred }
    if ($manifest) {
        $old = $manifest.Files
    } else {
        $names = Get-RemoteNames $session $cred.RemoteRoot
        Write-Host "first publish: remote root holds $($names.Count) item(s): $($names -join ', ')"
        if (-not (Test-FirstPublishTarget $names) -and -not $AcceptExistingRemote) {
            throw 'remote root is not empty and not the IONOS placeholder: wrong folder? Re-run with -AcceptExistingRemote only if you are sure'
        }
        $old = @{}
    }

    # 5. plan
    $plan = Get-PublishPlan $old $files
    Write-Host "plan: upload $($plan.Upload.Count), delete $($plan.Delete.Count)"
    $plan.Upload | ForEach-Object { Write-Host "  + $_" }
    $plan.Delete | ForEach-Object { Write-Host "  - $_" }
    if ($DryRun) { Write-Host 'dry run: nothing changed'; exit 0 }

    # 6-8. upload, then delete; the manifest is saved after every step, so a publish that
    # dies half-way records exactly what it put on the server (and the retry needs no guard)
    $files = Invoke-PublishPlan $plan $old $files `
        { param($rel) Send-PublishFiles $session $cred.RemoteRoot $site @($rel) } `
        { param($rel) Remove-PublishFile $session $cred.RemoteRoot $rel } `
        { param($f) Write-PublishManifest $cred $f $noRewrite }
    Remove-EmptiedRemoteDirs $session $cred.RemoteRoot (Get-EmptiedRemoteDirs $plan.Delete @($files.Keys))
    Write-PublishManifest $cred $files $noRewrite

    # 9. live checks
    $ok = $true
    $live = Get-HttpStatus "$base/"
    if ($live.Status -eq 500 -and -not $noRewrite) {
        Write-Host "GET $base/ = 500: uploading web.config without the rewrite section"
        $plain = New-WebConfigText ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'web.config'))) $true
        $put = { param($local, $rel) Send-PublishFile $session $cred.RemoteRoot $local $rel }
        $fb = Invoke-RewriteFallback $files $plain $put { (Get-HttpStatus "$base/").Status }
        $files = $fb.Files
        $noRewrite = $fb.NoRewrite
        Write-PublishManifest $cred $files $noRewrite
        if ($noRewrite) { Write-Host 'URL Rewrite missing on IONOS: switch on HTTPS forwarding in the IONOS panel' }
        else { Write-Host "still $($fb.Status) without <rewrite>: another web.config section is refused by IONOS; check the IONOS error log" }
        $live = Get-HttpStatus "$base/"
    }
    Write-Host "GET $base/ = $($live.Status)"
    if (-not (Test-LiveHome $live $base)) { Write-Host 'the live home page is not ours (placeholder or error page)'; $ok = $false }
    $bareUrl = $base -replace '^https://www\.', 'http://'
    $bare = Get-HttpStatus "$bareUrl/"
    Write-Host "GET $bareUrl/ = $($bare.Status) $($bare.Location)"
    if ($bare.Status -ne 301 -or -not $bare.Location.StartsWith($base)) {
        if ($noRewrite) { Write-Host 'redirect missing: switch on HTTPS forwarding in the IONOS panel' }
        $ok = $false
    }

    # 10.
    if (-not $ok) { Write-Host 'PUBLISHED, but a live check failed'; exit 1 }
    Write-Host 'published'
    exit 0
} catch {
    Write-Host "PUBLISH FAILED: $($_.Exception.Message)"
    exit 1
} finally {
    if ($session) { $session.Dispose() }
}
