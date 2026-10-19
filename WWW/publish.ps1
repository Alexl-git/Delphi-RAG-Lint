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
. (Join-Path $PSScriptRoot 'lib\Publish.ps1')
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

    # 6-7. upload, then delete
    Send-PublishFiles $session $cred.RemoteRoot $site $plan.Upload
    Remove-PublishFiles $session $cred.RemoteRoot $plan.Delete

    # 8. manifest only after full success
    Write-PublishManifest $cred $files $noRewrite

    # 9. live checks
    $ok = $true
    $home200 = Get-HttpStatus 'https://www.delphi-rag-lint.com/'
    if ($home200.Status -eq 500 -and -not $noRewrite) {
        Write-Host 'GET https://www.delphi-rag-lint.com/ = 500: retrying without the rewrite section'
        & (Join-Path $PSScriptRoot 'build.ps1') -Out $site -NoRewrite
        if ($LASTEXITCODE -ne 0) { throw 'build -NoRewrite failed' }
        Send-PublishFiles $session $cred.RemoteRoot $site @('web.config')
        $noRewrite = $true
        Write-PublishManifest $cred (Get-SiteHashes $site) $true
        Write-Host 'URL Rewrite missing on IONOS: switch on HTTPS forwarding in the IONOS panel'
        $home200 = Get-HttpStatus 'https://www.delphi-rag-lint.com/'
    }
    Write-Host "GET https://www.delphi-rag-lint.com/ = $($home200.Status)"
    if ($home200.Status -ne 200) { $ok = $false }
    $bare = Get-HttpStatus 'http://delphi-rag-lint.com/'
    Write-Host "GET http://delphi-rag-lint.com/ = $($bare.Status) $($bare.Location)"
    if ($bare.Status -ne 301 -or -not $bare.Location.StartsWith('https://www.delphi-rag-lint.com')) {
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
