<#
  run_dotted_lhs_ref_kind.ps1 -- the ref shape of a dotted left-hand side `R.K := v`.

  QUESTION (docs\INBOX-local-var-read-refs-unbound.md, second point): the base `R`
  of `R.K := v` is emitted as kind 'read' although the statement stores through it.

  DECISION (EXT2, 2026-10-23): the base STAYS 'read'; the store is carried by the
  MEMBER row ('member-access', receiver_text = the base, member_accesses.mode =
  'write'). Reasons:
    * Consistent with `Self.X := v`, whose base `Self` is a 'read' and whose member
      carries the write (N-05).
    * The extractor has no types. For a CLASS receiver `Obj.K := v` reads Obj and
      does not modify it; 'write' would be wrong for the common case (and would make
      `Obj := TObj.Create; Obj.K := 1` look like a dead store to any refs consumer).
    * A new kind ('write-through') would drop these rows from every kind='read'
      consumer and from ResolveMemberReadRefs (90 field bases bound on the
      self-index) for no consumer that reads it yet.
    * The four flow / dead-code rules asked about are AST-based and answer
      correctly on every case below whatever refs.kind says -- asserted here.

  POSITIVE CONTROLS: plain `X := 1` is a 'write'; each of the four rules fires on
  its own control routine, so the "no finding on the dotted lines" checks cannot
  pass with a rule switched off.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dotted-lhs-$PID"
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
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory -Force $work | Out-Null
$body = @'
unit uDotLhs;

interface

type
  TInner = record
    K: Integer;
  end;
  TRec = record
    K: Integer;
    Inner: TInner;
  end;
  TObj = class
  private
    FNever: Integer;
    FSet: TRec;
  public
    K: Integer;
    function GetNever: Integer;
    function GetSet: Integer;
  end;

procedure UseR(const pR: TRec);
procedure UseO(pO: TObj);
procedure UseI(pI: Integer);
procedure RecLocal;
procedure ObjLocal;
procedure NestedLocal;
procedure Controls;

implementation

procedure UseR(const pR: TRec);
begin
  UseI(pR.K);
end;

procedure UseO(pO: TObj);
begin
  UseI(pO.K);
end;

procedure UseI(pI: Integer);
begin
  if pI > 0 then Exit;
end;

function TObj.GetNever: Integer;
begin
  Result := FNever;
end;

function TObj.GetSet: Integer;
begin
  FSet.K := 1;
  Result := FSet.K;
end;

procedure RecLocal;
var
  R: TRec;
begin
  R.K := 1;
  UseR(R);
end;

procedure ObjLocal;
var
  Obj: TObj;
begin
  Obj := TObj.Create;
  Obj.K := 1;
  UseO(Obj);
end;

procedure NestedLocal;
var
  R: TRec;
begin
  R.Inner.K := 1;
  UseR(R);
end;

procedure Controls;
var
  X, Y, Unused: Integer;
begin
  UseI(Y);
  X := 1;
  X := 2;
  UseI(X);
end;

end.
'@
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
$pas = Join-Path $work 'uDotLhs.pas'
[System.IO.File]::WriteAllText($pas, $norm, [System.Text.Encoding]::ASCII)
$lines = $norm -split "`r`n"
function LineOf([string]$Text) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Text) { return $i + 1 } }
  throw "fixture line not found: $Text"
}

$db = Join-Path $WorkDir 'dotted.sqlite'
$null = & $Exe index $work --db $db --library-db none 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Q([string]$Sql) {
  $raw = & $Exe sql --db $db --json --query $Sql 2>$null | Out-String
  $j = $raw | ConvertFrom-Json
  $names = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($j.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += [pscustomobject]$h
  }
  return ,$out
}
function FirstRef([int]$Line) {
  $rows = Q "select r.kind, r.name_text, coalesce(r.receiver_text,'<null>') rcv, coalesce(ma.mode,'<none>') mode from refs r left join member_accesses ma on ma.ref_id = r.id where r.start_line=$Line order by r.start_col"
  return ,$rows
}

