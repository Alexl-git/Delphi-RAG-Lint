<#
  run_rbb_class_arg_overload.ps1 -- same-arity overloads that differ only by a
  CLASS / CLASS-REFERENCE parameter type are told apart by the declared type of a
  plain-identifier argument (lane 151 RB-B, item 2).

  THE GAP (INT EX-AB, 2026-11-10)
  --------------------------------------------------------------------------------
  System.TypInfo declares two implementation-only overloads

      function FindPropInfo(AClass: TClass; const PropName: string): PPropInfo; overload;
      function FindPropInfo(Instance: TObject; const PropName: string): PPropInfo; overload;

  and calls them 35 times with a PARAMETER of exactly one of those types:
  `FindPropInfo(AClass, PropName)` / `FindPropInfo(Instance, PropName)`. After Y3
  separated the overloads, every site became an 'ambiguous' edge to the FIRST
  overload (TClass) and refs.symbol_id stayed NULL: the 1 bound-lost file of the
  EX-AB (System.TypInfo 2111 -> 2084). rb5-ovl's shape narrowing only models
  built-in families (Integer, Double, string, Char, Boolean); a TObject or TClass
  variable has no shape, so nothing narrowed.

  THE RULE: a plain-identifier argument whose declared type text is known and is
  NOT a built-in family decides between candidates whose parameter types DIFFER at
  that position: a candidate whose parameter type there is exactly the argument's
  type is kept, the others dropped -- an exact match is what the compiler picks.
  Narrowing only: no exact match, several exact matches, or an unknown argument
  type leaves the tie as it was. The controls pin that half.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rbb-class-arg-$PID"
)
try {
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
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# The TypInfo shape, implementation-only overloads as in the RTL; one Drive*
# routine per call site so each assertion names its site by the enclosing routine.
Write-Ascii (Join-Path $WorkDir 'rbbclassarg.pas') @'
unit rbbclassarg;

interface

uses Classes;

type
  TThing = class(TObject)
  end;

procedure DriveClass(AClass: TClass);
procedure DriveInstance(Instance: TObject);
procedure DriveInstanceExpr(Instance: TObject);
procedure DriveDerived(T: TThing);
procedure DriveComponent(C: TComponent);
procedure DriveBothExact(P: TPersistent);

implementation

function FindInfo(AClass: TClass; const PropName: string): Pointer; overload;
begin
  Result := nil;
end;

function FindInfo(Instance: TObject; const PropName: string): Pointer; overload;
begin
  Result := nil;
end;

procedure Show(const O: TObject; const N: Integer); overload;
begin
end;

procedure Show(const P: TPersistent; const N: Integer); overload;
begin
end;

procedure DriveClass(AClass: TClass);
begin
  FindInfo(AClass, 'Name');
end;

procedure DriveInstance(Instance: TObject);
begin
  FindInfo(Instance, 'Name');
end;

procedure DriveInstanceExpr(Instance: TObject);
begin
  FindInfo(Instance.ClassType, 'Name');
end;

procedure DriveDerived(T: TThing);
begin
  FindInfo(T, 'Name');
end;

procedure DriveComponent(C: TComponent);
begin
  Show(C, 1);
end;

procedure DriveBothExact(P: TPersistent);
begin
  Show(P, 1);
end;

end.
'@

$db = Join-Path $WorkDir 'rbbclassarg.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host "FATAL: index wrote no DB" -ForegroundColor Red; exit 2 }

$q = @"
SELECT enc.name AS from_name, r.name_text AS callee, ce.confidence AS conf, tgt.signature AS sig,
       (r.symbol_id = ce.target_symbol_id) AS ref_bound
FROM refs r
JOIN call_edges ce ON ce.ref_id = r.id
JOIN symbols enc ON enc.id = r.enclosing_symbol_id
JOIN symbols tgt ON tgt.id = ce.target_symbol_id
WHERE r.kind = 'call' AND r.name_text IN ('FindInfo', 'Show')
"@
$raw = & $Exe sql --db $db --json --query $q 2>$null
$doc = ($raw | Where-Object { $_ -notmatch '^\(loaded defaults' }) -join "`n" | ConvertFrom-Json
# sql --json rows are POSITIONAL arrays: map them onto the column names.
$cols = @($doc.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
$edges = @(foreach ($row in @($doc.rows)) {
  $o = [ordered]@{}
  for ($k = 0; $k -lt $cols.Count; $k++) { $o[$cols[$k]] = $row[$k] }
  [pscustomobject]$o
})
Check 'the probe returned edges (instrument check)' ($edges.Count -ge 6) "edges=$($edges.Count) cols=$($cols -join ',')"

function Site($from, $callee) {
  @($edges | Where-Object { $_.from_name -eq $from -and $_.callee -eq $callee }) | Select-Object -First 1
}
function SigOf($e) { if ($null -eq $e) { return '<no edge>' }; return $e.sig }
function CertainTo($from, $callee, $pattern, $label) {
  $e = Site $from $callee
  Check "$from binds $label, CERTAIN, ref bound" `
    ($null -ne $e -and $e.conf -eq 'certain' -and $e.sig -match $pattern -and "$($e.ref_bound)" -eq '1') `
    "conf=$($e.conf) ref_bound=$($e.ref_bound) sig=$(SigOf $e)"
}
function StaysAmbiguous($from, $callee, $why) {
  $e = Site $from $callee
  Check "$from stays ambiguous ($why)" ($null -ne $e -and $e.conf -eq 'ambiguous') "conf=$($e.conf) sig=$(SigOf $e)"
}

Write-Host 'Exact class / class-reference argument type decides the overload' -ForegroundColor Cyan
CertainTo 'DriveClass'    'FindInfo' 'AClass: TClass'    'FindInfo(TClass) for a TClass parameter'
CertainTo 'DriveInstance' 'FindInfo' 'Instance: TObject' 'FindInfo(TObject) for a TObject parameter'

Write-Host ''
Write-Host 'Controls -- what the declared type must NOT decide' -ForegroundColor Cyan
StaysAmbiguous 'DriveInstanceExpr' 'FindInfo' 'Instance.ClassType is an expression, not a plain identifier'
StaysAmbiguous 'DriveDerived'      'FindInfo' 'TThing matches neither parameter type exactly'
StaysAmbiguous 'DriveComponent'    'Show'     'TComponent matches neither TObject nor TPersistent exactly'
CertainTo 'DriveBothExact' 'Show' 'P: TPersistent' 'Show(TPersistent) for a TPersistent parameter (TObject also accepts it; exact wins)'
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
