<#
  run_absolute_aliasing.ps1 -- docs\INBOX-absolute-aliasing-not-modelled.md

  `Overlay: cardinal absolute InVal;` binds Overlay to InVal's storage. The flow
  analysis recorded them as two unrelated locals, so an assignment to either was
  invisible to the other.

  THE NOTE SAID THIS DEFECT WAS INVISIBLE. IT IS NOT -- re-measured 2026-08-28.
  It is masked only in `used-before-assignment` (by the coarse "a bare identifier
  argument might be a var/out def" treatment). In `overwrite-before-read` it is
  LIVE and shipping today, on C:\Projects\DB\ORM3\COMMON\MStreams.pas at 418,
  428 and 438 -- the three `ReverseBytes` overloads:

      InVal  : single                 ;
      Overlay: cardinal absolute InVal;
      InVal  := Value;
      Overlay:= ReverseBytes(Overlay);   <- "dead store", at WARNING severity
      Result := InVal;                   <- but THIS reads it, via the alias

  So the store IS read and the finding is false. That raises this note from
  "unblocks something else" to "fixes three visible false positives".

  GRAMMAR, PROBED FIRST (tools\dumpnode, not read off the grammar comments --
  this repo has been wrong about node names five times):

      declVar: ChildCount=6 NamedChildCount=4
        child[0] identifier  Overlay
        child[2] type        cardinal
        child[3] kAbsolute   absolute     <- a NAMED node
        child[4] identifier  InVal        <- the alias target

  The clause is a reachable child of declVar, so this is an ANALYSIS fix and NOT
  a grammar one: no DRAGLINT_EXTRACTOR_VERSION bump, no full reindex.

  Store-free by construction -- aliasing is pure AST, so these cases run on the
  bare `lint <file>` path with no --db.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_absolute_alias"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# Each routine isolates ONE shape. Types are unmanaged (cardinal/single), so the
# rules apply at all -- a managed type is zero-initialised and never reported.
$fixture = @'
unit uAbsolute;

interface

function AssignTargetReadAlias(V: single): cardinal;
function AssignAliasReadTarget(V: cardinal): single;
function MStreamsShape(const Value: single): single;
function NoAbsoluteControl(V: single): cardinal;
function GenuineDeadStoreControl(V: cardinal): cardinal;

implementation

function AssignTargetReadAlias(V: single): cardinal;
var
  InVal  : single                 ;
  Overlay: cardinal absolute InVal;
begin
  InVal  := V;
  Result := Overlay;
end;

function AssignAliasReadTarget(V: cardinal): single;
var
  InVal  : single                 ;
  Overlay: cardinal absolute InVal;
begin
  Overlay := V;
  Result  := InVal;
end;

function MStreamsShape(const Value: single): single;
var
  InVal  : single                 ;
  Overlay: cardinal absolute InVal;
begin
  InVal   := Value;
  Overlay := Overlay + 1;
  Result  := InVal;
end;

function NoAbsoluteControl(V: single): cardinal;
var
  InVal  : single ;
  Overlay: cardinal;
begin
  InVal  := V;
  Result := Overlay;
end;

function GenuineDeadStoreControl(V: cardinal): cardinal;
var
  Tmp: cardinal;
begin
  Tmp    := 1;
  Tmp    := V;
  Result := Tmp;
end;

end.
'@

$file = Join-Path $WorkDir 'uAbsolute.pas'
Write-Ascii $file $fixture

Push-Location C:\TEMP
try {
  $out = (& $exePath lint $file --rules-dir $rules 2>&1 | Out-String)
  $srcLines = [System.IO.File]::ReadAllLines($file)
  $rows = @()
  foreach ($l in ($out -split "`r?`n")) {
    if ($l -match ':(\d+):\d+\s+\[(\w+)\]\s+([a-z-]+):') {
      $rows += [pscustomobject]@{ Line=[int]$Matches[1]; Rule=$Matches[3]; Text=$l.Trim() }
    }
  }
  Write-Host '  findings:' -ForegroundColor DarkGray
  foreach ($r in $rows) { Write-Host ("    " + $r.Text) -ForegroundColor DarkGray }

  # Attribute a finding to the routine that encloses its line.
  function RoutineOf([int]$Line) {
    for ($i = $Line - 1; $i -ge 0; $i--) {
      if ($srcLines[$i] -match '^\s*(procedure|function)\s+(\w+)') { return $Matches[2] }
    }
    return ''
  }
  function Has([string]$Routine, [string]$Rule) {
    foreach ($r in $rows) { if ($r.Rule -eq $Rule -and (RoutineOf $r.Line) -eq $Routine) { return $true } }
    return $false
  }

  # ---- THE FIX. Both directions: the alias and its target are one storage cell.
  Check 'A1 assign target, read alias -> no used-before-assignment' `
        (-not (Has 'AssignTargetReadAlias' 'used-before-assignment')) 'Overlay reported despite InVal being assigned'
  Check 'A2 assign alias, read target -> no used-before-assignment' `
        (-not (Has 'AssignAliasReadTarget' 'used-before-assignment')) 'InVal reported despite Overlay being assigned'

  # ---- THE LIVE FALSE POSITIVE, reproduced from MStreams.pas.
  Check 'A3 MStreams shape -> no overwrite-before-read dead store' `
        (-not (Has 'MStreamsShape' 'overwrite-before-read')) `
        'the store through the alias is read via the target -- not a dead store'
  Check 'A4 MStreams shape -> no used-before-assignment either' `
        (-not (Has 'MStreamsShape' 'used-before-assignment')) 'Overlay is assigned through InVal'

  # ---- POSITIVE CONTROLS. Without these, a "fix" that stopped reporting the
  #      second local of any two-local routine -- or switched the rules off --
  #      would pass everything above.
  Check 'C1 CONTROL without `absolute`, the same shape IS still reported' `
        (Has 'NoAbsoluteControl' 'used-before-assignment') `
        'the control stopped firing: the fix is over-broad, not alias-aware'
  Check 'C2 CONTROL a genuine dead store IS still reported' `
        (Has 'GenuineDeadStoreControl' 'overwrite-before-read') `
        'overwrite-before-read stopped firing entirely'

  # ---- A THIRD RULE, found while building this guard: `write-only-local` says
  #      InVal is "assigned but never read" in AssignTargetReadAlias, where it is
  #      read through Overlay. Same root, so it must close with the others.
  Check 'A5 assign target, read alias -> no write-only-local on the target' `
        (-not (Has 'AssignTargetReadAlias' 'write-only-local')) `
        'InVal is read through Overlay'
  Check 'C3 CONTROL a genuinely write-only local IS still reported' `
        (Has 'NoAbsoluteControl' 'write-only-local') `
        'write-only-local stopped firing entirely'

  Check 'VACUITY the linter produced findings at all' ($rows.Count -gt 0) `
        'no findings whatsoever -- the fixture is measuring nothing'
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