Write-Host 'Positive control: plain assignment' -ForegroundColor Cyan
$r = FirstRef (LineOf 'Obj := TObj.Create;')
Check "control: 'Obj := ...' base is a write" ($r.Count -gt 0 -and $r[0].kind -eq 'write' -and $r[0].name_text -eq 'Obj') "got $($r[0].kind)/$($r[0].name_text)"

Write-Host 'Dotted left-hand sides: base read, member carries the store' -ForegroundColor Cyan
foreach ($case in @(
    @{ Line = 'R.K := 1;';      Base = 'R';    Member = 'K'; Mode = 'write' },
    @{ Line = 'Obj.K := 1;';    Base = 'Obj';  Member = 'K'; Mode = 'write' },
    @{ Line = 'FSet.K := 1;';   Base = 'FSet'; Member = 'K'; Mode = 'write' },
    @{ Line = 'R.Inner.K := 1;'; Base = 'R';   Member = 'Inner'; Mode = $null })) {
  $r = FirstRef (LineOf $case.Line)
  Check "$($case.Line) base '$($case.Base)' is a read" ($r.Count -ge 2 -and $r[0].kind -eq 'read' -and $r[0].name_text -eq $case.Base -and $r[0].rcv -eq '<null>') "got $($r[0].kind)/$($r[0].name_text)/$($r[0].rcv)"
  $m = $r | Where-Object { $_.kind -eq 'member-access' -and $_.name_text -eq $case.Member } | Select-Object -First 1
  Check "$($case.Line) member '$($case.Member)' is member-access, receiver '$($case.Base)'" ($m -and $m.rcv -eq $case.Base) "got $($m.kind)/$($m.rcv)"
  if ($case.Mode) { Check "$($case.Line) member access mode is '$($case.Mode)'" ($m -and $m.mode -eq $case.Mode) "got $($m.mode)" }
  Check "$($case.Line) emits no 'write' row" (@($r | Where-Object { $_.kind -eq 'write' }).Count -eq 0) ''
}
$r = FirstRef (LineOf 'R.Inner.K := 1;')
$leaf = $r | Where-Object { $_.kind -eq 'member-access' -and $_.name_text -eq 'K' } | Select-Object -First 1
Check "R.Inner.K := 1; leaf 'K' has receiver 'R.Inner'" ($leaf -and $leaf.rcv -eq 'R.Inner') "got $($leaf.rcv)"

Write-Host 'Lint answers on the same fixture' -ForegroundColor Cyan
$raw = & $Exe lint $pas --db $db --json --enable used-before-assignment,overwrite-before-read,referenced-never-set,unused-local 2>$null | Out-String
$f = @($raw | ConvertFrom-Json)
function Has([string]$Rule, [int]$Line) { @($f | Where-Object { $_.rule -eq $Rule -and $_.start_line -eq $Line }).Count -gt 0 }
Check 'control: used-before-assignment fires on UseI(Y)'         (Has 'used-before-assignment' (LineOf 'UseI(Y);')) ''
Check 'control: overwrite-before-read fires on the dead X := 1'   (Has 'overwrite-before-read' (LineOf 'X := 1;')) ''
Check 'control: unused-local fires on Unused'                    (Has 'unused-local' (LineOf 'X, Y, Unused: Integer;')) ''
Check 'control: referenced-never-set fires on FNever'            (Has 'referenced-never-set' (LineOf 'FNever: Integer;')) ''
$rules = 'used-before-assignment', 'overwrite-before-read', 'referenced-never-set', 'unused-local'
$quiet = @('R.K := 1;', 'UseR(R);', 'Obj := TObj.Create;', 'Obj.K := 1;', 'UseO(Obj);', 'R.Inner.K := 1;', 'FSet.K := 1;', 'FSet: TRec;', 'R: TRec;', 'Obj: TObj;')
foreach ($t in $quiet) {
  $ln = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $t) { $i + 1 } })
  $hit = @($f | Where-Object { $rules -contains $_.rule -and $ln -contains $_.start_line })
  Check "no flow/dead-code finding on '$t'" ($hit.Count -eq 0) (($hit | ForEach-Object { "$($_.rule)@$($_.start_line)" }) -join ',')
}

if ($script:Failed) { Write-Host 'run_dotted_lhs_ref_kind: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_dotted_lhs_ref_kind: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
