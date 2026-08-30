<#
  run_lint_uses_global_census.ps1 -- docs\PLAN-coupling-census-and-duplicate-decls.md
  (owner request 2026-08-30).

  THE ASK, verbatim: "Can we give an info message on each mentioning: N
  variables and M consts from unit uAAA. This can be suppressed, say in uses by
  a comment. Such a comment would show that uAAA is strongly coupled with this
  unit and must go together when separated for a test."

  So the acknowledgement is the POINT, not an escape hatch, and most of this
  guard is about it. Two things carry the weight:

  1. THE ACKNOWLEDGEMENT NAMES THE UNIT. A line-bound marker on
     `uses uP1, uP2;` would suppress BOTH edges with one comment, which is
     exactly the accountability the owner asked for, destroyed. The MULTI-ENTRY
     case below is the assertion that proves the unit name is read: uP1 goes
     silent in the same run that uP2 still reports.
  2. A STALE ACKNOWLEDGEMENT IS ITSELF A FINDING. An acknowledgement nobody
     re-checks is worse than none -- it reads as a decision made on purpose.
     Both stale shapes are asserted WITH the real census finding still firing
     in the same run, so neither can pass by the rule having died.

  Every silent assertion here is paired with a reporting one in the SAME run.
  A rule that never fires satisfies every "is suppressed" check ever written.

  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-census"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# --- the provider: two vars, one const, and a type for the zero-census case.
Emit 'uProvider.pas' @'
unit uProvider;
interface
type
  TProvThing = class
  end;
const
  cProvMax = 10;
var
  gProvOne: Boolean;
  gProvTwo: Integer;
implementation
end.
'@

# POSITIVE: 2 vars + 1 const drawn from uProvider.
Emit 'uReaderPos.pas' @'
unit uReaderPos;
interface
uses uProvider;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gProvOne then
    gProvTwo:= cProvMax;
end;
end.
'@

# ZERO CENSUS: uses uProvider but draws only a TYPE from it -> no census line.
Emit 'uReaderType.pas' @'
unit uReaderType;
interface
uses uProvider;
procedure DoWork;
implementation
procedure DoWork;
var
  T: TProvThing;
begin
  T:= nil;
  if T = nil then Exit;
end;
end.
'@

# ACK, trailing on the uses entry's own line.
Emit 'uAckTrail.pas' @'
unit uAckTrail;
interface
uses uProvider; // dl:census-ok uProvider -- travels with it
procedure DoWork;
implementation
procedure DoWork;
begin
  if gProvOne then
    gProvTwo:= cProvMax;
end;
end.
'@

# ACK, alone on the line immediately above the entry.
Emit 'uAckAbove.pas' @'
unit uAckAbove;
interface
uses
  // dl:census-ok uProvider
  uProvider;
procedure DoWork;
implementation
procedure DoWork;
begin
  if gProvOne then
    gProvTwo:= cProvMax;
end;
end.
'@

# ACK, written in a different case. SameText, both sides stemmed.
Emit 'uAckCase.pas' @'
unit uAckCase;
interface
uses uProvider; // dl:census-ok UPROVIDER
procedure DoWork;
implementation
procedure DoWork;
begin
  if gProvOne then
    gProvTwo:= cProvMax;
end;
end.
'@

# MULTI-ENTRY LINE -- the assertion that the unit name is load-bearing.
Emit 'uP1.pas' @'
unit uP1;
interface
var
  gP1Flag: Boolean;
implementation
end.
'@

Emit 'uP2.pas' @'
unit uP2;
interface
var
  gP2Flag: Boolean;
implementation
end.
'@

Emit 'uMulti.pas' @'
unit uMulti;
interface
uses uP1, uP2; // dl:census-ok uP1
procedure DoWork;
implementation
procedure DoWork;
begin
  if gP1Flag then Exit;
  if gP2Flag then Exit;
end;
end.
'@

# STALE, shape 1: the acknowledgement names a unit that is not used at all.
Emit 'uStaleNoUse.pas' @'
unit uStaleNoUse;
interface
uses uProvider; // dl:census-ok uNowhere
procedure DoWork;
implementation
procedure DoWork;
begin
  if gProvOne then
    gProvTwo:= cProvMax;
end;
end.
'@

# STALE, shape 2: it names a used unit this file draws nothing from.
Emit 'uOther.pas' @'
unit uOther;
interface
type
  TOtherThing = class
  end;
implementation
end.
'@

Emit 'uStaleZero.pas' @'
unit uStaleZero;
interface
uses uProvider, uOther; // dl:census-ok uOther
procedure DoWork;
implementation
procedure DoWork;
begin
  if gProvOne then
    gProvTwo:= cProvMax;
end;
end.
'@

# AMBIGUITY: gAmb is declared in TWO units, so it is not attributable to
# either and the census must not count it. Under-counting is the safe
# direction here -- unlike the sibling rule, this one makes no only-link claim.
Emit 'uAmbigProv.pas' @'
unit uAmbigProv;
interface
var
  gAmb: Integer;
implementation
end.
'@

Emit 'uAmbigThird.pas' @'
unit uAmbigThird;
interface
var
  gAmb: Integer;
implementation
end.
'@

Emit 'uAmbigReader.pas' @'
unit uAmbigReader;
interface
uses uAmbigProv;
procedure DoWork;
implementation
procedure DoWork;
begin
  gAmb:= gAmb + 1;
