<#
  run_unused_param_addr_taken.ps1 -- a routine whose ADDRESS is taken, or which is
  handed to another routine by BARE NAME, has a signature it does not control, so
  its unused parameters are not removable and must not be reported.

  THE DEFECT THIS PINS:
    unused-parameter already exempts the ways a signature can be externally fixed
    that it happened to know about: virtual/dynamic/override/message/abstract (the
    ContractMethods two-pass), a leading `Sender`, and a hardcoded list of TForm
    event names. It knew nothing about the most ordinary mechanism of all --
    passing the routine itself somewhere as a callback. Measured on DataCopy
    2026-08-16: 4 of the 5 unused-parameter findings were callbacks.

      Register(Pred1);        { bare name  -- uMainZeissCopy.pas:3303 }
      Register(@Handler1);    { address-of -- EExtraExceptionInfo.pas:529 }

  WHY SYNTACTIC AND NOT STORE-BACKED:
    One of the four real registrations (EExtraExceptionInfo.pas:533) sits inside an
    INACTIVE {$IFDEF}. The symbol store has no ref for it -- there is no compiled
    call -- but the raw tree-sitter parse does see it. A store-backed check would
    therefore still report that one. It also has to work on the plain `lint <file>`
    path, which has no store at all. Case A4 below is that shape.

  ACCEPTED IMPRECISION, deliberately pinned by A5:
    Matching is by BARE NAME, so a method sharing a name with an addr-taken free
    routine is also suppressed. That is the same trade-off ContractMethods already
    makes, and A5 exists so the next reader finds it documented rather than
    discovering it as a surprise.

  THE CONTROL IS THE POINT:
    A1 is an ordinary routine with a genuinely unused parameter, called normally
    and never passed anywhere. It MUST still fire. Without it, A2..A5's four
    silences would pass just as happily with the whole rule switched off -- which
    is exactly how two narrowings in session 22 nearly shipped broken.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-unused-param-addr"
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

$FixtureBody = @'
unit uUnusedParamAddr;

interface

type
  TFilterPred  = function(const APath: string; const ARec: Integer): Boolean;
  THandlerProc = procedure(const AMsg: string);

  TThing = class
  public
    function Shared(const AKey: string; const AExtra: Integer): Boolean;
  end;

procedure Plain(A, B: Integer);
function  Pred1(const APath: string; const ARec: Integer): Boolean;
procedure Handler1(const AMsg: string);
procedure Handler2(const AMsg: string);
function  Shared(const AKey: string): Boolean;
procedure Driver;

implementation

var
  GPred: TFilterPred ;
  GHand: THandlerProc;
  GAddr: Pointer     ;

{ A1 -- THE POSITIVE CONTROL. B is genuinely unused, and Plain is called
  normally and never handed to anybody. This one MUST still be reported. }
procedure Plain(A, B: Integer);
begin
  Writeln(A);
end;

{ A2 -- ARec unused, but Pred1 is passed by BARE NAME to Register1, so its
  signature belongs to TFilterPred. Silent. }
function Pred1(const APath: string; const ARec: Integer): Boolean;
begin
  Result := APath <> '';
end;

{ A3 -- AMsg unused, but Handler1 is registered via @Handler1. Silent. }
procedure Handler1(const AMsg: string);
begin
  Writeln('h1');
end;

{ A4 -- AMsg unused; the ONLY registration sits in an inactive $IFDEF, which
  no symbol store can see but the raw parse can. Silent.
  NOTE: do not write a brace-directive inside a brace comment here -- the first
  closing brace ends the comment and the rest of the line becomes garbage code,
  which silently corrupts the parse and makes the cases below pass vacuously. }
procedure Handler2(const AMsg: string);
begin
  Writeln('h2');
end;

{ Free routine, uses its parameter, and its address is taken below. Not itself
  a finding -- it exists so A5 has something to collide with. }
function Shared(const AKey: string): Boolean;
begin
  Result := AKey <> '';
end;

{ A5 -- AExtra is unused and TThing.Shared is passed to nobody. It is silent
  ONLY because its bare name collides with the addr-taken free Shared above.
  This documents the accepted imprecision; it is not a correctness claim. }
function TThing.Shared(const AKey: string; const AExtra: Integer): Boolean;
begin
  Result := AKey <> '';
end;

procedure Register1(P: TFilterPred);
begin
  GPred := P;
end;

procedure Register2(H: THandlerProc);
begin
  GHand := H;
end;

procedure Driver;
begin
  Plain(1, 2);
  Register1(Pred1);
  Register2(@Handler1);
{$IFDEF NEVER_DEFINED_XYZ}
  Register2(@Handler2);
{$ENDIF}
  GAddr := @Shared;
end;

