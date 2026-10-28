<#
  run_index_file_failure_exit.ps1 -- a file whose store phase RAISES must make
  `index` say so and exit non-zero (deep review 2026-10-25, finding F1).

  BEFORE: TIndexer.IndexFile caught the exception, rolled the file back, printed
  "ERROR indexing" to STDOUT among the progress lines and counted nothing. The
  run's "Done." summary never mentioned it and `index` exited 0, so the IDE job
  queue said "reindex: done", `index --all` counted the section OK, and every
  query over that unit answered from its OLD parse.

  The failure is driven through the engine's test seam
  DRAGLINT_INDEX_TEST_FAIL_FILE=<file name>: that file's store phase raises just
  before its commit (rolled back exactly like a real constraint / I/O error).

  CASES
    P1  positive control: the same corpus WITHOUT the seam indexes clean,
        exits 0, prints no "failed" note and no ERROR line. Without it, every
        check below could pass against an engine that fails every run.
    F1  `index <dir>` with one failing file: exit 1, the ERROR line names the
        file on STDERR (not stdout), and the Done. summary carries
        "1 file(s) FAILED to index".
    F2  the healthy sibling file still indexed (the run continued past it).
    A1  `index --all` sequential (--jobs 1): the section with the failing file
        is named in the FAILED sections roll-up; the healthy section is not;
        exit 1.
    A2  `index --all --jobs 2` (one child per section): same roll-up.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_filefail_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Set-Location C:\TEMP

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}
function Unit($dir, $name) {
  Write-Ascii (Join-Path $dir "$name.pas") @"
unit $name;

interface

type
  T$name = class
  public
    procedure Work;
  end;

implementation

procedure T$name.Work;
begin
end;

end.
"@
}

$srcBad  = Join-Path $scratch 'srcbad';  New-Item -ItemType Directory -Path $srcBad  | Out-Null
$srcGood = Join-Path $scratch 'srcgood'; New-Item -ItemType Directory -Path $srcGood | Out-Null
Unit $srcBad  'uHealthyA'
Unit $srcBad  'uBroken'
Unit $srcGood 'uHealthyB'

# One OS handle per stream, so stdout and stderr can be told apart.
function Run([string]$ArgLine, [string]$FailFile) {
  $tag = [guid]::NewGuid().ToString('N').Substring(0,8)
  $out = Join-Path $scratch "out-$tag.log"; $err = Join-Path $scratch "err-$tag.log"
  $env:DRAGLINT_INDEX_TEST_FAIL_FILE = $FailFile
  try { cmd /c "`"$exePath`" $ArgLine > `"$out`" 2> `"$err`"" | Out-Null; $code = $LASTEXITCODE }
  finally { $env:DRAGLINT_INDEX_TEST_FAIL_FILE = $null }
  [pscustomobject]@{ Code = $code; Out = [IO.File]::ReadAllText($out); Err = [IO.File]::ReadAllText($err) }
}

# DEC-15: committed= on the section summary line. Returns @{attempted;committed} for the named section, or $null.
function Get-Committed([string]$Text, [string]$Name) {
  $m = [regex]::Match($Text, '(?m)^=== ' + [regex]::Escape($Name) + '\b.*?\sattempted=(\d+)\s+up-to-date=(\d+)\s+committed=(\d+)\s+\[')
  if (-not $m.Success) { return $null }
  return @{ attempted = [int]$m.Groups[1].Value; committed = [int]$m.Groups[3].Value }
}
# ---- P1: positive control, no seam ----
Write-Host 'P1: clean corpus, no fault' -ForegroundColor Cyan
$dbP = Join-Path $scratch 'p1.sqlite'
$r = Run "index `"$srcBad`" --db `"$dbP`"" ''
Check 'P1 exit 0'                 ($r.Code -eq 0) "exit $($r.Code)`n$($r.Err)"
Check 'P1 no ERROR indexing line' (($r.Out + $r.Err) -notmatch 'ERROR indexing')
Check 'P1 Done. without a failed note' (($r.Out -match '(?m)^Done\. ') -and ($r.Out -notmatch 'FAILED to index')) $r.Out

