# tools\shoot.ps1 reports sideways overflow (the iframe's scrolling="no" would clip it out of the
# picture) and leaves no _shoot* copy behind. Needs Edge; skipped without it.
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
if (-not (Test-Path -LiteralPath $edge)) { Write-Host 'SKIP test_shoot: no Edge'; return }
$shoot = Join-Path $PSScriptRoot '..\tools\shoot.ps1'
$site = New-TestDir
$csp = '<meta http-equiv="Content-Security-Policy" content="script-src ''self''">'
foreach ($k in @{ wide = '<div style="width:900px">wide</div>'; fits = '<p>fits</p>' }.GetEnumerator()) {
    [void][IO.Directory]::CreateDirectory((Join-Path $site $k.Key))
    [IO.File]::WriteAllText((Join-Path $site "$($k.Key)\index.html"),
        "<!doctype html><html><head>$csp</head><body style=""margin:0"">$($k.Value)</body></html>", [Text.ASCIIEncoding]::new())
}
foreach ($case in @(@{ page = 'wide'; code = 1; like = '*375 px: OVERFLOW*' }, @{ page = 'fits'; code = 0; like = '*375 px: fits*' })) {
    $out = New-TestDir
    $log = & pwsh -NoProfile -File $shoot -Site $site -Page "$($case.page)\index.html" -Out $out -Widths 375 2>&1 | Out-String
    Assert-Equal $case.code $LASTEXITCODE "$($case.page): exit code ($log)"
    Assert-True ($log -like $case.like) "$($case.page): reported ($log)"
    Assert-True (Test-Path -LiteralPath (Join-Path $out "$($case.page)-375.png")) "$($case.page): png written"
}
Assert-Equal 0 @(Get-ChildItem -LiteralPath $site -Recurse -Filter '_shoot*').Count 'no _shoot* left in the site'
