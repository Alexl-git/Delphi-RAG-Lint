<#
  run_cap_reporting.ps1 --
  Every capped list SAYS it was capped (XERJ item 2, 138-DURING-REPARSE lane xj-1).

  DEFECT (audit 2026-10-28). `context --max-callers 3` printed `## Callers (3)` for a
  symbol with 7 callers (the count of the TRUNCATED list); `query --text --limit 2`
  printed `2 match(es)` for a phrase with 5 hits; `top --limit 1` printed `1 row(s)`.
  An agent reading any of them concluded the answer was complete.

  CONTRACT.
    * context: `## Callers (3 of 7)` + the note line `-- 4 omitted by cap 3; rerun
      with --max-callers 7`; `--format json` carries `omitted` and `cap` keys.
    * query --text / top: the note `-- at least N omitted by cap C; rerun with --limit M`
      (a lower bound: the reader fetched cap + 1). With --json the stdout stays a bare
      array and the note goes to stderr.
    * The exit code is UNCHANGED by the cap (owner ruling).

  POSITIVE CONTROLS (a test asserting only "the note appears" passes with a note that
  always prints): a cap that is NOT reached prints no omitted line and JSON omitted = 0.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_cap_reporting_$PID"
)
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
$env:DRAGLINT_USAGE_LOG = '0'   # this suite is about the cap, not the usage log

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
# 7 distinct call sites, each with a literal that holds the phrase zzcapphrase.
$calls = (1..7 | ForEach-Object { "  TW.Save('zzcapphrase $_');" }) -join "`r`n"
Write-Ascii (Join-Path $src 'uUse.pas') @"
unit uUse;

interface

procedure Run;

implementation

uses uW;

procedure Run;
begin
$calls
end;

end.
"@
$db = Join-Path $WorkDir 'cap.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V fixture index was built' (Test-Path $db) $db

function Run-Ctx([string[]]$Extra) { (& $exePath context --task 'modify uW.TW.Save' --db $db @Extra 2>$null) -join "`n" }

# ---- T1: context, cap below the caller count ---------------------------------
$m = Run-Ctx @('--max-callers', '3', '--format', 'markdown')
Check 'T1 context header says `3 of 7`'                      ($m -match '## Callers \(3 of 7\)') (($m -split "`n" | Where-Object { $_ -match 'Callers' }) -join ' | ')
Check 'T1b context prints the omitted note with the rerun hint' ($m -match '-- 4 omitted by cap 3; rerun with --max-callers 7') ''
$j = (Run-Ctx @('--max-callers', '3', '--format', 'json')) | ConvertFrom-Json
Check 'T1c context --format json: omitted = 4'               ($j.omitted -eq 4) "omitted=$($j.omitted)"
Check 'T1d context --format json: cap = 3 (and caller_count stays 3)' (($j.cap -eq 3) -and ($j.caller_count -eq 3)) "cap=$($j.cap) caller_count=$($j.caller_count)"

# ---- P1: positive control, cap not reached -----------------------------------
$m2 = Run-Ctx @('--max-callers', '50', '--format', 'markdown')
Check 'P1 POSITIVE CONTROL: --max-callers 50 prints `Callers (7)` and no omitted line' (($m2 -match '## Callers \(7\)') -and -not ($m2 -match 'omitted')) (($m2 -split "`n" | Where-Object { $_ -match 'Callers|omitted' }) -join ' | ')
$j2 = (Run-Ctx @('--max-callers', '50', '--format', 'json')) | ConvertFrom-Json
Check 'P1b POSITIVE CONTROL: JSON omitted = 0, cap = 50'     (($j2.omitted -eq 0) -and ($j2.cap -eq 50)) "omitted=$($j2.omitted) cap=$($j2.cap)"

# ---- T2: query --text --limit 2 -----------------------------------------------
$full = @(& $exePath query --text zzcapphrase --db $db --limit 50 2>$null)
$nFull = @($full | Where-Object { $_ -match 'zzcapphrase' }).Count
Check "V the phrase has more than 2 hits (got $nFull)" ($nFull -ge 3) ($full -join ' | ')
$t = @(& $exePath query --text zzcapphrase --db $db --limit 2 2>$null)
$tExit = $LASTEXITCODE
$fullExit = $null; & $exePath query --text zzcapphrase --db $db --limit 50 2>&1 | Out-Null; $fullExit = $LASTEXITCODE
Check 'T2 query --text --limit 2 prints an omitted note' (($t -join "`n") -match '-- at least \d+ omitted by cap 2; rerun with --limit 4') ($t -join ' | ')
Check 'T2b exit code is unchanged by the cap'            ($tExit -eq $fullExit) "capped=$tExit uncapped=$fullExit"
Check 'T2c POSITIVE CONTROL: --limit 50 prints no omitted line' (-not (($full -join "`n") -match 'omitted')) ''

# ---- T3: query --text --json keeps stdout a bare array ------------------------
$jj = (& $exePath query --text zzcapphrase --db $db --limit 2 --json 2>$null) -join "`n"
$arr = $jj | ConvertFrom-Json
Check 'T3 query --text --json stdout stays a parseable array of 2' (@($arr).Count -eq 2) $jj.Substring(0, [Math]::Min(120, $jj.Length))
$errF = Join-Path $WorkDir "err.txt"; & $exePath query --text zzcapphrase --db $db --limit 2 --json 2>$errF | Out-Null; $err = (Get-Content $errF) -join "`n"
Check 'T3b the note goes to stderr under --json'            ($err -match 'omitted by cap 2') $err

# ---- T4: top --limit 1 ---------------------------------------------------------
$tp = @(& $exePath top --db $db --limit 1 2>$null)
Check 'T4 top --limit 1 prints an omitted note'             (($tp -join "`n") -match '-- at least 1 omitted by cap 1; rerun with --limit 2') ($tp -join ' | ')
Check 'T4b top --limit 1 prints exactly one data row'       (@($tp | Where-Object { $_ -match '^\s+\d+\s' }).Count -eq 1) ($tp -join ' | ')
$tp2 = @(& $exePath top --db $db --limit 500 2>$null)
Check 'T4c POSITIVE CONTROL: top --limit 500 prints no omitted line' (-not (($tp2 -join "`n") -match 'omitted')) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  Remove-Item Env:\DRAGLINT_USAGE_LOG -ErrorAction SilentlyContinue
  foreach ($d23 in @("C:\TEMP\draglint_cap_reporting_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
