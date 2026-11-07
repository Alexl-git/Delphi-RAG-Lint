<#
  run_flow_out_arg_rules.ps1 -- local-only-out-arg, dead-store-before-out-arg and
  by-value-arg-before-assignment (lane 146 t1; spec docs\superpowers\specs\2026-11-06-liveness-out-args-by-value.md).

  THE DEFECT. Liveness counts every call argument as a use, so `G.GetOut(X)` hides a write-only local
  and a dead store before it. The mode dispatch asks bare names only, so `G.Take(X)` hides a read of
  an unassigned local. All three rules are OFF: nothing here may move a default run.

  Local names are the case labels: t* must be reported by the rule the name starts with, c* never.
  Every negative control has a reported sibling, so a dead rule cannot pass this guard.

  Usage: pwsh -File tests\autotest\run_flow_out_arg_rules.ps1 [-Exe <drag-lint.exe>] [-RulesDir <dir>]
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_flow_out_args_$PID"
)
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }

$LO = 'local-only-out-arg'; $DS = 'dead-store-before-out-arg'; $BV = 'by-value-arg-before-assignment'
$NewRules = "$LO,$DS,$BV"

try {
  $exePath = (Resolve-Path $Exe).Path
  $rules   = (Resolve-Path $RulesDir).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  [void](New-Item -ItemType Directory -Path $src -Force)

  Write-Ascii (Join-Path $src 'uFaTypes.pas') @'
unit uFaTypes;
interface
type
  TBuf = array[0..7] of Byte;
  PInt = ^Integer;
  TPair = record
    A: Integer;
    B: Integer;
  end;
  IThing = interface
    procedure Hit;
  end;
  TGetter = class
  public
    procedure GetOut(out V: Integer);
    procedure GetVar(var V: Integer);
    function TryOut(out V: Integer): Boolean;
    procedure GetIntf(out V: IThing);
    procedure GetObj(out V: TObject);
    procedure Take(V: Integer);
    procedure TakeC(const V: Integer);
    procedure TakeStr(const V: string);
    procedure TakeP(P: PInt);
    procedure TakePtr(P: Pointer);
    procedure TakeBuf(const A: TBuf);
    procedure TakeUntyped(const B);
    procedure Two(out A: Integer; const B: Integer);
    procedure Differ(out A: Integer); overload;
    procedure Differ(const A: Word); overload;
  end;
  TKid = class(TGetter)
  end;
implementation
procedure TGetter.GetOut(out V: Integer); begin V := 1; end;
procedure TGetter.GetVar(var V: Integer); begin Inc(V); end;
function TGetter.TryOut(out V: Integer): Boolean; begin V := 1; Result := True; end;
procedure TGetter.GetIntf(out V: IThing); begin V := nil; end;
procedure TGetter.GetObj(out V: TObject); begin V := nil; end;
procedure TGetter.Take(V: Integer); begin end;
procedure TGetter.TakeC(const V: Integer); begin end;
procedure TGetter.TakeStr(const V: string); begin end;
procedure TGetter.TakeP(P: PInt); begin end;
procedure TGetter.TakePtr(P: Pointer); begin end;
procedure TGetter.TakeBuf(const A: TBuf); begin end;
procedure TGetter.TakeUntyped(const B); begin end;
procedure TGetter.Two(out A: Integer; const B: Integer); begin A := B; end;
procedure TGetter.Differ(out A: Integer); begin A := 1; end;
procedure TGetter.Differ(const A: Word); begin end;
end.
'@

  Write-Ascii (Join-Path $src 'uFaUse.pas') @'
unit uFaUse;
interface
uses uFaTypes;
procedure Use(const V: Integer);
procedure BareOut(out V: Integer);
procedure LoCases(G: TGetter; K: TKid; U: TNotIndexed; B: Boolean);
procedure DsCases(G: TGetter; U: TNotIndexed; B: Boolean);
procedure BvCases(G: TGetter; K: TKid; U: TNotIndexed; B: Boolean);
implementation
procedure Use(const V: Integer); begin end;
procedure BareOut(out V: Integer); begin V := 1; end;

procedure LoCases(G: TGetter; K: TKid; U: TNotIndexed; B: Boolean);
var
  tloMethod, tloKid, tloAgain, tloBare: Integer;
  cloVar, cloRead, cloUnknown, cloCond, cloCondIf, cloDiffer, cloBoth, cloCaptured: Integer;
  cloPair: TPair;
  cloWriteOnly: Integer;
  P: TProc;
begin
  G.GetOut(tloMethod);
  K.GetOut(tloKid);
  G.GetOut(tloAgain);
  G.GetOut(tloAgain);
  BareOut(tloBare);
  G.GetVar(cloVar);
  G.GetOut(cloRead);
  Use(cloRead);
  U.GetOut(cloUnknown);
  if B and G.TryOut(cloCond) then Use(1);
  Use(if B then G.TryOut(cloCondIf) else 0);
  G.Differ(cloDiffer);
  G.Two(cloBoth, cloBoth);
  G.GetOut(cloPair.A);
  G.GetOut(cloCaptured);
  P := procedure begin Use(cloCaptured); end;
  cloWriteOnly := 1;
end;

procedure DsCases(G: TGetter; U: TNotIndexed; B: Boolean);
var
  tdsMethod, tdsBare, tdsInline: Integer;
  cdsVar, cdsReadFirst, cdsCond, cdsBranch, cdsTry, cdsUnknown, tloNever, cdsOverwrite: Integer;
  cdsIntf: IThing;
  cdsObj: TObject;
begin
  tdsMethod := 1;
  G.GetOut(tdsMethod);
  Use(tdsMethod);
  tdsBare := 1;
  BareOut(tdsBare);
  Use(tdsBare);
  tdsInline := 1;
  if B then Use(2);
  G.GetOut(tdsInline);
  Use(tdsInline);

  cdsVar := 1;
  G.GetVar(cdsVar);
  Use(cdsVar);
  cdsReadFirst := 1;
  Use(cdsReadFirst);
  G.GetOut(cdsReadFirst);
  Use(cdsReadFirst);
  cdsCond := 1;
  if B and G.TryOut(cdsCond) then Use(3);
  Use(cdsCond);
  cdsBranch := 1;
  if B then G.GetOut(cdsBranch);
  Use(cdsBranch);
  cdsTry := 1;
  try
    G.GetOut(cdsTry);
  except
    Use(cdsTry);
  end;
  Use(cdsTry);
  cdsUnknown := 1;
  U.GetOut(cdsUnknown);
  Use(cdsUnknown);
  tloNever := 1;
  G.GetOut(tloNever);
  cdsIntf := nil;
  G.GetIntf(cdsIntf);
  cdsIntf.Hit;
  cdsObj := nil;
  try
    G.GetObj(cdsObj);
  finally
    cdsObj.Free;
  end;
  cdsOverwrite := 1;
  cdsOverwrite := 2;
  Use(cdsOverwrite);
end;

procedure BvCases(G: TGetter; K: TKid; U: TNotIndexed; B: Boolean);
var
  tbvDefinite, tbvConst, tbvKid, tbvMay, tbvOuter: Integer;
  cbvAssigned, cbvVar, cbvOut, cbvUnknown, cbvGuard, cbvP, cbvNp, cbvUntyped, cbvDiffer, cbvBoth: Integer;
  cbvStr: string;
  cbvBuf: TBuf;
  cbvPtr: PInt;
  cbvBare: Integer;
begin
  G.Take(tbvDefinite);
  G.TakeC(tbvConst);
  K.Take(tbvKid);
  if B then tbvMay := 1;
  G.Take(tbvMay);
  G.Take(tbvOuter);
  tbvOuter := 2;
  Use(tbvOuter);

  cbvAssigned := 1;
  G.Take(cbvAssigned);
  G.GetVar(cbvVar);
  G.GetOut(cbvOut);
  G.Take(cbvOut);
  U.Take(cbvUnknown);
  if B then cbvGuard := 1;
  if B then G.Take(cbvGuard);
  G.TakeStr(cbvStr);
  G.TakeBuf(cbvBuf);
  G.TakeP(cbvP);
  G.TakePtr(cbvPtr);
  G.TakeUntyped(cbvUntyped);
  G.Differ(cbvDiffer);
  G.Two(cbvBoth, cbvBoth);
  Use(cbvBare);
  with G do Take(cbvNp);
end;
end.
'@

  function Findings([string]$Json) {
    $i = $Json.IndexOf('['); if ($i -lt 0) { return ,@() }
    $a = @($Json.Substring($i) | ConvertFrom-Json)
    $o = @()
    foreach ($f in $a) {
      $m = [regex]::Match([string]$f.message, '"([^"]+)"')
      $o += [pscustomobject]@{ rule = [string]$f.rule; name = $m.Groups[1].Value; line = [int]$f.start_line; sev = [string]$f.severity; file = [string]$f.file_path }
    }
    return ,$o
  }
  function Names($F, [string]$Rule) { ,@($F | Where-Object { $_.rule -eq $Rule } | ForEach-Object { $_.name } | Sort-Object) }
  function Has($F, [string]$Rule, [string]$Name) { @($F | Where-Object { $_.rule -eq $Rule -and $_.name -eq $Name }).Count -gt 0 }

  $db = Join-Path $WorkDir 'fa.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $old = Join-Path $WorkDir 'fa-notable.sqlite'
  Copy-Item $db $old
  $py = Join-Path $WorkDir 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.commit()`nc.close()`n")
  & python $py $old

  Push-Location $WorkDir
  try {
    $use = Join-Path $src 'uFaUse.pas'
    $on   = Findings (& $exePath lint $use --db $db  --rules-dir $rules --enable $NewRules --json 2>$null | Out-String)
    $off  = Findings (& $exePath lint $use --db $old --rules-dir $rules --enable $NewRules --json 2>$null | Out-String)
    $dflt = Findings (& $exePath lint $use --db $db  --rules-dir $rules --json 2>$null | Out-String)
    $bare = Findings (& $exePath lint $use --rules-dir $rules --enable $NewRules --json 2>$null | Out-String)
    $allT = (& $exePath lint-all --db $db --rules-dir $rules --enable $NewRules --quiet 2>&1 | Out-String)
  }
  finally { Pop-Location }
  Write-Host ("  {0}: {1}" -f $LO, ((Names $on $LO) -join ','))
  Write-Host ("  {0}: {1}" -f $DS, ((Names $on $DS) -join ','))
  Write-Host ("  {0}: {1}" -f $BV, ((Names $on $BV) -join ','))
  Write-Host ("  no table: {0}" -f (@($off | Where-Object { $_.rule -in $LO, $DS, $BV } | ForEach-Object { $_.name }) -join ','))
  Write-Host ("  no index: {0}" -f (@($bare | Where-Object { $_.rule -in $LO, $DS, $BV } | ForEach-Object { $_.name }) -join ','))

  # Triggers.
  foreach ($n in 'tloMethod', 'tloKid', 'tloAgain', 'tloBare', 'tloNever') { Check "T $LO $n" (Has $on $LO $n) '' }
  foreach ($n in 'tdsMethod', 'tdsBare', 'tdsInline') { Check "T $DS $n" (Has $on $DS $n) '' }
  foreach ($n in 'tbvDefinite', 'tbvConst', 'tbvKid', 'tbvMay', 'tbvOuter') { Check "T $BV $n" (Has $on $BV $n) '' }

  # Each trigger once, at the place the rule promises.
  Check "T tloAgain is one finding, at the declaration" (@($on | Where-Object { $_.rule -eq $LO -and $_.name -eq 'tloAgain' }).Count -eq 1) ''
  $useLines = [IO.File]::ReadAllLines((Join-Path $src 'uFaUse.pas'))
  $tds = @($on | Where-Object { $_.rule -eq $DS -and $_.name -eq 'tdsMethod' })
  Check "T $DS reports the store's line" (($tds.Count -eq 1) -and ($useLines[$tds[0].line - 1] -match 'tdsMethod := 1')) ($tds | Out-String)
  $tbv = @($on | Where-Object { $_.rule -eq $BV -and $_.name -eq 'tbvDefinite' })
  Check "T $BV reports the call's line" (($tbv.Count -eq 1) -and ($useLines[$tbv[0].line - 1] -match 'G\.Take\(tbvDefinite\)')) ($tbv | Out-String)

  # Severity follows what the lattice knows.
  Check "T $BV definite is error"  (@($on | Where-Object { $_.rule -eq $BV -and $_.name -eq 'tbvDefinite' -and $_.sev -eq 'error' }).Count -eq 1) ''
  Check "T $BV possible is warning" (@($on | Where-Object { $_.rule -eq $BV -and $_.name -eq 'tbvMay' -and $_.sev -eq 'warning' }).Count -eq 1) ''

  # Controls: no c* anywhere under a new rule.
  foreach ($r in $LO, $DS, $BV) {
    $bad = @($on | Where-Object { $_.rule -eq $r -and $_.name -like 'c*' } | ForEach-Object { $_.name })
    Check "C $r reports no control" ($bad.Count -eq 0) ($bad -join ',')
  }
  # A positive control beside the negatives: the parents still fire, and the new ids do not take them over.
  Check 'C the parent write-only-local still fires'      (Has $on 'write-only-local' 'cloWriteOnly') ''
  Check 'C the parent overwrite-before-read still fires' (Has $on 'overwrite-before-read' 'cdsOverwrite') ''
  Check 'C the parent used-before-assignment still fires' (Has $on 'used-before-assignment' 'cbvBare') ''
  Check "C no line carries both overwrite-before-read and $DS" (-not (Has $on $DS 'cdsOverwrite')) ''
  Check "C $DS leaves a never-read local to $LO" (-not (Has $on $DS 'tloNever') -and (Has $on $LO 'tloNever')) ''

  # OFF means off, and the default run is what it was.
  foreach ($r in $LO, $DS, $BV) { Check "OFF $r silent without --enable" (@($dflt | Where-Object { $_.rule -eq $r }).Count -eq 0) '' }
  $same = (($on | Where-Object { $_.rule -notin $LO, $DS, $BV } | ForEach-Object { "$($_.rule):$($_.line):$($_.name)" }) -join '|') -eq (($dflt | ForEach-Object { "$($_.rule):$($_.line):$($_.name)" }) -join '|')
  Check 'OFF every other rule answers the same with the new ones enabled' $same ''

  # Degradation: a method's mode is F1; a bare same-unit signature is not.
  foreach ($n in 'tloMethod', 'tloKid') { Check "NOTABLE $n silent" (-not (Has $off $LO $n)) '' ; Check "NOINDEX $n silent" (-not (Has $bare $LO $n)) '' }
  Check 'NOTABLE tdsMethod silent' (-not (Has $off $DS 'tdsMethod')) ''
  Check 'NOTABLE tbvDefinite silent' (-not (Has $off $BV 'tbvDefinite')) ''
  Check 'NOINDEX tbvDefinite silent' (-not (Has $bare $BV 'tbvDefinite')) ''
  Check 'NOTABLE the bare out still reports' (Has $off $LO 'tloBare') ''
  Check 'NOINDEX the bare out still reports' (Has $bare $LO 'tloBare') ''
  Check 'NOINDEX the bare dead store still reports' (Has $bare $DS 'tdsBare') ''

  # lint-all reaches the rules too (a checker gate list short of an id answers 0).
  Check 'LINT-ALL reports all three' (($allT -match [regex]::Escape($LO)) -and ($allT -match [regex]::Escape($DS)) -and ($allT -match [regex]::Escape($BV))) ''
  # --rule narrows to the flow checker: LINT_GATE_FLOW has to name the ids.
  foreach ($r in $LO, $DS, $BV) {
    Push-Location $WorkDir
    try { $nr = Findings (& $exePath lint $use --db $db --rules-dir $rules --rule $r --json 2>$null | Out-String) } finally { Pop-Location }
    Check "RULE --rule $r answers" (@($nr | Where-Object { $_.rule -eq $r }).Count -gt 0) ''
  }
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:fail) { Write-Host 'run_flow_out_arg_rules: FAIL'; exit 1 }
Write-Host 'run_flow_out_arg_rules: PASS'; exit 0
