<#
  run_repo_cli_roundtrip.ps1 -- `drag-lint repo ...` without Firebird (lane TTE, 1.52).

  Drives init / info / backup / restore / gen-memtable / the path resolution of the
  field repository verb family on temp files. The fixtures are the byte-exact backups in
  tests\fixtures\fieldrepo (golden = 6/2/3/1 rows, bad_unknown_column_L28 = a defect on line 28).

  CASES
    R1  restore golden into a missing repo     -> exit 0, file exists
    R2  repo info --json                       -> row counts 6/2/3/1 (golden #end lines), schema_version 1
    R3  repo backup --output                   -> bytes equal the fixture
    R4  second restore without --replace       -> exit 1, counts unchanged; with --replace -> exit 0
    R5  restore bad_unknown_column_L28 (fresh) -> exit 2, stderr has "line 28", NO repository left behind
    R6  repo init on the existing file         -> exit 1; init on a fresh path -> exit 0 and info shows 0 rows
    R7  repo info on a text file               -> exit 1
    R8  --project <tmp>\X.dproj                -> <tmp>\_DL-REPO\X.dlrepo; a fieldRepository key in
        _D-RAG\drag-lint-project.json wins and is relative to the project folder
    R9  usage: no --repo/--project -> 1; unknown sub-verb -> 1 naming the verbs
    R10 gen-memtable --in csv --name Foo -> exit 0, stdout has CreateFooFields; bad FieldType -> exit 2
    R11 import-fb / seed-fb / refresh-schema without --connection -> exit 1

  Run from any CWD, pwsh 7:
    pwsh -File tests\autotest\run_repo_cli_roundtrip.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$Fix  = Join-Path $PSScriptRoot '..\fixtures\fieldrepo'
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-repo-cli-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null

# Runs the engine; returns exit code, stdout, stderr.
function Run([string[]]$a) {
  $errFile = Join-Path $Work ('err-' + [guid]::NewGuid().ToString('N') + '.txt')
  $out = (& { $ErrorActionPreference = 'Continue'; $dlErrFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($errFile); [IO.File]::WriteAllText($dlErrFile, ''); & $Exe @a 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { [IO.File]::AppendAllText($dlErrFile, "$_" + [Environment]::NewLine) } else { $_ } } }) -join "`n"
  $code = $LASTEXITCODE
  $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  [pscustomobject]@{ Code = $code; Out = $out; Err = $err }
}
function Counts($repo) {
  $r = Run @('repo', 'info', '--json', '--repo', $repo)
  if ($r.Code -ne 0) { return $null }
  $j = $r.Out | ConvertFrom-Json | ForEach-Object { $_ }
  ('{0}/{1}/{2}/{3}' -f $j.tables.DL_FIELDS_INFO, $j.tables.DL_DATASETS_INFO, $j.tables.DL_ENUMVALUES, $j.tables.DL_ERROR_MESSAGES)
}

$golden = Join-Path $Fix 'golden.dlrepo.txt'
$bad    = Join-Path $Fix 'bad_unknown_column_L28.dlrepo.txt'
$repo   = Join-Path $Work 'a.dlrepo'

# R1
$r = Run @('repo', 'restore', '--in', $golden, '--repo', $repo)
Check 'R1 restore golden into a missing repo' (($r.Code -eq 0) -and (Test-Path $repo)) "exit=$($r.Code) err=$($r.Err.Trim())"