# ---- F1/F2: one file raises ----
Write-Host 'F1: one file fails to index' -ForegroundColor Cyan
$dbF = Join-Path $scratch 'f1.sqlite'
$r = Run "index `"$srcBad`" --db `"$dbF`"" 'uBroken.pas'
Check 'F1 exit 1'                          ($r.Code -eq 1) "exit $($r.Code)"
Check 'F1 ERROR line names the file on STDERR' ($r.Err -match 'ERROR indexing .*uBroken\.pas') "stderr: $($r.Err)"
Check 'F1 ERROR line NOT on stdout'        ($r.Out -notmatch 'ERROR indexing')
Check 'F1 Done. summary counts the failure' ($r.Out -match '(?m)^Done\. .*1 file\(s\) FAILED to index') "stdout tail: $(($r.Out -split "`n" | Select-Object -Last 3) -join ' | ')"
$q = & $exePath query --name TuHealthyA --db $dbF --exact 2>&1 | Out-String
Check 'F2 healthy sibling still indexed'   ($q -match '(?m)^class\s+TuHealthyA\b') $q
$q = & $exePath query --name TuBroken --db $dbF --exact 2>&1 | Out-String
Check 'F2 failed file has no rows (rolled back)' ($q -notmatch '(?m)^class\s+TuBroken\b') $q

# ---- A1/A2: index --all counts the section as failed ----
$outDir = Join-Path $scratch 'out'; New-Item -ItemType Directory -Path $outDir | Out-Null
$cfg = Join-Path $scratch 'all.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 4096, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "$($outDir -replace '\\','\\')",
    "sections": [
      { "name": "WithBroken", "db": "withbroken.sqlite", "include": ["$($srcBad -replace '\\','\\')"] },
      { "name": "AllGood",    "db": "allgood.sqlite",    "include": ["$($srcGood -replace '\\','\\')"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii

foreach ($jobs in 1,2) {
  $id = @{1='A1';2='A2'}[$jobs]
  Write-Host "${id}: index --all --jobs $jobs" -ForegroundColor Cyan
  $r = Run "index --all --config `"$cfg`" --jobs $jobs --rebuild" 'uBroken.pas'
  $roll = ([regex]::Match($r.Err, '(?m)^FAILED sections.*$')).Value
  Check "$id exit 1"                           ($r.Code -eq 1) "exit $($r.Code)"
  Check "$id roll-up names WithBroken"          ($roll -match 'WithBroken') "roll-up: [$roll]`nstderr: $($r.Err)"
  Check "$id roll-up does NOT name AllGood"     ($roll -notmatch 'AllGood') "roll-up: [$roll]"
  $cw = Get-Committed $r.Out 'WithBroken'; $cg = Get-Committed $r.Out 'AllGood'
  Check "$id DEC-15 WithBroken committed = attempted - 1" (($null -ne $cw) -and ($cw.attempted -eq 2) -and ($cw.committed -eq 1)) "line: $(($r.Out -split "`n" | Where-Object { $_ -match '^=== WithBroken' }) -join '')"
  Check "$id DEC-15 AllGood committed = attempted (control)" (($null -ne $cg) -and ($cg.attempted -eq 1) -and ($cg.committed -eq 1)) "line: $(($r.Out -split "`n" | Where-Object { $_ -match '^=== AllGood' }) -join '')"
}

# ---- A0: positive control for --all, no seam ----
Write-Host 'A0: index --all, no fault' -ForegroundColor Cyan
$r = Run "index --all --config `"$cfg`" --jobs 1 --rebuild" ''
Check 'A0 exit 0 and no roll-up' (($r.Code -eq 0) -and ($r.Err -notmatch 'FAILED sections')) "exit $($r.Code) stderr: $($r.Err)"
$c0 = Get-Committed $r.Out 'WithBroken'
Check 'A0 DEC-15 no fault: committed = attempted = 2' (($null -ne $c0) -and ($c0.attempted -eq 2) -and ($c0.committed -eq 2)) "line: $(($r.Out -split "`n" | Where-Object { $_ -match '^=== WithBroken' }) -join '')"

} finally {
  Set-Location C:\TEMP
}
if ($fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0 }
