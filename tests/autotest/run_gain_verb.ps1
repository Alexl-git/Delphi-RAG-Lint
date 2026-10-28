<#
  run_gain_verb.ps1 --
  Counted savings: reader verbs append one line to %LOCALAPPDATA%\drag-lint\usage.log
  and `drag-lint gain` sums it (XERJ item 1, 138-DURING-REPARSE lane xj-1).

  Before this, the only record of what the index saved was a hand-written
  stats\draglint-usage.log. A saving nobody counts is a claim, not a number.

  LINE: ISO8601 <TAB> verb <TAB> db_tag <TAB> tokens_returned <TAB> units_avoided <TAB> bytes_avoided
  tokens_avoided = bytes_avoided / 4 (derived by `gain`, never stored).

  THE CHECKS, and what each rules out:
    T1  `context` on a fixture appends EXACTLY ONE line with tokens_returned > 0 and
        bytes_avoided >= the target unit's size       -> the hook exists and measures
    T1b query --text, query --name and find-callers each append one line
    T2  `gain --json` over a hand-written 3-line log returns the summed numbers, per
        verb and per day, and --since drops the older lines
    T3  DRAGLINT_USAGE_LOG=0 writes nothing (positive control: the verb still answers)
    T4  an unwritable LOCALAPPDATA changes neither the output nor the exit code
        (positive control: same output as the writable run)
    T5  an empty/missing log is an all-zero report, exit 0

  Run from any CWD, pwsh 7. Builds its own fixture; points LOCALAPPDATA at scratch.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_gain_verb_$PID"
)
$savedLocal = $env:LOCALAPPDATA
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
Remove-Item Env:\DRAGLINT_USAGE_LOG -ErrorAction SilentlyContinue

Write-Ascii (Join-Path $src 'uW.pas') @"
unit uW;

interface

type
  TW = class
  public
    class procedure Save(const AName: string);
  end;

implementation

class procedure TW.Save(const AName: string);
begin
end;

end.
"@
Write-Ascii (Join-Path $src 'uUse.pas') @"
unit uUse;

interface

procedure Run;

implementation

uses uW;

procedure Run;
begin
  TW.Save('zzgainphrase a');
  TW.Save('zzgainphrase b');
end;

end.
"@
$db = Join-Path $WorkDir 'gain.sqlite'
$env:LOCALAPPDATA = Join-Path $WorkDir 'la0'    # index with the log pointed away from the checks
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V fixture index was built' (Test-Path $db) $db
$uWSize = (Get-Item (Join-Path $src 'uW.pas')).Length

function Fresh-Local([string]$n) {
  $d = Join-Path $WorkDir $n
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  $env:LOCALAPPDATA = $d
  return (Join-Path $d 'drag-lint\usage.log')
}
function Log-Lines([string]$p) { if (Test-Path $p) { return @(Get-Content $p | Where-Object { $_ -ne '' }) } else { return @() } }

