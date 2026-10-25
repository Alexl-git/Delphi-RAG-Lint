<#
  run_uba_class_local_deref_write.ps1 -- used-before-assignment on a member WRITE
  through an unassigned CLASS-typed local.

      var Obj: TFoo;
      begin
        Obj.K := 1;      // Obj is nil/garbage: this dereferences it
      end;

  WAS SILENT. The replay collected reads from an assignment's RHS only, and the
  definite-assignment lattice treats a partial write `x.f := ..` as assigning the
  base `x` (right for a RECORD: `R.K := 1` writes into R's own storage). For a
  CLASS local the lhs base is a pointer that is READ before the store.

  DECISION: the class-vs-record distinction needs a type, and the CST has none.
  The fix asks the symbol store (ResolveTypeCategory = tcClass) and does nothing
  when the store cannot classify the type (tcUnknown) -- no naming-convention
  fallback, because a `T` prefix names records and classes alike. So an
  unresolvable type stays SILENT (case U below pins that decision).

  Controls:
    positive  ClassRead     `N := ObjR.K` already fires (rhs read) -- proves the
                            rule is on and the harness parses findings.
    negative  RecordWrite   `R.K := 2` on a record local -- legal, silent.
    negative  AssignedFirst `ObjA := TFoo.Create; ObjA.K := 3` -- silent.
    negative  SelfAndField  `K := 4`, `Self.K := 5`, `FObj.K := 6` -- not locals.
    negative  UnknownType   `U.K := 7`, U's type not in any index -- silent.
    may-case  MaybeAssigned assigned on one branch only -> warning, not error.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-uba-class-deref-$PID"
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
function WritePas([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$projSrc = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory $projSrc | Out-Null

WritePas (Join-Path $projSrc 'UbaClassCases.pas') @"
unit UbaClassCases;

interface

type
  TFoo = class
  public
    K: Integer;
  end;

  TRec = record
    K: Integer;
  end;

  THolder = class
  public
    FObj: TFoo;
    K: Integer;
    procedure SelfAndField;
  end;

procedure ClassWrite;
procedure ClassRead;
procedure RecordWrite;
procedure AssignedFirst;
procedure UnknownType;
procedure MaybeAssigned(B: Boolean);

implementation

procedure ClassWrite;
var
  Obj: TFoo;
begin
  Obj.K := 1;
end;

procedure ClassRead;
var
  ObjR: TFoo;
  N: Integer;
begin
  N := ObjR.K;
  Writeln(N);
end;

procedure RecordWrite;
var
  R: TRec;
begin
  R.K := 2;
  Writeln(R.K);
end;

procedure AssignedFirst;
var
  ObjA: TFoo;
begin
  ObjA := TFoo.Create;
  ObjA.K := 3;
  ObjA.Free;
end;

procedure THolder.SelfAndField;
begin
  K := 4;
  Self.K := 5;
  FObj.K := 6;
end;

procedure UnknownType;
var
  U: TNotDeclaredAnywhere;
begin
  U.K := 7;
end;

procedure MaybeAssigned(B: Boolean);
var
  ObjM: TFoo;
begin
  if B then ObjM := TFoo.Create;
  ObjM.K := 8;
end;

end.
"@

$cases = Join-Path $projSrc 'UbaClassCases.pas'
$lines = [System.IO.File]::ReadAllLines($cases)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$ln = [ordered]@{
  write = LineOf 'Obj.K := 1;';     read  = LineOf 'N := ObjR.K;'
  rec   = LineOf 'R.K := 2;';       asg   = LineOf 'ObjA.K := 3;'
  fld   = LineOf 'K := 4;';         self  = LineOf 'Self.K := 5;'
  fobj  = LineOf 'FObj.K := 6;';    unk   = LineOf 'U.K := 7;'
  may   = LineOf 'ObjM.K := 8;'
}
Check 'all fixture statements located' (@($ln.Values) -notcontains -1) (($ln.Values) -join ',')

$projDb = Join-Path $WorkDir 'proj.sqlite'
& $Exe index $projSrc --db $projDb 2>&1 | Out-Null
Check 'index built' (Test-Path $projDb)

$json = (& $Exe lint-all --db $projDb --rule used-before-assignment --json 2>$null) -join "`n"
$arr  = @($json | ConvertFrom-Json)
$uba  = @{}
foreach ($f in $arr) {
  if ($f.rule -eq 'used-before-assignment') { $uba[[int]$f.start_line] = "$($f.severity)" }
}
Write-Host ("  findings: {0}" -f (($uba.Keys | Sort-Object | ForEach-Object { "$_=$($uba[$_])" }) -join ', ')) -ForegroundColor DarkGray

Check "positive control: rhs read N := ObjR.K fires (line $($ln.read))" ($uba.ContainsKey($ln.read))
Check "Obj.K := 1 on an unassigned class local fires as error (line $($ln.write))" ($uba[$ln.write] -eq 'error') "got '$($uba[$ln.write])'"
Check "ObjM.K := 8 assigned on one branch fires as warning (line $($ln.may))" ($uba[$ln.may] -eq 'warning') "got '$($uba[$ln.may])'"
Check "record local R.K := 2 is silent (line $($ln.rec))"        (-not $uba.ContainsKey($ln.rec))
Check "assigned-first ObjA.K := 3 is silent (line $($ln.asg))"   (-not $uba.ContainsKey($ln.asg))
Check "field K := 4 is silent (line $($ln.fld))"                 (-not $uba.ContainsKey($ln.fld))
Check "Self.K := 5 is silent (line $($ln.self))"                 (-not $uba.ContainsKey($ln.self))
Check "field FObj.K := 6 is silent (line $($ln.fobj))"           (-not $uba.ContainsKey($ln.fobj))
Check "unresolvable type U.K := 7 is silent -- decision (line $($ln.unk))" (-not $uba.ContainsKey($ln.unk))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
