<#
  run_repo_cli_import_fb_live.ps1 -- `drag-lint repo import-fb` against a live Firebird
  (lane TTE, 1.52). SKIPs (exit 0, prints SKIP) unless $env:DL_TEST_FB_CONNECTION holds a
  connection string ("Database=host:path;User=..;Password=..;DriverID=FB"). Firebird is only READ.

  CASES
    I1  import into a fresh repo -> exit 0; per DL_ table the verb's "<table>: <n> rows (source <m>)"
        line has n = m, and n equals `repo info --json`; DL_FIELDS_INFO n > 0
    I2  re-run without --replace -> exit 1, counts unchanged
    I3  re-run with --replace    -> exit 0, a <repo>.before-import-*.txt exists and restores
        (`repo restore`) into a third repository with the same counts

  SET UP (live run): copy a Firebird 4 database to a private folder, start/keep a local FB4 server, then
    $env:DL_TEST_FB_CONNECTION = 'Database=localhost:<path-to-copy>.fdb;User_Name=<user>;Password=<pw>;DriverID=FB'
  and put the folder holding fbclient.dll (64-bit) on PATH. Never point it at a production database.
  Run: pwsh -File tests\autotest\run_repo_cli_import_fb_live.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if ([string]::IsNullOrWhiteSpace($env:DL_TEST_FB_CONNECTION)) { Write-Host 'SKIP live Firebird import (DL_TEST_FB_CONNECTION not set)'; exit 0 }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-live-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
function Run([string[]]$a) {
  $errFile = Join-Path $Work ('err-' + [guid]::NewGuid().ToString('N') + '.txt')
  $out = (& $Exe @a 2> $errFile) -join "`n"
  $code = $LASTEXITCODE
  $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  [pscustomobject]@{ Code = $code; Out = $out; Err = $err }
}
function Tables($repo) { $r = Run @('repo', 'info', '--json', '--repo', $repo); if ($r.Code -ne 0) { return $null }; ($r.Out | ConvertFrom-Json).tables }
$repo = Join-Path $Work 'imp.dlrepo'
$cn = $env:DL_TEST_FB_CONNECTION
$r = Run @('repo', 'import-fb', '--connection', $cn, '--repo', $repo)
Write-Host "  raw import output:`n$($r.Out)"
$t = Tables $repo
$ok = ($r.Code -eq 0) -and ($t -ne $null)
foreach ($n in 'DL_FIELDS_INFO', 'DL_DATASETS_INFO', 'DL_ENUMVALUES', 'DL_ERROR_MESSAGES') {
  $m = [regex]::Match($r.Out, "(?m)^$n`: (\d+) rows \(source (\d+)\)")
  $good = $m.Success -and ($m.Groups[1].Value -eq $m.Groups[2].Value) -and ($t -ne $null) -and ([int]$m.Groups[1].Value -eq $t.$n)
  Check "I1 $n verb line n = m = info" $good ($m.Value)
  if (-not $good) { $ok = $false }
}
Check 'I1 import exit 0 and DL_FIELDS_INFO > 0' ($ok -and ($t.DL_FIELDS_INFO -gt 0)) "exit=$($r.Code)"
$r = Run @('repo', 'import-fb', '--connection', $cn, '--repo', $repo)
Check 'I2 re-run without --replace -> exit 1' (($r.Code -eq 1) -and ((Tables $repo).DL_FIELDS_INFO -eq $t.DL_FIELDS_INFO)) "exit=$($r.Code)"
$r = Run @('repo', 'import-fb', '--connection', $cn, '--repo', $repo, '--replace')
$bk = @(Get-ChildItem -LiteralPath $Work -Filter 'imp.dlrepo.before-import-*.txt')
Check 'I3 --replace -> exit 0 and a before-import backup exists' (($r.Code -eq 0) -and ($bk.Count -eq 1)) "exit=$($r.Code)"
if ($bk.Count -eq 1) {
  $third = Join-Path $Work 'third.dlrepo'
  $r = Run @('repo', 'restore', '--in', $bk[0].FullName, '--repo', $third)
  $t3 = Tables $third
  Check 'I3 the backup restores into a third repo with the same counts' (($r.Code -eq 0) -and ($t3 -ne $null) -and ($t3.DL_FIELDS_INFO -eq $t.DL_FIELDS_INFO) -and ($t3.DL_DATASETS_INFO -eq $t.DL_DATASETS_INFO)) "exit=$($r.Code)"
}
if ($script:Failed) { Write-Host 'REPO CLI IMPORT-FB LIVE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'REPO CLI IMPORT-FB LIVE: PASS' -ForegroundColor Green
exit 0