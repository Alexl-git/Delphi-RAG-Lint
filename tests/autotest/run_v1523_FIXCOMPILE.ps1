<#
  run_v1523_FIXCOMPILE.ps1 -- `lint --fix --apply` must never emit code that does not compile
  (docs\INBOX-fixer-noncompiling-ifthen-nonminimal.md; found by lane SLZ-S10 / SLZ-S11 on DL itself).

  Fixtures are the EXACT failing statements, wrapped in just enough declarations to compile:
    A. ifthen-to-if-expression in a generic routine over interface method calls (Analysis.DataFlow:
       `Acc := if .. then AAnalysis.Boundary else AAnalysis.Bottom` -> E2010 'procedure, untyped pointer')
    B. ifthen-to-if-expression with an array-concatenation arm (Charts.Q.EventWiring:271 E2010,
       Charts.Q.FeedsFrom:654 / Charts.Q.LandsWhere:726 internal error F2084)
    C. nonminimal-bool on TTSNode operands (a record whose helper declares Equal and no NotEqual:
       Analysis.Cfg 505/1186, Refactor.Rename 1186, Refactor.NamingFix 678, Refactor.ExtractMethod
       681/743/987/1169/1646 -> E2015)
    D. nonminimal-bool never leaves `((A <> B))` -- one grouping pair.
  For each: the fixed file must COMPILE (dcc32), the unsafe statements must be left as written
  (the fixer declined), and positive controls in the same file must still be rewritten (so the
  pass is not vacuous: a fixer switched off would fail the controls).

  -Exe defaults to the worktree build; pass the 1.52.2 engine to see RED.
#>
param(
  [string]$Exe = ''
)
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Exe) { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FAIL: engine not found: $Exe"; exit 2 }
$Dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc32.exe'
if (-not (Test-Path -LiteralPath $Dcc)) { Write-Host "SKIP: dcc32 not found: $Dcc"; exit 0 }
$Work = Join-Path ([IO.Path]::GetTempPath()) ('fixcompile-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
$Enc = [Text.Encoding]::GetEncoding(1252)
$script:Pass = 0; $script:Fail = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "PASS  $Name" }
  else { $script:Fail++; Write-Host "FAIL  $Name  $Detail" }
}
function Put([string]$Name, [string]$Text) {
  $p = Join-Path $Work $Name
  [IO.File]::WriteAllText($p, ($Text -replace "`r?`n", "`r`n"), $Enc)
  return $p
}
function Get-Text([string]$Path) { return [IO.File]::ReadAllText($Path, $Enc) }
function Fix([string]$Path, [string]$Rule) {
  $a = @('lint', '--in', $Path, '--fix', '--apply', '--no-backup', '--no-compile-gate', '--enable', $Rule, '--rule', $Rule)
  return (& { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } } | Out-String)
}
# compile the unit through a one-line program; returns the dcc error lines ('' = compiled)
function Compile([string]$UnitPath) {
  $u = [IO.Path]::GetFileNameWithoutExtension($UnitPath)
  $dpr = Put "P_$u.dpr" "program P_$u;`n{`$APPTYPE CONSOLE}`nuses $u in '$u.pas';`nbegin end.`n"
  $out = & { $ErrorActionPreference = 'Continue'; & $Dcc -Q -B $dpr "-E$Work" "-N$Work" 2>&1 | ForEach-Object { "$_" } }
  return (($out | Where-Object { $_ -match '(Error|Fatal)' }) -join ' | ')
}
function Has([string]$Text, [string]$Literal) { return $Text.Contains($Literal) }