end;
end.
'@

# --- configs ---------------------------------------------------------------
$cfgOn  = Join-Path $WorkDir 'on.json'
$cfgOff = Join-Path $WorkDir 'off.json'
[System.IO.File]::WriteAllText($cfgOn,  '{ "enabled": [ "uses-global-census" ] }',
                               [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($cfgOff, '{ }', [System.Text.Encoding]::ASCII)

# --- index -----------------------------------------------------------------
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecCensus", "db": "census.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\census.sqlite'

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecCensus --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $onOut  = & $Exe lint-all --db $db --config $cfgOn  --quiet 2>&1 | Out-String
  $offOut = & $Exe lint-all --db $db --config $cfgOff --quiet 2>&1 | Out-String
} finally { Pop-Location }

$lines = @($onOut -split "`r?`n" | Where-Object { $_ -match 'uses-global-census' })
function CensusIn([string]$reader) {
  @($lines | Where-Object { $_ -match [regex]::Escape($reader) -and $_ -notmatch 'dl:census-ok names' })
}
function StaleIn([string]$reader) {
  @($lines | Where-Object { $_ -match [regex]::Escape($reader) -and $_ -match 'dl:census-ok names' })
}

Write-Host ''
Write-Host 'THE CENSUS' -ForegroundColor Cyan
$pos = CensusIn 'uReaderPos.pas'
Check 'POSITIVE: uReaderPos -> uProvider is reported once' ($pos.Count -eq 1) `
  ("got " + $pos.Count + " line(s) of " + $lines.Count + " total")
Check 'and it counts 2 variables and 1 const' `
  (($pos -join ' ') -match '2 variable\(s\) and 1 const\(s\)') `
  (($pos -join ' '))
Check 'and it names all three drawn symbols' `
  ((($pos -join ' ') -match 'gprovone') -and (($pos -join ' ') -match 'gprovtwo') -and
   (($pos -join ' ') -match 'cprovmax')) ''
Check 'and it is anchored at the uses line, not line 1' `
  (($pos -join ' ') -match 'uReaderPos\.pas:3:') `
  'the uses entry IS the edge -- it is what gets acknowledged'
Check 'ZERO CENSUS: a reader that draws only a TYPE is silent' `
  ((CensusIn 'uReaderType.pas').Count -eq 0) `
  'no globals drawn means there is no coupling to report'

Write-Host ''
Write-Host 'THE ACKNOWLEDGEMENT' -ForegroundColor Cyan
Check 'TRAILING on the uses entry -> suppressed' `
  ((CensusIn 'uAckTrail.pas').Count -eq 0) ''
Check 'ON THE LINE ABOVE the entry -> suppressed' `
  ((CensusIn 'uAckAbove.pas').Count -eq 0) ''
Check 'CASE-INSENSITIVE unit match -> suppressed' `
  ((CensusIn 'uAckCase.pas').Count -eq 0) ''
Check 'POSITIVE CONTROL: the unacknowledged reader still reports in the same run' `
  ($pos.Count -eq 1) `
  'without this, all three checks above pass with the rule switched off'

Write-Host ''
Write-Host 'MULTI-ENTRY LINE -- the unit name is load-bearing' -ForegroundColor Cyan
$multi = CensusIn 'uMulti.pas'
Check 'the acknowledged unit uP1 is suppressed' `
  (-not (($multi -join ' ') -match 'from uP1')) `
  'RED means the marker is line-bound and took both edges with it'
Check 'and uP2 on the SAME line is still reported' `
  (($multi -join ' ') -match 'from uP2') `
  'RED means the acknowledgement suppressed more than it named'

Write-Host ''
Write-Host 'STALE ACKNOWLEDGEMENTS -- drift, one level down' -ForegroundColor Cyan
$sn = StaleIn 'uStaleNoUse.pas'
$sz = StaleIn 'uStaleZero.pas'
Check 'NOT IN USES: reported at the comment line' ($sn.Count -eq 1) `
  ("got " + $sn.Count + " line(s)")
Check 'and it says the unit is not in the uses clause' `
  (($sn -join ' ') -match 'not in this unit') ''
Check 'and the real census finding still fires for that reader' `
  ((CensusIn 'uStaleNoUse.pas').Count -eq 1) `
  'a stale ack acknowledges nothing, so it must not suppress'
Check 'ZERO CENSUS: an ack on a unit nothing is drawn from is reported' `
  ($sz.Count -eq 1) ("got " + $sz.Count + " line(s)")
Check 'and it says nothing is drawn from it' `
  (($sz -join ' ') -match 'draws no globals') ''
Check 'and that reader still reports its real uProvider census' `
  ((CensusIn 'uStaleZero.pas').Count -eq 1) ''

Write-Host ''
Write-Host 'AMBIGUITY' -ForegroundColor Cyan
Check 'a name declared in two units is attributed to neither -> SILENT' `
  ((CensusIn 'uAmbigReader.pas').Count -eq 0) `
  'the census under-counts rather than guessing; it makes no only-link claim'

Write-Host ''
Write-Host 'OPT-IN GATE' -ForegroundColor Cyan
Check 'DefaultEnabled=False: an un-enabling config reports nothing' `
  (-not ($offOut -match 'uses-global-census')) ''
Check 'POSITIVE CONTROL: the off run still produced other findings' `
  ($offOut -match ':\d+:\d+') `
  'a silent run would pass the check above for the wrong reason'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
