<#
  run_cyclefix_cycq_dcc.ps1 -- lane cycq (1.44): three questions WEBSITE raised re-capturing the untangling article.

  Q1  A qualified R1 routine: `DUnit.Foo(2)` becomes `FooPtr(2)`. That is right, and it is what the wiki now says. But
      the rewrite replaced EVERY bare `Foo` on the line, whatever it bound to, so `Foo(1); DUnit.Foo(2);` with a local or
      a method `Foo` became `FooPtr(1); FooPtr(2);`: it compiled and called the wrong routine. Three more shapes gave a
      plan that compiled and did something else, or did not build: a local named like the unit (`DUnit.Foo` is a record
      method there), a parameter named like the routine, a consumer that already declares `FooPtr`.
      Now: name-shadowed / duplicate-identifier, up front. Shapes that are sound are proved by --apply + an independent
      msbuild + stdout byte-identical to the untouched build.
  Q2  `X is <interface>` does not compile (E2015, q2d); `X as <interface>` and `X is TAlias` do, and refuse when the declaration cannot move. The edge's line
      says other-ref; the cycle's verdict says coupling-remains when the other direction moves a class with bodies.
  Q3  A constant named only qualified in a subrange (`array[0..BUnit.cMax]`): the `..` hid it from the planner (a dot
      before the unit reads as a member chain), the plan removed the interface entry, the build failed with E2242 and
      the verdict was compile-error. Now the entry is kept and coupling-remains refuses up front, or, when the constant
      moves anyway, the text follows it.

  POSITIVE CONTROLS: pc1 (the stdout proof catches the unsound rewrite written by hand), pc2 (`R.DUnit.Foo`, a member
  chain, is still not a unit qualifier), pc3 (`0 .. BUnit.cMax`, spelled with spaces, was always seen and stays
  refused). RED on 1.43.0-alpha: q4/q5 same-line, q8, q9, q13, q3a, q3b, q3c.
  Needs RAD Studio; SKIPs (exit 0) without it. Works under %TEMP%.
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe") { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" } else { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-cycq-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailCount++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$Tmpl  = Join-Path $Repo 'tests\fixtures\cyclefix\qualparta\QualPartA.dproj'
$script:N = 0

function Write-Src([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii) }
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
# A project of the given units, indexed. $Spec: Units (name -> text), Order (dpr order), Main (the program's statement).
function New-Lab($Spec) {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  foreach ($k in $Spec.Units.Keys) { Write-Src (Join-Path $root "$k.pas") $Spec.Units[$k] }
  $u = ($Spec.Order | ForEach-Object { "  $_ in '$_.pas'" }) -join ",`n"
  Write-Src (Join-Path $root 'Lab.dpr') "program Lab;`n`n{`$APPTYPE CONSOLE}`n`nuses`n$u;`n`nbegin`n  $($Spec.Main)`nend.`n"
  $d = [IO.File]::ReadAllText($Tmpl, $Ascii).Replace('QualPartA', 'Lab')
  $refs = ($Spec.Order | ForEach-Object { "<DCCReference Include=`"$_.pas`"/>" }) -join "`r`n        "
  $d = [regex]::Replace($d, '<DCCReference Include="QpB.pas"/>\s*<DCCReference Include="QpA.pas"/>\s*<DCCReference Include="QpC.pas"/>', $refs)
  [IO.File]::WriteAllText((Join-Path $root 'Lab.dproj'), $d, $Ascii)
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'Lab.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'Lab.dproj'); Db = $db; Name = 'Lab' }
}
function Run-Fix($P, [string[]]$Extra) {
  $a = @('cycles', '--fix', '--build-timeout', '600', '--project', $P.Dproj, '--db', $P.Db, '--library-db', 'none', '--format', 'json') + $Extra
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @(); $r = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += $x.kind; $r += "$($x.kind): $($x.reason)" } } }
  foreach ($x in @($j.refusals)) { if ($x) { $k += $x.kind; $r += "$($x.kind): $($x.reason)" } }
  return @{ Exit = $code; Out = $out; Kinds = $k; Reasons = ($r -join ' || ') }
}
function Get-Plan($P) {
  Push-Location $WorkDir
  try { return ($null | & $Exe cycles --plan --project $P.Dproj --db $P.Db --library-db none 2>$null | Out-String) } finally { Pop-Location }
}
function Invoke-Build($P) {
  $bat = "$($P.Root).build.bat"; $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $P.Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $P.Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program($P) {
  $exeP = Join-Path $P.Root "Win64\Debug\$($P.Name).exe"
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [IO.File]::ReadAllText($o, $Ascii)
}
# Applies on one copy and proves it: exit 0, no refusal, builds, stdout byte-identical to an untouched copy.
function Prove-Apply([string]$Tag, $Spec) {
  $base = New-Lab $Spec
  $b0 = Invoke-Build $base
  $out0 = Invoke-Program $base
  $P = New-Lab $Spec
  $a = Run-Fix $P @('--apply')
  $b1 = Invoke-Build $P
  $out1 = Invoke-Program $P
  Check "$Tag --apply exit 0 no refusal; builds; stdout byte-identical" (
    $b0.Ok -and ($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0) -and $b1.Ok -and ($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) (
    "base=[$($b0.Errors)] exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons) build=[$($b1.Errors)] before=[$out0] after=[$out1]")
  return $P
}
# Legal Delphi (it builds untouched) and refused up front: the wanted kind, exit 1, no compile-error, not one byte written.
function Prove-Refused([string]$Tag, $Spec, [string]$Kind, [string]$Names) {
  $base = New-Lab $Spec
  $b0 = Invoke-Build $base
  $P = New-Lab $Spec
  $h0 = Get-SrcHash $P.Root
  $a = Run-Fix $P @('--apply')
  Check "$Tag is legal Delphi, refused $Kind up front, writes nothing" (
    $b0.Ok -and ($a.Exit -eq 1) -and ($a.Kinds -contains $Kind) -and ($a.Kinds -notcontains 'compile-error') -and
    ($a.Reasons -match $Names) -and ((Get-SrcHash $P.Root) -ceq $h0)) "base=[$($b0.Errors)] exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons)"
  return $P
}

# ---------------------------------------------------------------- the units
$DStd = @'
unit DUnit;

interface

const
  cMax = 5;

procedure Foo(pA: Integer);

implementation

uses
  CUnit;

procedure Foo(pA: Integer);
begin
  Writeln('D.Foo ', pA);
  TCCls.Create.Free;
end;

end.
'@
$DOver = @'
unit DUnit;

interface

procedure Foo(pA: Integer); overload;
procedure Foo(pA, pB: Integer); overload;

implementation

uses
  CUnit;

procedure Foo(pA: Integer);
begin
  Writeln('D.Foo1 ', pA);
  TCCls.Create.Free;
end;

procedure Foo(pA, pB: Integer);
begin
  Writeln('D.Foo2 ', pA, pB);
end;

end.
'@
$DTwo = $DStd.Replace('procedure Foo(pA: Integer);' + "`r`n`r`nimplementation", "procedure Foo(pA: Integer);`r`nprocedure Bar;`r`n`r`nimplementation").Replace('procedure Foo(pA: Integer);' + "`n`nimplementation", "procedure Foo(pA: Integer);`nprocedure Bar;`n`nimplementation").Replace('end.', "procedure Bar;`nbegin`n  Writeln('bar');`nend;`n`nend.")
$EUnitFoo = @'
unit EUnit;

interface

procedure Foo(pA: Integer);

implementation

procedure Foo(pA: Integer);
begin
  Writeln('E.Foo ', pA);
end;

end.
'@
$EUnitBase = @'
unit EUnit;

interface

type
  TEBase = class
  public
    procedure Foo(pA: Integer);
  end;

implementation

procedure TEBase.Foo(pA: Integer);
begin
  Writeln('inherited ', pA);
end;

end.
'@
function CU([string]$Member, [string]$Impl, [string]$ImplUses = 'DUnit', [string]$Ancestor = '', [string]$IntfUses = '') {
  $iu = if ($IntfUses) { "uses`n  $IntfUses;`n`n" } else { '' }
  $anc = if ($Ancestor) { "($Ancestor)" } else { '' }
  return "unit CUnit;`n`ninterface`n`n${iu}type`n  TCCls = class$anc`n  public`n    procedure Run;`n$Member`n  end;`n`nprocedure CRun;`n`nimplementation`n`nuses`n  $ImplUses;`n`n$Impl`n`nprocedure CRun;`nbegin`n  with TCCls.Create do`n  begin`n    Run;`n    Free;`n  end;`nend;`n`nend.`n"
}
function R1Spec([string]$C, [string]$D = $DStd, [string]$E = '') {
  $u = @{ CUnit = $C; DUnit = $D }
  $o = @('CUnit', 'DUnit')
  if ($E) { $u['EUnit'] = $E; $o += 'EUnit' }
  return @{ Units = $u; Order = $o; Main = 'CRun;' }
}
$Other = "procedure Other;`nbegin`n  Foo(3);`nend;`n`n"
$Nest  = "procedure TCCls.Run;`n  procedure Foo(pA: Integer);`n  begin`n    Writeln('local ', pA);`n  end;`nbegin`n  Other;`n"
$Meth  = "procedure TCCls.Foo(pA: Integer);`nbegin`n  Writeln('meth ', pA);`nend;`n`nprocedure TCCls.Run;`nbegin`n  Other;`n"
$FooM  = '    procedure Foo(pA: Integer);'

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== Q1 sound shapes: a qualified routine goes through the pointer' -ForegroundColor Cyan
  $P = Prove-Apply 'q1 bare + qualified' (R1Spec (CU '' "procedure TCCls.Run;`nbegin`n  Foo(1);`n  DUnit.Foo(2);`nend;"))
  $t = [IO.File]::ReadAllText((Join-Path $P.Root 'CUnit.pas'), $Ascii)
  Check 'q1 the qualified call reads FooPtr(2)' ($t.Contains('  FooPtr(2);') -and -not $t.Contains('DUnit.Foo')) $t
  $null = Prove-Apply 'q1b a lower-case qualifier' (R1Spec (CU '' "procedure TCCls.Run;`nbegin`n  Foo(1);`n  dunit.foo(2);`nend;"))
  $null = Prove-Apply 'q1c qualified, as an assignment value' (R1Spec (CU '' "type`n  TP = procedure(pA: Integer);`n`nprocedure TCCls.Run;`nvar`n  P: TP;`nbegin`n  P := Foo;`n  P(1);`n  P := DUnit.Foo;`n  P(2);`nend;"))
  $null = Prove-Apply 'q3a overloads: the qualified call has the bound overload''s count' (R1Spec (CU '' "procedure TCCls.Run;`nbegin`n  Foo(1);`n  DUnit.Foo(2);`nend;") $DOver)

  Write-Host '== Q1 a same-named routine on ANOTHER line stays what it was' -ForegroundColor Cyan
  $Sep = R1Spec (CU '' ($Other + $Nest + "  Foo(1);`n  DUnit.Foo(2);`nend;"))
  $P = Prove-Apply 'q4a a nested routine Foo' $Sep
  $t = [IO.File]::ReadAllText((Join-Path $P.Root 'CUnit.pas'), $Ascii)
  Check 'q4a the local call still reads Foo(1)' ($t.Contains('  Foo(1);') -and $t.Contains('  FooPtr(2);')) $t
  # pc1: the stdout proof has teeth: the same unit with the unsound rewrite written by hand builds and prints something else
  $bad = New-Lab $Sep
  $b = Invoke-Build $bad
  $good = Invoke-Program $bad
  $src = Join-Path $bad.Root 'CUnit.pas'
  Write-Src $src ([IO.File]::ReadAllText($src, $Ascii).Replace("  Foo(1);`r`n  DUnit.Foo(2);", "  DUnit.Foo(1);`r`n  DUnit.Foo(2);"))
  $b2 = Invoke-Build $bad
  $worse = Invoke-Program $bad
  Check 'pc1 the wrong binding builds and its stdout differs: the proof can fail' ($b.Ok -and $b2.Ok -and ($good -cne $worse)) "good=[$good] worse=[$worse]"
  $null = Prove-Apply 'q5a a method Foo' (R1Spec (CU $FooM ($Other + $Meth + "  Foo(1);`n  DUnit.Foo(2);`nend;")))
  $null = Prove-Apply 'q5b an inherited method Foo, bare, in another unit' (R1Spec (CU '' ($Other + "procedure TCCls.Run;`nbegin`n  Other;`n  Foo(1);`nend;") 'DUnit' 'TEBase' 'EUnit') $DStd $EUnitBase)
  $null = Prove-Apply 'q5c a with body whose receiver has Foo' (R1Spec (CU '' "procedure TCCls.Run;`nvar`n  B: TEBase;`nbegin`n  B := TEBase.Create;`n  Foo(3);`n  with B do Foo(1);`n  with B do DUnit.Foo(2);`n  B.Free;`nend;" 'DUnit, EUnit') $DStd $EUnitBase)
  $null = Prove-Apply 'q10a another unit declares Foo, listed first' (R1Spec (CU '' "procedure TCCls.Run;`nbegin`n  Foo(1);`n  DUnit.Foo(2);`nend;" 'EUnit, DUnit') $DStd $EUnitFoo)
  # q10b: bare Foo is EUnit's, so no routine of DUnit is on the edge and the class moves with its bodies. That plan fails
  # the compile gate today (the body's DUnit.Foo, EUnit in both uses of the leaf): safe, never a changed program.
  $Q10b = R1Spec (CU '' "procedure TCCls.Run;`nbegin`n  Foo(1);`n  DUnit.Foo(2);`nend;" 'DUnit, EUnit') $DStd $EUnitFoo
  $P = New-Lab $Q10b
  $h0 = Get-SrcHash $P.Root
  $a = Run-Fix $P @('--apply')
  Check 'q10b another unit declares Foo, listed last: the gate refuses, nothing written' (($a.Exit -eq 1) -and ((Get-SrcHash $P.Root) -ceq $h0)) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons)"
  # lane 148 CY: the PLANNER refuses it (coupling-remains, the moved body names DUnit qualified), no build needed
  $a = Run-Fix $P @('--no-compile')
  Check 'q10c the dry run already refuses coupling-remains naming DUnit.Foo' (($a.Exit -eq 1) -and ($a.Kinds -contains 'coupling-remains') -and ($a.Reasons -match 'DUnit\.Foo')) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons)"
  $null = Prove-Apply 'pc2 R.DUnit.Foo is a member chain, no qualifier' (R1Spec (CU '' "type`n  TIn = record`n    procedure Foo(pA: Integer);`n  end;`n  TOut = record`n    DUnit: TIn;`n  end;`n`nprocedure TIn.Foo(pA: Integer);`nbegin`n  Writeln('rec ', pA);`nend;`n`nprocedure TCCls.Run;`nvar`n  R: TOut;`nbegin`n  Foo(1);`n  R.DUnit.Foo(2);`nend;"))

  Write-Host '== Q1 unsound or impossible shapes refuse' -ForegroundColor Cyan
  $null = Prove-Refused 'q4b a nested routine Foo on the qualified call''s line' (R1Spec (CU '' ($Other + $Nest + "  Foo(1); DUnit.Foo(2);`nend;"))) 'name-shadowed' 'name-shadowed.*line \d+'
  $null = Prove-Refused 'q5d a method Foo on the qualified call''s line' (R1Spec (CU $FooM ($Other + $Meth + "  Foo(1); DUnit.Foo(2);`nend;"))) 'name-shadowed' 'name-shadowed.*line \d+'
  $null = Prove-Refused 'q13 a parameter named Foo' (R1Spec (CU '' "procedure Other(Foo: Integer);`nbegin`n  DUnit.Foo(Foo);`nend;`n`nprocedure TCCls.Run;`nbegin`n  Foo(1);`n  Other(5);`nend;")) 'name-shadowed' 'name-shadowed.*line \d+'
  $null = Prove-Refused 'q9 a local variable named like the unit' (R1Spec (CU '' "type`n  TRec = record`n    procedure Foo(pA: Integer);`n  end;`n`nprocedure TRec.Foo(pA: Integer);`nbegin`n  Writeln('rec ', pA);`nend;`n`nprocedure TCCls.Run;`nvar`n  DUnit: TRec;`nbegin`n  Foo(1);`n  DUnit.Foo(2);`nend;")) 'name-shadowed' 'name-shadowed.*DUnit'
  $null = Prove-Refused 'q8a the consumer declares FooPtr: it would win over the pointer' (R1Spec (CU '' "procedure FooPtr(pA: Integer);`nbegin`n  Writeln('own ptr ', pA);`nend;`n`nprocedure TCCls.Run;`nbegin`n  Foo(1);`n  FooPtr(9);`nend;")) 'duplicate-identifier' 'duplicate-identifier.*FooPtr'
  $null = Prove-Refused 'q8b the class has a method FooPtr' (R1Spec (CU '    procedure FooPtr(pA: Integer);' "procedure TCCls.FooPtr(pA: Integer);`nbegin`n  Writeln('meth ptr ', pA);`nend;`n`nprocedure TCCls.Run;`nbegin`n  Foo(1);`nend;")) 'duplicate-identifier' 'duplicate-identifier.*FooPtr'
  $null = Prove-Refused 'q3b overloads: the qualified call is the OTHER overload' (R1Spec (CU '' "procedure TCCls.Run;`nbegin`n  Foo(1);`n  DUnit.Foo(1, 2);`nend;") $DOver) 'overloaded-routine' 'Foo'
  $null = Prove-Refused 'q6 the consumer''s own Foo: only the qualified call needs the unit' (R1Spec (CU '' "procedure Foo(pA: Integer);`nbegin`n  Writeln('own ', pA);`nend;`n`nprocedure TCCls.Run;`nbegin`n  Foo(1);`n  DUnit.Foo(2);`nend;")) 'edge-still-used' 'still uses'
  $null = Prove-Refused 'q11 a second routine qualified' (R1Spec (CU '' "procedure TCCls.Run;`nbegin`n  Foo(1);`n  Bar;`n  DUnit.Bar;`nend;") $DTwo) 'qualified-ref' 'Bar'

  Write-Host '== Q2 is <interface> / is <alias> compile, and refuse when the declaration cannot move' -ForegroundColor Cyan
  $UiAOf = { param($Sender, $Test) "unit UiA;`n`ninterface`n`nuses`n  System.Classes;`n`ntype`n  TUiA = class(TComponent)`n  public`n    function Check(Sender: $Sender): Boolean;`n  end;`n`nimplementation`n`nuses`n  UiB;`n`nfunction TUiA.Check(Sender: $Sender): Boolean;`nbegin`n  Result := $Test;`nend;`n`nend.`n" }
  $Make = "procedure TPOne.Make;`nvar`n  A: TUiA;`nbegin`n  A := TUiA.Create(nil);`n  Writeln(A.Check(Self));`n  A.Free;`nend;"
  $UiBIntf = "unit UiB;`n`ninterface`n`nuses`n  System.Classes;`n`ntype`n  TPOne = class;`n`n  IFoo = interface`n    ['{8B7C3A10-1D2E-4F50-9A61-0123456789AB}']`n    function Me: TPOne;`n  end;`n`n  TPOne = class(TInterfacedObject, IFoo)`n  public`n    procedure Make;`n    function Me: TPOne;`n  end;`n`nprocedure BRun;`n`nimplementation`n`nuses`n  UiA;`n`nfunction TPOne.Me: TPOne;`nbegin`n  Result := Self;`nend;`n`n$Make`n`nprocedure BRun;`nbegin`n  TPOne.Create.Make;`nend;`n`nend.`n"
  $UiBMov  = $UiBIntf.Replace('function Me: TPOne;', 'function Val: Integer;').Replace("function TPOne.Val: Integer;`nbegin`n  Result := Self;", "function TPOne.Val: Integer;`nbegin`n  Result := 1;").Replace('  TPOne = class;' + "`n`n", '').Replace('function TPOne.Me: TPOne;', 'function TPOne.Val: Integer;').Replace('Result := Self;', 'Result := 1;')
  $UiBAl   = "unit UiB;`n`ninterface`n`nuses`n  System.Classes;`n`ntype`n  TPOne = class(TComponent)`n  public`n    procedure Make;`n  end;`n`n  TAlias = TPOne;`n`nprocedure BRun;`n`nimplementation`n`nuses`n  UiA;`n`n$Make`n`nprocedure BRun;`nbegin`n  TPOne.Create(nil).Make;`nend;`n`nend.`n"
  $IntfSpec = @{ Units = @{ UiA = (& $UiAOf 'TInterfacedObject' '(Sender as IFoo) <> nil'); UiB = $UiBIntf }; Order = @('UiA', 'UiB'); Main = 'BRun;' }
  $P = Prove-Refused 'q2a Sender as IFoo, IFoo names a class with bodies' $IntfSpec 'coupling-remains' 'TUiA'
  $plan = Get-Plan $P
  Check 'q2a the edge says other-ref, naming the interface and its line' ($plan -match '`IFoo` \(no class\): refused: other-ref -- line \d+ tests or casts against `IFoo`') $plan
  $AliasSpec = @{ Units = @{ UiA = (& $UiAOf 'TObject' 'Sender is TAlias'); UiB = $UiBAl }; Order = @('UiA', 'UiB'); Main = 'BRun;' }
  $P = Prove-Refused 'q2b Sender is TAlias, TAlias names a class of its unit' $AliasSpec 'coupling-remains' 'TUiA'
  $plan = Get-Plan $P
  Check 'q2b the edge says other-ref, naming the alias and its line' ($plan -match '`TAlias` \(no class\): refused: other-ref -- line \d+ tests or casts against `TAlias`') $plan
  $null = Prove-Apply 'q2c Sender as IFoo, IFoo names nothing of its unit: it moves' @{ Units = @{ UiA = (& $UiAOf 'TInterfacedObject' '(Sender as IFoo) <> nil'); UiB = $UiBMov }; Order = @('UiA', 'UiB'); Main = 'BRun;' }

  # X is <interface> cannot occur: the compiler refuses it for every left operand, so the wiki says `as`
  foreach ($Lhs in @(@('TObject', 'Sender is IFoo'), @('TInterfacedObject', 'Sender is IFoo'), @('IInterface', 'Sender is IFoo'), @('TComponent', 'Sender is IFoo'))) {
    $Pi = New-Lab @{ Units = @{ UiA = (& $UiAOf $Lhs[0] $Lhs[1]); UiB = $UiBIntf.Replace('A.Check(Self)', 'True') }; Order = @('UiA', 'UiB'); Main = 'BRun;' }
    $b = Invoke-Build $Pi
    Check "q2d $($Lhs[1]) with Sender: $($Lhs[0]) does not compile (E2015)" ((-not $b.Ok) -and ($b.Errors -match 'E2015')) $b.Errors
  }
  Write-Host '== Q3 a constant named qualified in a subrange' -ForegroundColor Cyan
  $BOf = { param($Decl) "unit BUnit;`n`ninterface`n`nconst`n$Decl`n`nprocedure Touch;`n`nimplementation`n`nuses`n  AUnit;`n`nprocedure Touch;`nbegin`n  Writeln(High(TArr));`nend;`n`nend.`n" }
  $AOf = { param($Decl) "unit AUnit;`n`ninterface`n`nuses`n  BUnit;`n`n$Decl`n`nimplementation`n`nend.`n" }
  $Q3a = @{ Units = @{ AUnit = (& $AOf "const`n  cLocal = cOther;`n`ntype`n  TArr = array[0..BUnit.cMax] of Integer;"); BUnit = (& $BOf "  cMax = 5;`n  cOther = 3;") }; Order = @('AUnit', 'BUnit'); Main = 'Touch;' }
  $P = Prove-Refused 'q3a array[0..BUnit.cMax], only cOther moves: the entry stays' $Q3a 'coupling-remains' 'coupling|interface'
  $plan = Get-Plan $P
  Check 'q3a the plan keeps the entry, naming cMax' ($plan -match '(?m)^- `AUnit\.pas` / `BUnit`: \*\*keep\*\* it in the interface uses; that section still uses `cMax`') $plan
  $Q3b = @{ Units = @{ AUnit = (& $AOf "const`n  cLocal = cMax;`n`ntype`n  TArr = array[0..BUnit.cMax] of Integer;"); BUnit = (& $BOf '  cMax = 5;') }; Order = @('AUnit', 'BUnit'); Main = 'Touch;' }
  $P = Prove-Apply 'q3b cMax moves anyway (bare too): the text follows it' $Q3b
  $t = [IO.File]::ReadAllText((Join-Path $P.Root 'AUnit.pas'), $Ascii)
  Check 'q3b reads array[0..BUnit.Untangle.cMax]' ($t.Contains('array[0..BUnit.Untangle.cMax]')) $t
  $Q3c = R1Spec (CU '' "procedure TCCls.Run;`nbegin`n  Foo(1);`n  case 2 of`n    0..DUnit.cMax: Writeln('in');`n  end;`nend;")
  $P = Prove-Apply 'q3c R1: a case label 0..DUnit.cMax moves with the edge' $Q3c
  $t = [IO.File]::ReadAllText((Join-Path $P.Root 'CUnit.pas'), $Ascii)
  Check 'q3c reads 0..DUnit.Untangle.cMax' ($t.Contains('0..DUnit.Untangle.cMax')) $t
  $Pc3 = @{ Units = @{ AUnit = (& $AOf "const`n  cLocal = cOther;`n`ntype`n  TArr = array[0 .. BUnit.cMax] of Integer;"); BUnit = (& $BOf "  cMax = 5;`n  cOther = 3;") }; Order = @('AUnit', 'BUnit'); Main = 'Touch;' }
  $null = Prove-Refused 'pc3 array[0 .. BUnit.cMax], spelled with spaces, the same refusal' $Pc3 'coupling-remains' 'coupling|interface'
  $Q3d = @{ Units = @{ AUnit = (& $AOf "type`n  TArr = array[0..BUnit.cMax] of Integer;"); BUnit = (& $BOf '  cMax = 5;') }; Order = @('AUnit', 'BUnit'); Main = 'Touch;' }
  $null = Prove-Refused 'q3d nothing but the qualified name' $Q3d 'coupling-remains' 'coupling|interface'
}
finally {
  if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("passed {0}, failed {1}" -f $script:Passed, $script:FailCount)
if ($script:Failed) { exit 1 }
exit 0