try {
  # ---- A. generic routine, interface method-call arms ------------------------------
  $a = @'
unit FxGeneric;

interface

uses System.Generics.Collections;

type
  IDataFlowAnalysis<TValue> = interface
    function Bottom: TValue;
    function Boundary: TValue;
    function Join(const A, B: TValue): TValue;
  end;

  TCfg = class
    EntryIdx: Integer;
    ExitIdx: Integer;
  end;

  TDataFlowSolver<TValue> = class
    class function Solve(const ACfg: TCfg; const AAnalysis: IDataFlowAnalysis<TValue>;
      out AIn, AOut: TArray<TValue>): Boolean;
  end;

implementation

class function TDataFlowSolver<TValue>.Solve(const ACfg: TCfg;
  const AAnalysis: IDataFlowAnalysis<TValue>; out AIn, AOut: TArray<TValue>): Boolean;
var
  Fwd: Boolean;
  B, P, Boundary: Integer;
  Acc: TValue;
begin
  SetLength(AIn, 2); SetLength(AOut, 2);
  Fwd := ACfg.EntryIdx = 0;
  if Fwd then Boundary := ACfg.EntryIdx else Boundary := ACfg.ExitIdx;
  B := 0; P := 1;
  if B = Boundary then Acc := AAnalysis.Boundary
  else Acc := AAnalysis.Bottom;
  if Fwd then Acc := AAnalysis.Join(Acc, AOut[P])
  else Acc := AAnalysis.Join(Acc, AIn[P]);
  AOut[B] := Acc;
  Result := True;
end;

end.
'@
  $pa = Put 'FxGeneric.pas' $a
  Check 'A: the fixture compiles before the fix' ((Compile $pa) -eq '')
  Fix $pa 'ifthen-to-if-expression' | Out-Null
  $ta = Get-Text $pa
  $err = Compile $pa
  Check 'A: the fixed generic unit compiles' ($err -eq '') $err
  Check 'A: the generic-typed method-call arms are left as written' ((Has $ta 'if B = Boundary then Acc := AAnalysis.Boundary') -and (Has $ta 'if Fwd then Acc := AAnalysis.Join(Acc, AOut[P])')) $ta
  Check 'A control: the Integer target in the same generic routine is still rewritten' (Has $ta 'Boundary := if Fwd then ACfg.EntryIdx else ACfg.ExitIdx;') $ta

  # ---- B. array-concatenation arms (E2010 and internal error F2084) -----------------
  $b = @'
unit FxArrays;

interface

type
  TDotRow = record
    Text: string;
    class function Anchored(const AComp: string; ALine: Integer; const AHref, ALabel: string): TDotRow; static;
    class function Plain(const ALabel: string): TDotRow; static;
  end;

  THop = record
    Line: Integer;
    Path, Caption, Reason: string;
  end;

function NewRow(const ALabel, APath: string; ALine: Integer; const ATip, AReason: string): TDotRow;
function Draw(ADfmExact, AHasField: Boolean; const AHops: TArray<THop>): Integer;

implementation

uses System.SysUtils;

class function TDotRow.Anchored(const AComp: string; ALine: Integer; const AHref, ALabel: string): TDotRow;
begin
  Result.Text := AComp + AHref + ALabel + IntToStr(ALine);
end;

class function TDotRow.Plain(const ALabel: string): TDotRow;
begin
  Result.Text := ALabel;
end;

function NewRow(const ALabel, APath: string; ALine: Integer; const ATip, AReason: string): TDotRow;
begin
  Result.Text := ALabel + APath + ATip + AReason + IntToStr(ALine);
end;

function Draw(ADfmExact, AHasField: Boolean; const AHops: TArray<THop>): Integer;
var
  Cells, Rows, FSelRows: TArray<TDotRow>;
  N: Integer;
begin
  Cells := []; Rows := []; FSelRows := [];
  if ADfmExact then
    Cells:= Cells + [TDotRow.Anchored('C', 1, 'h',
      Format('%s  --  %s:%d', ['a', 'b', 1]))]
  else
    Cells:= Cells + [TDotRow.Plain('x')];
  if AHasField then
    Rows:= Rows + [NewRow('F' + ' : ' + 'T', 'd', 2,
      Format('%s.%s = ''%s'' -- %s:%d', ['q', 'p', 'c', 'd', 2]), 'p' + ' = ' + 'c')]
  else
    Rows:= Rows + [NewRow('F', 'd', 0, '', '')];
  for var H in AHops do
  begin
    if (H.Line > 0) and (H.Path <> '') then
      FSelRows:= FSelRows + [NewRow('L', H.Path, H.Line, H.Caption + ' -- ' + H.Path, H.Reason)]
    else
      FSelRows:= FSelRows + [NewRow('L', '', 0, H.Caption, H.Reason)];
  end;
  if ADfmExact then N := 1 else N := 2;
  Result := Length(Cells) + Length(Rows) + Length(FSelRows) + N;
end;

end.
'@
  $pb = Put 'FxArrays.pas' $b
  Check 'B: the fixture compiles before the fix' ((Compile $pb) -eq '')
  Fix $pb 'ifthen-to-if-expression' | Out-Null
  $tb = Get-Text $pb
  $err = Compile $pb
  Check 'B: the fixed array unit compiles (no E2010, no F2084)' ($err -eq '') $err
  Check 'B: no array-concatenation arm became an if-expression' (-not ($tb -match ':=\s*if\s[^;]*\+\s*\[')) $tb
  Check 'B control: the Integer assignment in the same routine is still rewritten' (Has $tb 'N := if ADfmExact then 1 else 2;') $tb

  # ---- C + D. nonminimal-bool on TTSNode (Equal declared, NotEqual not) -------------
  $c = @'
unit FxNodes;

interface

type
  TSNode = record
    Id: Integer;
  end;
  TTSNode = TSNode;
  TTSNodeHelper = record helper for TTSNode
    function NamedChild(AIndex: Integer): TTSNode;
    function ChildByField(const AName: string): TTSNode;
    function NodeType: string;
    function NamedChildCount: Integer;
    class operator Equal(A: TTSNode; B: TTSNode): Boolean;
  end;
  TSel = record
    Proc: TTSNode;
  end;
  TKind = (kA, kB);

function Probe(N, ARoutine, StartN, OwnerProc, TargetList, TargetListTo: TTSNode; const ASel: TSel;
  I: Integer; K: TKind): Integer;

implementation

function TTSNodeHelper.NamedChild(AIndex: Integer): TTSNode; begin Result.Id := Id + AIndex; end;
function TTSNodeHelper.ChildByField(const AName: string): TTSNode; begin Result.Id := Length(AName); end;
function TTSNodeHelper.NodeType: string; begin Result := 'defProc'; end;
function TTSNodeHelper.NamedChildCount: Integer; begin Result := Id; end;
class operator TTSNodeHelper.Equal(A: TTSNode; B: TTSNode): Boolean; begin Result := A.Id = B.Id; end;

function Probe(N, ARoutine, StartN, OwnerProc, TargetList, TargetListTo: TTSNode; const ASel: TSel;
  I: Integer; K: TKind): Integer;
var
  ANode: TTSNode;
begin
  Result := 0;
  ANode := N;
  if (N.NodeType = 'defProc') and (not (N = ARoutine)) then Exit;
  if (not (ANode.NamedChild(I) = StartN)) and (not (ANode.NamedChild(I) = ANode.ChildByField('body'))) then
    Inc(Result);
  if (not (N = OwnerProc)) and (N.NodeType = 'defProc') then Exit;
  if not (TargetList = TargetListTo) then Inc(Result);
  if not (N = ASel.Proc) then Exit;
  if (not (I = 0)) and (Result > 0) then Inc(Result);
  if not (K = kA) then Inc(Result);
end;

end.
'@
  $pc = Put 'FxNodes.pas' $c
  Check 'C: the fixture compiles before the fix' ((Compile $pc) -eq '')
  Fix $pc 'nonminimal-bool' | Out-Null
  $tc = Get-Text $pc
  $err = Compile $pc
  Check 'C: the fixed TTSNode unit compiles (no E2015)' ($err -eq '') $err
  Check 'C: every TTSNode comparison is left as written' ((Has $tc 'not (N = ARoutine)') -and (Has $tc 'not (ANode.NamedChild(I) = StartN)') -and
    (Has $tc "not (ANode.NamedChild(I) = ANode.ChildByField('body'))") -and (Has $tc 'not (N = OwnerProc)') -and
    (Has $tc 'not (TargetList = TargetListTo)') -and (Has $tc 'not (N = ASel.Proc)')) $tc
  Check 'C control: the Integer comparison is still rewritten' (Has $tc '(I <> 0) and (Result > 0)') $tc
  Check 'C control: the enum comparison is still rewritten' (Has $tc 'if (K <> kA) then') $tc
  Check 'D: no doubled grouping pair ((A <> B))' (-not ($tc -match '\(\(I <> 0\)\)')) $tc
}
finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
Write-Host ("run_v1523_FIXCOMPILE: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