# ---- T1: context appends exactly one line ------------------------------------
$log = Fresh-Local 'la1'
$out = (& $exePath context --task 'modify uW.TW.Save' --db $db 2>$null) -join "`n"
$ctxExit = $LASTEXITCODE
$ln = @(Log-Lines $log)
Check 'T1 context appended exactly one usage line' ($ln.Count -eq 1) "lines=$($ln.Count) log=$log"
$f = if ($ln.Count -ge 1) { $ln[0] -split "`t" } else { @() }
Check 'T1a the line has 6 tab-separated fields: iso, verb, db, tokens, units, bytes' ($f.Count -eq 6 -and $f[0] -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$') ($ln -join ' | ')
Check 'T1b verb = context, db tag = gain'                 ($f.Count -eq 6 -and $f[1] -eq 'context' -and $f[2] -eq 'gain') ($ln -join ' | ')
Check 'T1c tokens_returned > 0'                           ($f.Count -eq 6 -and [int64]$f[3] -gt 0) ($ln -join ' | ')
Check "T1d bytes_avoided >= the target unit's size ($uWSize)" ($f.Count -eq 6 -and [int64]$f[5] -ge $uWSize) ($ln -join ' | ')
Check 'T1e units_avoided counts the target unit AND the caller unit (2)' ($f.Count -eq 6 -and [int]$f[4] -eq 2) ($ln -join ' | ')

# ---- T1b: the other reader hooks each append one line -------------------------
foreach ($case in @(
  @{ verb = 'query';        args = @('query','--text','zzgainphrase','--db',$db) },
  @{ verb = 'query';        args = @('query','--name','Save','--db',$db) },
  @{ verb = 'find-callers'; args = @('query','find-callers','--name','Save','--db',$db) })) {
  $log = Fresh-Local ('la_' + [guid]::NewGuid().ToString('N').Substring(0,6))
  & $exePath @($case.args) 2>$null | Out-Null
  $ln = @(Log-Lines $log)
  Check ("T1f '" + ($case.args[0..2] -join ' ') + "' appends one '" + $case.verb + "' line") (($ln.Count -eq 1) -and ($ln[0] -split "`t")[1] -eq $case.verb) ($ln -join ' | ')
}

# ---- T2: gain --json over a hand-written log ----------------------------------
$log = Fresh-Local 'la2'
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
$hand = @(
  "2026-10-01T10:00:00Z`tcontext`tdbA`t100`t2`t4000",
  "2026-10-01T11:00:00Z`tquery`tdbA`t50`t1`t2000",
  "2026-10-02T09:00:00Z`tcontext`tdbA`t150`t3`t6000") -join "`r`n"
[IO.File]::WriteAllText($log, $hand + "`r`n", [Text.Encoding]::ASCII)
$g = (& $exePath gain --json 2>$null) -join "`n" | ConvertFrom-Json
Check 'T2 gain --json total: calls 3, tokens_returned 300, tokens_avoided 3000' (($g.total.calls -eq 3) -and ($g.total.tokens_returned -eq 300) -and ($g.total.tokens_avoided -eq 3000)) ($g.total | ConvertTo-Json -Compress)
Check 'T2b ratio = tokens_avoided / tokens_returned = 10' ([math]::Abs($g.total.ratio - 10) -lt 0.01) "ratio=$($g.total.ratio)"
$cv = @($g.by_verb | Where-Object { $_.verb -eq 'context' })
Check 'T2c by_verb context: 2 calls, 250 returned, 2500 avoided' (($cv.Count -eq 1) -and ($cv[0].calls -eq 2) -and ($cv[0].tokens_returned -eq 250) -and ($cv[0].tokens_avoided -eq 2500)) ($g.by_verb | ConvertTo-Json -Compress)
Check 'T2d by_day has 2 days: 2026-10-01 (2 calls) and 2026-10-02 (1 call)' ((@($g.by_day).Count -eq 2) -and ($g.by_day[0].day -eq '2026-10-01') -and ($g.by_day[0].calls -eq 2) -and ($g.by_day[1].calls -eq 1)) ($g.by_day | ConvertTo-Json -Compress)
$gs = (& $exePath gain --json --since 2026-10-02 2>$null) -join "`n" | ConvertFrom-Json
Check 'T2e --since 2026-10-02 keeps only the last line (1 call, 150 returned)' (($gs.total.calls -eq 1) -and ($gs.total.tokens_returned -eq 150)) ($gs.total | ConvertTo-Json -Compress)
$gt = (& $exePath gain 2>$null) -join "`n"
Check 'T2f the text form has a TOTAL row with 3 calls, 300 returned, 3000 avoided' ($gt -match 'TOTAL\s+3\s+300\s+3000\s') $gt

# ---- T3: DRAGLINT_USAGE_LOG=0 writes nothing ---------------------------------
$log = Fresh-Local 'la3'
$env:DRAGLINT_USAGE_LOG = '0'
$off = (& $exePath context --task 'modify uW.TW.Save' --db $db 2>$null) -join "`n"
Remove-Item Env:\DRAGLINT_USAGE_LOG
Check 'T3 DRAGLINT_USAGE_LOG=0 writes no log line' ((Log-Lines $log).Count -eq 0) "log exists: $(Test-Path $log)"
Check 'T3b POSITIVE CONTROL: the verb still answers with the log off' ($off -match '## Callers') ''

# ---- T4: an unwritable LOCALAPPDATA does not change the verb ------------------
$bad = Join-Path $WorkDir 'la4'
New-Item -ItemType Directory -Path $bad -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $bad 'drag-lint'), 'a file where the log directory should be')   # ForceDirectories cannot succeed
$env:LOCALAPPDATA = $bad
$bo = (& $exePath context --task 'modify uW.TW.Save' --db $db 2>$null) -join "`n"
$badExit = $LASTEXITCODE
Check 'T4 an unwritable log location leaves the exit code unchanged' ($badExit -eq $ctxExit) "bad=$badExit good=$ctxExit"
Check 'T4b POSITIVE CONTROL: and the verb still prints its bundle' ($bo -match '## Callers') ''

# ---- T5: a missing log is an all-zero report ---------------------------------
$null = Fresh-Local 'la5'
$z = (& $exePath gain --json 2>$null) -join "`n" | ConvertFrom-Json
Check 'T5 missing log: gain --json total.calls = 0, exit 0' (($z.total.calls -eq 0) -and ($LASTEXITCODE -eq 0)) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  $env:LOCALAPPDATA = $savedLocal
  Remove-Item Env:\DRAGLINT_USAGE_LOG -ErrorAction SilentlyContinue
  foreach ($d23 in @("C:\TEMP\draglint_gain_verb_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
