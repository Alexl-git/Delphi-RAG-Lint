<#
  run_uba_typed_method_modes.ps1 -- used-before-assignment on a METHOD call's argument, with the
  receiver's static type from index fact F1 (ref_types; lane 145 L-D, survey row 7).

  THE DEFECT. `Reader.Fill(Buf[0], 8)` with `procedure Fill(var B; N: Integer)` FILLS Buf, and was
  reported at error severity on that line. The parameter-mode oracle answers bare-name calls only;
  a method call got a closed list (Read / ReadBuffer, first argument).

  THE FIX. Receiver type -> the method's overload set over that type's ancestry -> var/out at this
  position in every applicable overload => the read is withdrawn. Anything else is today's logic.

  TRIGGERS (t*): every one of them is reported by the no-table and no-index runs, and by the old
  engine. CONTROLS (c*): reported in EVERY run, so the rule is proved on and no "unknown" silenced it.
  LIVENESS: write-only-local and overwrite-before-read do not take the oracle (Lattices calls with no
  ParamMode); their findings must be byte-equal with and without the table.

  Usage: pwsh -File tests\autotest\run_uba_typed_method_modes.ps1 [-Exe <drag-lint.exe>] [-RulesDir <dir>]
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_uba_typed_$PID"
)
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }

try {
  $exePath = (Resolve-Path $Exe).Path
  $rules   = (Resolve-Path $RulesDir).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  [void](New-Item -ItemType Directory -Path $src -Force)

  Write-Ascii (Join-Path $src 'uUtTypes.pas') @'
unit uUtTypes;
interface
type
  TBuf = array[0..7] of Byte;
  TPair = record
    A: Integer;
    B: Integer;
  end;
  PByte2 = ^Byte;
  THolderObj = class
  public
    FValue: Integer;
  end;
  TFwd = class;
  TFiller = class
  public
    procedure Arity3(const A: Byte; N, M: Integer); overload;
    procedure Arity3(var A: Byte; N: Integer); overload;
    procedure Dflt(var A: Byte); overload;
    procedure Dflt(const A: Word; N: Integer = 0); overload;
    procedure Fill(var B; N: Integer);
    procedure TakeOut(out V: Byte);
    procedure Peek(const B; N: Integer);
    procedure ByVal(V: Byte);
    procedure Both(var A: Byte; var B: Byte);
    procedure VarConst(var A: Byte; const B: Byte);
    procedure Agree(var A: Byte); overload;
    procedure Agree(out A: Byte; N: Integer); overload;
    procedure Differ(var A: Byte); overload;
    procedure Differ(const A: Word); overload;
    procedure Arity(const A: Byte); overload;
    procedure Arity(var A: Byte; N: Integer); overload;
    procedure Shadowed(var B; N: Integer);
    procedure HelperHides(var B; N: Integer);
    function Next: TFiller;
  end;
  TFwd = class
  public
    procedure FwdFill(var B; N: Integer);
  end;
  TKid = class(TFiller)
  end;
  THider = class(TFiller)
  public
    procedure Shadowed(const B; N: Integer); reintroduce;
  end;
  TFillerHelper = class helper for TFiller
  public
    procedure HelperHides(const B; N: Integer);
  end;
  IFiller = interface
    procedure IFill(var B; N: Integer);
  end;
  TRecv = record
    procedure RFill(var B; N: Integer);
  end;
  TFieldCall = class
  public
    Fire: procedure(var B) of object;
  end;
  THolder = class
  public
    FFiller: TFiller;
    function Get: TFiller;
  end;
implementation
procedure TFiller.Arity3(const A: Byte; N, M: Integer); begin end;
procedure TFiller.Arity3(var A: Byte; N: Integer); begin end;
procedure TFiller.Dflt(var A: Byte); begin end;
procedure TFiller.Dflt(const A: Word; N: Integer = 0); begin end;
procedure TFwd.FwdFill(var B; N: Integer); begin end;
procedure TFiller.Fill(var B; N: Integer); begin end;
procedure TFiller.TakeOut(out V: Byte); begin end;
procedure TFiller.Peek(const B; N: Integer); begin end;
procedure TFiller.ByVal(V: Byte); begin end;
procedure TFiller.Both(var A: Byte; var B: Byte); begin end;
procedure TFiller.VarConst(var A: Byte; const B: Byte); begin end;
procedure TFiller.Agree(var A: Byte); begin end;
procedure TFiller.Agree(out A: Byte; N: Integer); begin end;
procedure TFiller.Differ(var A: Byte); begin end;
procedure TFiller.Differ(const A: Word); begin end;
procedure TFiller.Arity(const A: Byte); begin end;
procedure TFiller.Arity(var A: Byte; N: Integer); begin end;
procedure TFiller.Shadowed(var B; N: Integer); begin end;
procedure TFiller.HelperHides(var B; N: Integer); begin end;
function TFiller.Next: TFiller; begin Result := Self; end;
procedure THider.Shadowed(const B; N: Integer); begin end;
procedure TFillerHelper.HelperHides(const B; N: Integer); begin end;
procedure TRecv.RFill(var B; N: Integer); begin end;
function THolder.Get: TFiller; begin Result := FFiller; end;
end.
'@

  # TDup is a homonym: two classes of that name, and their Fill AGREE. A homonym still answers unknown.
  foreach ($u in 'uUtDupA', 'uUtDupB') {
    Write-Ascii (Join-Path $src "$u.pas") (@'
unit {0};
interface
type
  TDup = class
  public
    procedure DupFill(var B; N: Integer);
  end;
implementation
procedure TDup.DupFill(var B; N: Integer); begin end;
end.
'@ -f $u)
  }

  Write-Ascii (Join-Path $src 'uUtUse.pas') @'
unit uUtUse;
interface
uses uUtTypes, uUtDupA;
procedure TDirect(R: TFiller);
procedure TOutParam(R: TFiller);
procedure TInherited(R: TKid);
procedure TDotted(H: THolder);
procedure TCallRecv(H: THolder);
procedure TOverloadAgree(R: TFiller);
procedure TOverloadArity(R: TFiller);
procedure TRecordField(R: TFiller);
procedure TNamedArray(R: TFiller);
procedure TTwoVarArgs(R: TFiller);
procedure TInterface(R: IFiller);
procedure TRecordRecv(var R: TRecv);
procedure TInIf(R: TFiller);
procedure TCaseFold(R: TFiller);
procedure TArityThree(R: TFiller);
procedure TForward(R: TFwd);
procedure CDefault(R: TFiller);
procedure CConst(R: TFiller);
procedure CByVal(R: TFiller);
procedure COverloadDiffer(R: TFiller);
procedure CHidden(R: THider);
procedure CHelper(R: TFiller);
procedure CHomonym(R: TDup);
procedure CNoSuchMethod(R: TFiller);
procedure CUnknownType(R: TNotIndexedAnywhere);
procedure CFieldCall(R: TFieldCall);
procedure COtherArg(R: TFiller);
procedure CSelfIndex(R: TFiller);
procedure CDeref(R: TFiller);
procedure CPointerIndex(R: TFiller);
procedure CClassField(R: TFiller);
procedure CNested(R: TFiller);
procedure CAlsoRead(R: TFiller);
procedure CBareRead;
procedure COverwrite(R: TFiller);
procedure CWriteOnly(R: TFiller);
implementation
procedure TDirect(R: TFiller);
var tdirect1: array[0..7] of Byte;
begin
  R.Fill(tdirect1[0], 8);
  Writeln(tdirect1[0]);
end;
procedure TOutParam(R: TFiller);
var toutparam1: array[0..7] of Byte;
begin
  R.TakeOut(toutparam1[0]);
  Writeln(toutparam1[0]);
end;
procedure TInherited(R: TKid);
var tinherited1: array[0..7] of Byte;
begin
  R.Fill(tinherited1[0], 8);
  Writeln(tinherited1[0]);
end;
procedure TDotted(H: THolder);
var tdotted1: array[0..7] of Byte;
begin
  H.FFiller.Fill(tdotted1[0], 8);
  Writeln(tdotted1[0]);
end;
procedure TCallRecv(H: THolder);
var tcallrecv1: array[0..7] of Byte;
begin
  H.Get.Fill(tcallrecv1[0], 8);
  Writeln(tcallrecv1[0]);
end;
procedure TOverloadAgree(R: TFiller);
var tagree1: array[0..7] of Byte;
begin
  R.Agree(tagree1[0]);
  Writeln(tagree1[0]);
end;
procedure TOverloadArity(R: TFiller);
var tarity1: array[0..7] of Byte;
begin
  R.Arity(tarity1[0], 8);
  Writeln(tarity1[0]);
end;
procedure TRecordField(R: TFiller);
var trecfield1: TPair;
begin
  R.Fill(trecfield1.A, 4);
  Writeln(trecfield1.A);
end;
procedure TNamedArray(R: TFiller);
var tnamedarr1: TBuf;
begin
  R.Fill(tnamedarr1[0], 8);
  Writeln(tnamedarr1[0]);
end;
procedure TTwoVarArgs(R: TFiller);
var ttwovar1: array[0..7] of Byte;
begin
  R.Both(ttwovar1[0], ttwovar1[1]);
  Writeln(ttwovar1[0]);
end;
procedure TInterface(R: IFiller);
var tintf1: array[0..7] of Byte;
begin
  R.IFill(tintf1[0], 8);
  Writeln(tintf1[0]);
end;
procedure TRecordRecv(var R: TRecv);
var trecrecv1: array[0..7] of Byte;
begin
  R.RFill(trecrecv1[0], 8);
  Writeln(trecrecv1[0]);
end;
procedure TInIf(R: TFiller);
var tinif1: array[0..7] of Byte;
begin
  if R.Next <> nil then R.Fill(tinif1[0], 8);
end;
procedure TCaseFold(R: TFiller);
var tcasefold1: array[0..7] of Byte;
begin
  r.fILL(tcasefold1[0], 8);
  Writeln(tcasefold1[0]);
end;
procedure TArityThree(R: TFiller);
var tarity3: array[0..7] of Byte;
begin
  R.Arity3(tarity3[0], 8);
  Writeln(tarity3[0]);
end;
procedure TForward(R: TFwd);
var tforward1: array[0..7] of Byte;
begin
  R.FwdFill(tforward1[0], 8);
  Writeln(tforward1[0]);
end;
procedure CDefault(R: TFiller);
var cdflt1: array[0..7] of Byte;
begin
  R.Dflt(cdflt1[0]);
end;
procedure CConst(R: TFiller);
var cconst1: array[0..7] of Byte;
begin
  R.Peek(cconst1[0], 8);
end;
procedure CByVal(R: TFiller);
var cbyval1: array[0..7] of Byte;
begin
  R.ByVal(cbyval1[0]);
end;
procedure COverloadDiffer(R: TFiller);
var cdiffer1: array[0..7] of Byte;
begin
  R.Differ(cdiffer1[0]);
end;
procedure CHidden(R: THider);
var chidden1: array[0..7] of Byte;
begin
  R.Shadowed(chidden1[0], 8);
end;
procedure CHelper(R: TFiller);
var chelper1: array[0..7] of Byte;
begin
  R.HelperHides(chelper1[0], 8);
end;
procedure CHomonym(R: TDup);
var chomonym1: array[0..7] of Byte;
begin
  R.DupFill(chomonym1[0], 8);
end;
procedure CNoSuchMethod(R: TFiller);
var cnosuch1: array[0..7] of Byte;
begin
  R.NoSuchThing(cnosuch1[0], 8);
end;
procedure CUnknownType(R: TNotIndexedAnywhere);
var cunknown1: array[0..7] of Byte;
begin
  R.Fill(cunknown1[0], 8);
end;
procedure CFieldCall(R: TFieldCall);
var cfieldcall1: array[0..7] of Byte;
begin
  R.Fire(cfieldcall1[0]);
end;
procedure COtherArg(R: TFiller);
var cother1: array[0..7] of Byte;
begin
  R.VarConst(cother1[0], cother1[1]);
end;
procedure CSelfIndex(R: TFiller);
var cselfidx1: array[0..7] of Byte;
begin
  R.Fill(cselfidx1[cselfidx1[1]], 8);
end;
procedure CDeref(R: TFiller);
var cderef1: PByte2;
begin
  R.Fill(cderef1^, 8);
end;
procedure CPointerIndex(R: TFiller);
var cptridx1: PByte2;
begin
  R.Fill(cptridx1[0], 8);
end;
procedure CClassField(R: TFiller);
var cclsfield1: THolderObj;
begin
  R.Fill(cclsfield1.FValue, 8);
end;
procedure CNested(R: TFiller);
var cnested1: array[0..1] of TPair;
begin
  R.Fill(cnested1[0].A, 8);
end;
procedure CAlsoRead(R: TFiller);
var calso1: array[0..7] of Byte;
begin
  R.Fill(calso1[0], calso1[1]);
end;
procedure CBareRead;
var cbare1: Integer;
begin
  Writeln(cbare1 + 1);
end;
procedure COverwrite(R: TFiller);
var cover1: Integer;
begin
  cover1 := 1;
  cover1 := 2;
  R.ByVal(cover1);
end;
procedure CWriteOnly(R: TFiller);
var cwrite1: Integer;
begin
  cwrite1 := 1;
end;
end.
'@

  $triggers = @('tdirect1', 'toutparam1', 'tinherited1', 'tdotted1', 'tcallrecv1', 'tagree1', 'tarity1', 'trecfield1',
                'tnamedarr1', 'ttwovar1', 'tintf1', 'trecrecv1', 'tinif1', 'tcasefold1', 'tarity3', 'tforward1')
  $controls = @('cconst1', 'cbyval1', 'cdiffer1', 'chidden1', 'chelper1', 'chomonym1', 'cnosuch1', 'cunknown1',
                'cfieldcall1', 'cother1', 'cselfidx1', 'cderef1', 'cptridx1', 'cclsfield1', 'cnested1', 'calso1', 'cbare1', 'cdflt1')

  function Reported([string]$Text) {
    ,@([regex]::Matches($Text, 'used-before-assignment: Local "(\w+)"') | ForEach-Object { $_.Groups[1].Value.ToLower() } | Sort-Object -Unique)
  }
  function Liveness([string]$Text) {
    ,@($Text -split "`r?`n" | Where-Object { $_ -match 'write-only-local|overwrite-before-read' } | ForEach-Object { $_.Trim() } | Sort-Object)
  }

  $db = Join-Path $WorkDir 'ut.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $old = Join-Path $WorkDir 'ut-notable.sqlite'
  Copy-Item $db $old
  $py = Join-Path $WorkDir 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.commit()`nc.close()`n")
  & python $py $old
  $gone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'SETUP the control DB really has no ref_types' ($gone -match '\b0 row') $gone
  $rows = ((& $exePath sql --db $db --query "SELECT count(*) AS n FROM ref_types" --json 2>&1 | Out-String) | ConvertFrom-Json).rows[0][0]
  Check 'SETUP the DB has ref_types rows' ([int]$rows -gt 0) $rows

  Push-Location $WorkDir
  try {
    $onText  = (& $exePath lint-all --db $db  --rules-dir $rules --quiet 2>&1 | Out-String)
    $offText = (& $exePath lint-all --db $old --rules-dir $rules --quiet 2>&1 | Out-String)
    # The no-index run: a bare file lint, with no --db and the DB dir not beside the source.
    $bareText = (& $exePath lint (Join-Path $src 'uUtUse.pas') --rules-dir $rules 2>&1 | Out-String)
  }
  finally { Pop-Location }
  $on = Reported $onText; $off = Reported $offText; $bare = Reported $bareText
  Write-Host ("  table   : {0}" -f ($on -join ','))
  Write-Host ("  notable : {0}" -f ($off -join ','))
  Write-Host ("  noindex : {0}" -f ($bare -join ','))

  foreach ($t in $triggers) {
    Check "T $t is NOT reported with the table (the fill line)" (-not ($on -contains $t)) ''
    Check "T $t IS reported with no ref_types table (today's logic)" ($off -contains $t) ''
  }
  foreach ($c in $controls) {
    Check "C $c is reported with the table" ($on -contains $c) ''
    Check "C $c is reported with no table" ($off -contains $c) ''
  }
  # NO INDEX: the store-free path keeps what it had; a trigger is not silenced by any new logic there.
  Check 'NOINDEX the rule is on (cbare1 reported)' ($bare -contains 'cbare1') ($bare -join ',')
  Check 'NOINDEX a trigger stays reported' (($bare -contains 'tdirect1') -and ($bare -contains 'tdotted1')) ($bare -join ',')
  # The oracle does not reach the liveness rules, and the fixture proves those rules ran.
  $lOn = Liveness $onText; $lOff = Liveness $offText
  Check 'LIVENESS overwrite-before-read and write-only-local fired' ((($lOn -join ' ') -match 'cover1') -and (($lOn -join ' ') -match 'cwrite1')) ($lOn -join ' | ')
  Check 'LIVENESS byte-equal with and without the table' (($lOn -join "`n") -eq ($lOff -join "`n")) ''
}
finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