end.
'@
$file = Join-Path $WorkDir 'uUnusedParamAddr.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

# Anchor each case on its IMPLEMENTATION header. Every routine is named twice
# (interface + implementation), so -Last is required; -First would put every
# anchor in the interface block and attribute every finding to one routine.
$src = Get-Content $file
function Impl-Row([string]$Pattern) {
  ($src | Select-String -Pattern $Pattern -SimpleMatch | Select-Object -Last 1).LineNumber
}
$rows = [ordered]@{}
$rows['A1_Plain']    = Impl-Row 'procedure Plain(A, B: Integer);'
$rows['A2_Pred1']    = Impl-Row 'function Pred1(const APath: string; const ARec: Integer): Boolean;'
$rows['A3_Handler1'] = Impl-Row 'procedure Handler1(const AMsg: string);'
$rows['A4_Handler2'] = Impl-Row 'procedure Handler2(const AMsg: string);'
$rows['FreeShared']  = Impl-Row 'function Shared(const AKey: string): Boolean;'
$rows['A5_Method']   = Impl-Row 'function TThing.Shared(const AKey: string; const AExtra: Integer): Boolean;'
$rows['Register1']   = Impl-Row 'procedure Register1(P: TFilterPred);'
$rows['Register2']   = Impl-Row 'procedure Register2(H: THandlerProc);'
$rows['Driver']      = Impl-Row 'procedure Driver;'

foreach ($k in $rows.Keys) {
  if (-not $rows[$k]) { Write-Host "FATAL: anchor not found: $k" -ForegroundColor Red; exit 2 }
}
if (@($rows.Values | Sort-Object -Unique).Count -ne $rows.Count) {
  Write-Host "FATAL: anchors collapsed: $($rows.Values -join ',')" -ForegroundColor Red; exit 2
}
Write-Host ("  anchors: " + (($rows.Keys | ForEach-Object { "$_=$($rows[$_])" }) -join ' ')) -ForegroundColor DarkGray

$out = & $Exe lint $file 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'uUnusedParamAddr\.pas:(\d+):\d+\s+\[\w+\]\s+unused-parameter: Parameter "(\w+)"') |
          ForEach-Object { [pscustomobject]@{ Row = [int]$_.Groups[1].Value; Param = $_.Groups[2].Value } })
function Proc-Of([int]$Row) {
  $best = '(none)'
  foreach ($n in $rows.Keys) { if ($Row -ge $rows[$n]) { $best = $n } }
  $best
}
function Params-In([string]$P) {
  @($hits | Where-Object { (Proc-Of $_.Row) -eq $P } | ForEach-Object { $_.Param }) -join ','
}
Write-Host ("  findings: " + (@($hits | ForEach-Object { "$(Proc-Of $_.Row):$($_.Param)" }) -join '  ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'CONTROL: an ordinary routine with an unused parameter still fires' -ForegroundColor Cyan
Check 'A1: Plain(A, B) reports exactly B' ((Params-In 'A1_Plain') -eq 'B') "got=[$(Params-In 'A1_Plain')]"
if ((Params-In 'A1_Plain') -ne 'B') {
  Write-Host '  !! The control failed, so every silence below proves nothing --' -ForegroundColor Yellow
  Write-Host '  !! they would all pass with the rule disabled.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'A routine handed to somebody does not own its signature' -ForegroundColor Cyan
Check 'A2: passed by bare name'                  ((Params-In 'A2_Pred1')    -eq '') "got=[$(Params-In 'A2_Pred1')]"
Check 'A3: registered via @Handler1'             ((Params-In 'A3_Handler1') -eq '') "got=[$(Params-In 'A3_Handler1')]"
Check 'A4: registered only in an inactive IFDEF' ((Params-In 'A4_Handler2') -eq '') "got=[$(Params-In 'A4_Handler2')]"

Write-Host ''
Write-Host 'ACCEPTED IMPRECISION: bare-name collision (documented, not a claim)' -ForegroundColor Cyan
Check 'A5: method sharing a name with an addr-taken free routine' ((Params-In 'A5_Method') -eq '') "got=[$(Params-In 'A5_Method')]"

Write-Host ''
Write-Host 'Nothing else in the fixture may fire' -ForegroundColor Cyan
Check 'free Shared uses its parameter' ((Params-In 'FreeShared') -eq '') "got=[$(Params-In 'FreeShared')]"
Check 'Register1 uses P'               ((Params-In 'Register1')  -eq '') "got=[$(Params-In 'Register1')]"
Check 'Register2 uses H'               ((Params-In 'Register2')  -eq '') "got=[$(Params-In 'Register2')]"
Check 'Driver has no parameters'       ((Params-In 'Driver')     -eq '') "got=[$(Params-In 'Driver')]"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