# R2 (raw shape printed once, so the JSON field names are seen before they are asserted)
$r = Run @('repo', 'info', '--json', '--repo', $repo)
Write-Host "  raw info --json: $($r.Out)"
$j = $null; try { $j = $r.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
Check 'R2 info --json counts 6/2/3/1 + schema_version 1' (($r.Code -eq 0) -and ($j -ne $null) -and ((Counts $repo) -eq '6/2/3/1') -and ($j.schema_version -eq 1)) "exit=$($r.Code)"
$rt = Run @('repo', 'info', '--repo', $repo)
Check 'R2b info text lists the table counts' (($rt.Code -eq 0) -and ($rt.Out -match 'DL_FIELDS_INFO: 6 rows')) "exit=$($rt.Code)"

# R3
$bk = Join-Path $Work 'b.txt'
$r = Run @('repo', 'backup', '--output', $bk, '--repo', $repo)
$same = (Test-Path $bk) -and ([IO.File]::ReadAllBytes($bk) -join ',') -eq ([IO.File]::ReadAllBytes($golden) -join ',')
Check 'R3 backup bytes equal the fixture' (($r.Code -eq 0) -and $same) "exit=$($r.Code)"

# R4
$r = Run @('repo', 'restore', '--in', $golden, '--repo', $repo)
Check 'R4 second restore without --replace fails, counts unchanged' (($r.Code -eq 1) -and ((Counts $repo) -eq '6/2/3/1')) "exit=$($r.Code)"
$r = Run @('repo', 'restore', '--in', $golden, '--repo', $repo, '--replace')
Check 'R4b restore with --replace succeeds' (($r.Code -eq 0) -and ((Counts $repo) -eq '6/2/3/1')) "exit=$($r.Code)"

# R5 (positive control: the same path restores fine with the good fixture in R1)
$repo2 = Join-Path $Work 'c.dlrepo'
$r = Run @('repo', 'restore', '--in', $bad, '--repo', $repo2)
Check 'R5 malformed backup -> exit 2, "line 28", no repository left' (($r.Code -eq 2) -and ($r.Err -match 'line 28') -and (-not (Test-Path $repo2)) -and (-not (Test-Path "$repo2.restoring"))) "exit=$($r.Code) err=$($r.Err.Trim())"

# R6
$r = Run @('repo', 'init', '--repo', $repo)
Check 'R6 init on an existing file -> exit 1, rows untouched' (($r.Code -eq 1) -and ((Counts $repo) -eq '6/2/3/1')) "exit=$($r.Code)"
$repo3 = Join-Path $Work 'sub\d.dlrepo'
$r = Run @('repo', 'init', '--repo', $repo3)
Check 'R6b init on a fresh path -> exit 0, 0/0/0/0' (($r.Code -eq 0) -and (Test-Path $repo3) -and ((Counts $repo3) -eq '0/0/0/0')) "exit=$($r.Code)"

# R7
$txt = Join-Path $Work 'plain.txt'
[IO.File]::WriteAllText($txt, "this is not a database`r`n", [Text.Encoding]::ASCII)
$r = Run @('repo', 'info', '--repo', $txt)
Check 'R7 info on a text file -> exit 1' ($r.Code -eq 1) "exit=$($r.Code)"
$r = Run @('repo', 'info', '--repo', (Join-Path $Work 'nothing.dlrepo'))
Check 'R7b info on a missing file -> exit 1' ($r.Code -eq 1) "exit=$($r.Code)"

# R8
$proj = Join-Path $Work 'X.dproj'
[IO.File]::WriteAllText($proj, '<Project/>', [Text.Encoding]::ASCII)
$r = Run @('repo', 'init', '--project', $proj)
$want = Join-Path $Work '_DL-REPO\X.dlrepo'
Check 'R8 --project resolves to _DL-REPO\X.dlrepo' (($r.Code -eq 0) -and (Test-Path $want)) "exit=$($r.Code)"
$cfgDir = Join-Path $Work '_D-RAG'
[IO.Directory]::CreateDirectory($cfgDir) | Out-Null
[IO.File]::WriteAllText((Join-Path $cfgDir 'drag-lint-project.json'), '{ "fieldRepository": "shared\\db.dlrepo" }', [Text.Encoding]::ASCII)
$r = Run @('repo', 'init', '--project', $proj)
$shared = Join-Path $Work 'shared\db.dlrepo'
Check 'R8b fieldRepository key wins, relative to the project folder' (($r.Code -eq 0) -and (Test-Path $shared)) "exit=$($r.Code) err=$($r.Err.Trim())"
$r = Run @('repo', 'init', '--project', $proj, '--repo', (Join-Path $Work 'explicit.dlrepo'))
Check 'R8c --repo beats the project key' (($r.Code -eq 0) -and (Test-Path (Join-Path $Work 'explicit.dlrepo'))) "exit=$($r.Code)"

# R9
$r = Run @('repo', 'info')
Check 'R9 no --repo/--project -> exit 1' ($r.Code -eq 1) "exit=$($r.Code)"
$r = Run @('repo', 'frobnicate', '--repo', $repo)
Check 'R9b unknown sub-verb -> exit 1 naming the verbs' (($r.Code -eq 1) -and ($r.Err -match 'import-fb') -and ($r.Err -match 'restore')) "exit=$($r.Code)"

# R10
$csv = Join-Path $Work 'f.csv'
[IO.File]::WriteAllText($csv, "FieldName,FieldType,Size,FieldKind`r`nID,Integer,0,Data`r`nNAME,String,40,Data`r`n", [Text.Encoding]::ASCII)
$r = Run @('repo', 'gen-memtable', '--in', $csv, '--name', 'Foo')
Check 'R10 gen-memtable -> exit 0, CreateFooFields on stdout' (($r.Code -eq 0) -and ($r.Out -match 'CreateFooFields')) "exit=$($r.Code) err=$($r.Err.Trim())"
$out = Join-Path $Work 'foo.inc'
$r = Run @('repo', 'gen-memtable', '--in', $csv, '--output', $out)
Check 'R10b gen-memtable --output writes the file (default name FDMemTable)' (($r.Code -eq 0) -and (Test-Path $out) -and ((Get-Content $out -Raw) -match 'CreateFDMemTableFields')) "exit=$($r.Code)"
[IO.File]::WriteAllText($csv, "FieldName,FieldType,Size,FieldKind`r`nID,NoSuchType,0,Data`r`n", [Text.Encoding]::ASCII)
$r = Run @('repo', 'gen-memtable', '--in', $csv)
Check 'R10c bad FieldType -> exit 2' (($r.Code -eq 2) -and ($r.Err -notmatch 'unknown command') -and ($r.Err -match 'NoSuchType|FieldType')) "exit=$($r.Code) err=$($r.Err.Trim())"

# R11
foreach ($v in 'import-fb', 'seed-fb', 'refresh-schema') {
  $r = Run @('repo', $v, '--repo', $repo)
  Check "R11 $v without --connection -> exit 1" (($r.Code -eq 1) -and ($r.Err -match '--connection')) "exit=$($r.Code)"
}

if ($script:Failed) { Write-Host 'REPO CLI ROUNDTRIP: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'REPO CLI ROUNDTRIP: PASS' -ForegroundColor Green
exit 0
