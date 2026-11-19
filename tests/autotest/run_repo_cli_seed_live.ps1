<#
  run_repo_cli_seed_live.ps1 -- `drag-lint repo seed-fb` / `refresh-schema` against a live
  Firebird (lane TTE, 1.52). SKIPs (exit 0, prints SKIP) unless $env:DL_TEST_FB_CONNECTION is
  set. Firebird is only READ.

  CASES
    S1  init, then seed-fb --dry-run  -> exit 0, "dry run", repository still 0 rows
    S2  seed-fb                       -> exit 0, DL_FIELDS_INFO > 0, DL_DATASETS_INFO > 0, meta source_database set
    S3  seed-fb again (not empty)     -> exit 1, counts unchanged
    S4  refresh-schema --dry-run      -> exit 0, counts unchanged; refresh-schema -> exit 0,
        the field count does not change (nothing new in the schema)
    S5  the stdout / stderr of every call never contains the Password value

  SET UP (live run): copy a Firebird 4 database to a private folder, start/keep a local FB4 server, then
    $env:DL_TEST_FB_CONNECTION = 'Database=localhost:<path-to-copy>.fdb;User_Name=<user>;Password=<pw>;DriverID=FB'
  and put the folder holding fbclient.dll (64-bit) on PATH. Never point it at a production database.
  Run: pwsh -File tests\autotest\run_repo_cli_seed_live.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if ([string]::IsNullOrWhiteSpace($env:DL_TEST_FB_CONNECTION)) { Write-Host 'SKIP live Firebird seed (DL_TEST_FB_CONNECTION not set)'; exit 0 }
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
$repo = Join-Path $Work 'seed.dlrepo'
$cn = $env:DL_TEST_FB_CONNECTION
$pw = [regex]::Match($cn, '(?i)Password=([^;]*)').Groups[1].Value
$all = New-Object System.Text.StringBuilder
function Rec($r) { [void]$all.AppendLine($r.Out); [void]$all.AppendLine($r.Err); $r }
$r = Rec (Run @('repo', 'init', '--repo', $repo))
$r = Rec (Run @('repo', 'seed-fb', '--connection', $cn, '--repo', $repo, '--dry-run'))
Write-Host "  raw dry-run output:`n$($r.Out)"
Check 'S1 seed-fb --dry-run -> exit 0, nothing written' (($r.Code -eq 0) -and ($r.Out -match 'dry run') -and ((Tables $repo).DL_FIELDS_INFO -eq 0)) "exit=$($r.Code) err=$($r.Err.Trim())"
$r = Rec (Run @('repo', 'seed-fb', '--connection', $cn, '--repo', $repo))
$t = Tables $repo
$meta = (Run @('repo', 'info', '--json', '--repo', $repo)).Out | ConvertFrom-Json
Check 'S2 seed-fb -> exit 0, fields + datasets filled, source_database set' (($r.Code -eq 0) -and ($t.DL_FIELDS_INFO -gt 0) -and ($t.DL_DATASETS_INFO -gt 0) -and ($meta.meta.source_database)) "exit=$($r.Code) err=$($r.Err.Trim())"
$r = Rec (Run @('repo', 'seed-fb', '--connection', $cn, '--repo', $repo))
Check 'S3 seed-fb on a filled repo -> exit 1, counts unchanged' (($r.Code -eq 1) -and ((Tables $repo).DL_FIELDS_INFO -eq $t.DL_FIELDS_INFO)) "exit=$($r.Code)"
$r = Rec (Run @('repo', 'refresh-schema', '--connection', $cn, '--repo', $repo, '--dry-run'))
Check 'S4 refresh-schema --dry-run -> exit 0, counts unchanged' (($r.Code -eq 0) -and ((Tables $repo).DL_FIELDS_INFO -eq $t.DL_FIELDS_INFO)) "exit=$($r.Code)"
$r = Rec (Run @('repo', 'refresh-schema', '--connection', $cn, '--repo', $repo))
Check 'S4b refresh-schema -> exit 0, field count unchanged' (($r.Code -eq 0) -and ((Tables $repo).DL_FIELDS_INFO -eq $t.DL_FIELDS_INFO)) "exit=$($r.Code)"
if ($pw) { Check 'S5 the password never appears in any output' (-not $all.ToString().Contains($pw)) } else { Write-Host 'S5 skipped: the connection string has no Password=' }
if ($script:Failed) { Write-Host 'REPO CLI SEED LIVE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'REPO CLI SEED LIVE: PASS' -ForegroundColor Green
exit 0