<#
  run_find_callers_callback_reach.ps1 -- `find-callers --resolved` reports a
  routine that is REACHED as a callback, marked [callback], and still reports
  nothing for a routine that is genuinely dead.

  THE DEFECT THIS PINS:
    A routine handed somewhere by name -- `Register(Pred)`, `@Handler`,
    `OnFoo := Handler` -- produces a refs.kind='read' row and NO call_edges row,
    because it is reached there but not called there. So for the same live
    predicate:

      find-callers --name X             -> 1 caller
      find-callers --name X --resolved  -> 0 callers

    and since --resolved is documented as the PRECISE query, the honest reading
    of that 0 is "dead code". Measured on DataCopy 2026-08-16:
    TfrmZeissCopy.isValidZeissFileName is passed to TDirectory.GetFiles at
    uMainZeissCopy.pas:3303 and had zero resolved callers.

  WHY NOT JUST ADD A CALL EDGE:
    call_edges means CALLS. An edge there is consumed by callgraph, impact and
    call-path as control flow, and there is no call at a bare-name pass -- no
    call site, no arguments. So the reach is reported by find-callers only, with
    a [callback] marker that cannot be mistaken for a call.

  THE CONTROL IS THE POINT:
    D_Orphan is called by nobody and passed to nobody. It MUST still report
    0 callers and exit 1. Without it, "the callback now shows up" would pass
    just as well against a change that reported every routine as reached --
    which is the failure direction that matters here, because this query is what
    people use to decide something is dead.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-callback-reach"
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
$SrcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $SrcDir | Out-Null

$FixtureBody = @'
unit uCallbackReach;

interface

type
  TPickPred = function(const AItem: string): Boolean;

function  A_Predicate(const AItem: string): Boolean;
procedure B_Plain;
procedure C_Driver;
procedure D_Orphan;

implementation

var
  GPick: TPickPred;

{ Reached ONLY by being handed to Choose -- never called. }
function A_Predicate(const AItem: string): Boolean;
begin
  Result := AItem <> '';
end;

{ Called normally by C_Driver -- an ordinary resolved call edge. }
procedure B_Plain;
begin
  Writeln('plain');
end;

{ Neither called nor passed anywhere. THE CONTROL. }
procedure D_Orphan;
begin
  Writeln('orphan');
end;

procedure Choose(P: TPickPred);
begin
  GPick := P;
end;

procedure C_Driver;
begin
  B_Plain;
  Choose(A_Predicate);
end;

end.
'@
$file = Join-Path $SrcDir 'uCallbackReach.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

$Db = Join-Path $WorkDir 'cb.sqlite'
& $Exe index $SrcDir --db $Db 2>&1 | Out-Null
if (-not (Test-Path $Db)) { Write-Host 'FATAL: index produced no DB' -ForegroundColor Red; exit 2 }

function Resolved([string]$Name) {
  $o = & $Exe query find-callers --name $Name --resolved --db $Db 2>&1 | Out-String
  [pscustomobject]@{ Out = $o; Rc = $LASTEXITCODE }
}
$pred   = Resolved 'A_Predicate'
$plain  = Resolved 'B_Plain'
$orphan = Resolved 'D_Orphan'

Write-Host ''
Write-Host 'A routine reached as a CALLBACK is reported, and marked as one' -ForegroundColor Cyan
Check 'A_Predicate has a resolved-path result' ($pred.Rc -eq 0) "rc=$($pred.Rc)"
Check 'it is marked [callback]'                ($pred.Out -match '\[callback\]')
Check 'it names the enclosing routine'         ($pred.Out -match 'C_Driver')
Check 'it is NOT reported as a plain call'     (-not ($pred.Out -match '\[certain\]|\[ambiguous\]'))

Write-Host ''
Write-Host 'An ordinary call is unchanged -- still a real call edge' -ForegroundColor Cyan
Check 'B_Plain has a resolved caller'      ($plain.Rc -eq 0) "rc=$($plain.Rc)"
Check 'B_Plain names C_Driver'             ($plain.Out -match 'C_Driver')
Check 'B_Plain is NOT marked [callback]'   (-not ($plain.Out -match '\[callback\]')) "out=$($plain.Out.Trim())"

Write-Host ''
Write-Host 'CONTROL: a genuinely dead routine is still dead' -ForegroundColor Cyan
Check 'D_Orphan reports 0 caller(s)' ($orphan.Out -match '0 caller\(s\)') "out=$($orphan.Out.Trim())"
Check 'D_Orphan exits 1'             ($orphan.Rc -eq 1)                  "rc=$($orphan.Rc)"
if ($orphan.Rc -ne 1) {
  Write-Host '  !! The control failed: if a dead routine now reports callers,' -ForegroundColor Yellow
  Write-Host '  !! the callback result above proves nothing.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) {
  Write-Host '--- A_Predicate ---'; Write-Host $pred.Out
  Write-Host '--- B_Plain ---';     Write-Host $plain.Out
  Write-Host '--- D_Orphan ---';    Write-Host $orphan.Out
  Write-Host 'FAIL' -ForegroundColor Red; exit 1
} else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
