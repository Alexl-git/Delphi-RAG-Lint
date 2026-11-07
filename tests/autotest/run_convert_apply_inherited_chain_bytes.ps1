<#
  run_convert_apply_inherited_chain_bytes.ps1 -- C-INHERITED-DFM (wave 146, C1):
  the whole chain of an inherited form, proved on the BYTES and at RUN TIME.

  The other inherited suites pin one descendant against an ancestor fixture that
  is already converted. A real run walks the chain: root, a middle class that
  re-opens nothing, a middle class with an own instance, a leaf with order-only `inherited X: TField [n]` entries, and
  a form hosting an `inline` frame. This suite converts that chain with --apply,
  compiles it with dcc64 and RUNS it: the probe program creates the modules, so
  Delphi's own reader streams every .dfm the engine wrote.

  THE CONTRACT this guard pins, on every route through the chain:
    * RF batch root-first, one process, no reindex between the units.
    * RV batch in REVERSE order: the batch orders the ancestors first (1.42).
    * RS one process per unit, root first, NO reindex between them.
    * RI one process per unit, root first, a reindex between them.
    * RD a descendant that REDECLARES the ancestor's field: that line is retyped,
      its To unit goes to the INTERFACE uses, it compiles and streams; a same-named
      field of another class in the unit is left alone (E-CONVAPPLY-IFACE-USES).
    After each: no From type is left in any .pas / .dfm, the old library unit is
    in no uses clause, the To unit is in the INTERFACE uses of a unit with an
    interface field and in no uses clause twice, the leaf's `[1]` is kept, the
    set compiles, and the probe prints the leaf's and the host's streamed values.
  POSITIVE CONTROLS (this suite can fail):
    * CN the leaf alone, ancestor unconverted: skipped, .dfm byte-identical.
    * CR the root converted, the leaf left alone: the probe DIES loading it with
      EReadError on the From property. So a green probe is a real load, and an
      unconverted descendant really is what this suite would catch.

  Fixture written fresh under $WorkDir, indexed into a scratch --db there.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_inh_chain_$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$Fixture = [ordered]@{}
$Fixture['ChLibOld.pas'] = @'
unit ChLibOld;

interface

uses
  System.Classes;

type
  TOldQ = class(TComponent)
  private
    FSql: string;
    FSize: Integer;
  published
    property SqlText: string read FSql write FSql;
    property Size: Integer read FSize write FSize default 3;
  end;
  TOldF = class(TComponent)
  private
    FLen: Integer;
  published
    property FieldLen: Integer read FLen write FLen default 0;
  end;

implementation

end.
'@
$Fixture['ChLibNew.pas'] = @'
unit ChLibNew;

interface

uses
  System.Classes;

type
  TNewQ = class(TComponent)
  private
    FSql: string;
    FSize: Integer;
  published
    property Statement: string read FSql write FSql;
    property Size: Integer read FSize write FSize default 3;
  end;
  TNewF = class(TComponent)
  private
    FLen: Integer;
  published
    property DataLen: Integer read FLen write FLen default 0;
  end;

implementation

end.
'@
$Fixture['ChHelper.pas'] = @'
unit ChHelper;

interface

function Stamp: string;

implementation

function Stamp: string;
begin
  Result:= 'h';
end;

end.
'@
$Fixture['ChRoot.pas'] = @'
unit ChRoot;

interface

uses
  System.Classes, ChLibOld;

type
  TChRoot = class(TDataModule)
    Q1: TOldQ;
    F1: TOldF;
    F2: TOldF;
  public
    function Show: string;
  end;

implementation

uses
  ChHelper;

{$R *.dfm}

function TChRoot.Show: string;
begin
  Result:= Q1.SqlText + Stamp;
end;

end.
'@
$Fixture['ChRoot.dfm'] = @'
object ChRoot: TChRoot
  Height = 150
  Width = 215
  object Q1: TOldQ
    SqlText = 'root'
    Size = 7
  end
  object F1: TOldF
    FieldLen = 11
  end
  object F2: TOldF
    FieldLen = 22
  end
end
'@
$Fixture['ChMid.pas'] = @'
unit ChMid;

interface

uses
  System.Classes, ChRoot;

type
  TChMid = class(TChRoot)
  end;

implementation

{$R *.dfm}

end.
'@
$Fixture['ChMid.dfm'] = @'
inherited ChMid: TChMid
end
'@
$Fixture['ChMid2.pas'] = @'
unit ChMid2;

interface

uses
  System.Classes, ChMid, ChLibOld;

type
  TChMid2 = class(TChMid)
    Qm: TOldQ;
  end;

implementation

{$R *.dfm}

end.
'@
$Fixture['ChMid2.dfm'] = @'
inherited ChMid2: TChMid2
  object Qm: TOldQ
    SqlText = 'mid'
  end
end
'@
$Fixture['ChLeaf.pas'] = @'
unit ChLeaf;

interface

uses
  System.Classes, ChMid2, ChLibOld;

type
  TChLeaf = class(TChMid2)
    Q2: TOldQ;
  public
    function Read: string;
  end;

implementation

uses
  ChHelper;

{$R *.dfm}

function TChLeaf.Read: string;
begin
  Q1.SqlText:= Q1.SqlText + Stamp;
  Result:= Q1.SqlText + '/' + Q2.SqlText;
end;

end.
'@
$Fixture['ChLeaf.dfm'] = @'
inherited ChLeaf: TChLeaf
  inherited Q1: TOldQ
    SqlText = 'leaf'
  end
  inherited F2: TOldF [1]
    FieldLen = 33
  end
  inherited Qm: TOldQ
    SqlText = 'leafmid'
  end
  object Q2: TOldQ
    SqlText = 'own'
  end
end
'@
$Fixture['ChFrame.pas'] = @'
unit ChFrame;

interface

uses
  System.Classes, Vcl.Forms, ChLibOld;

type
  TChFrame = class(TFrame)
    Qf: TOldQ;
  end;

implementation

{$R *.dfm}

end.
'@
$Fixture['ChFrame.dfm'] = @'
object ChFrame: TChFrame
  Left = 0
  Top = 0
  Width = 100
  Height = 100
  TabOrder = 0
  object Qf: TOldQ
    SqlText = 'frame'
  end
end
'@
$Fixture['ChHost.pas'] = @'
unit ChHost;

interface

uses
  System.Classes, Vcl.Forms, ChFrame;

type
  TChHost = class(TForm)
    Fr: TChFrame;
  end;

implementation

{$R *.dfm}

end.
'@
$Fixture['ChHost.dfm'] = @'
object ChHost: TChHost
  Left = 0
  Top = 0
  Caption = 'host'
  ClientHeight = 120
  ClientWidth = 120
  inline Fr: TChFrame
    Left = 0
    Top = 0
    Width = 100
    Height = 100
    TabOrder = 0
    inherited Qf: TOldQ
      SqlText = 'hosted'
    end
  end
end
'@
$Fixture['ChShadow.pas'] = @'
unit ChShadow;

interface

uses
  System.Classes, ChRoot, ChLibOld;

type
  TChOther = class(TObject)
    F1: TOldF;
  end;
  TChShadow = class(TChRoot)
  published
    F1: TOldF;
  end;

implementation

uses
  ChHelper;

{$R *.dfm}

end.
'@
$Fixture['ChShadow.dfm'] = @'
inherited ChShadow: TChShadow
  inherited F1: TOldF
    FieldLen = 44
  end
end
'@
$Fixture['chain.rules'] = @'
#unuse ChLibOld

#convert TOldQ -> TNewQ
#link Statement <- SqlText
#link Size <- Size

#convert TOldF -> TNewF
#link DataLen <- FieldLen
'@

# Probe bodies: the converted names, or the root-only control's unconverted leaf.
$ProbeNew = @'
program ChProbe;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, ChLeaf, ChHost;

var
  L: TChLeaf;
  H: TChHost;
begin
  try
    L:= TChLeaf.Create(nil);
    H:= TChHost.Create(nil);
    Writeln('leaf=', L.Q1.Statement, ' size=', L.Q1.Size, ' f1=', L.F1.DataLen, ' f2=', L.F2.DataLen, ' own=', L.Q2.Statement, ' mid=', L.Qm.Statement);
    Writeln('read=', L.Read);
    Writeln('hosted=', H.Fr.Qf.Statement);
    Writeln('PROBE_OK');
  except
    on E: Exception do
      Writeln('PROBE_DIED ', E.ClassName, ': ', E.Message);
  end;
end.
'@
$ProbeOld = $ProbeNew -replace 'L\.Q1\.Statement', 'L.Q1.SqlText' -replace 'L\.F1\.DataLen', 'L.F1.FieldLen' -replace 'L\.F2\.DataLen', 'L.F2.FieldLen' -replace 'L\.Q2\.Statement', 'L.Q2.SqlText' -replace 'L\.Qm\.Statement', 'L.Qm.SqlText' -replace 'H\.Fr\.Qf\.Statement', 'H.Fr.Qf.SqlText'

$OrderRoot = @('ChRoot.pas', 'ChMid.pas', 'ChMid2.pas', 'ChLeaf.pas', 'ChFrame.pas', 'ChHost.pas')

function WriteAscii([string]$Path, [string]$Text) {
  $t = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  if (-not $t.EndsWith("`r`n")) { $t += "`r`n" }
  [IO.File]::WriteAllText($Path, $t, [Text.Encoding]::ASCII)
}
function NewCase([string]$Name) {
  $d = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $d -Force | Out-Null
  foreach ($k in $Fixture.Keys) { WriteAscii (Join-Path $d $k) $Fixture[$k] }
  & $Exe index $d --db (Join-Path $d 'fx.sqlite') *> (Join-Path $d 'index.log')
  return $d
}
function Reindex([string]$D) { & $Exe index $D --db (Join-Path $D 'fx.sqlite') *>> (Join-Path $D 'index.log') }
function Apply([string]$D, [string[]]$Units, [string[]]$Extra = @()) {
  $a = @('convert-apply')
  foreach ($u in $Units) { $a += @('--unit', (Join-Path $D $u)) }
  $a += @('--rules', (Join-Path $D 'chain.rules'), '--db', (Join-Path $D 'fx.sqlite')) + $Extra
  $o = (& $Exe @a 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Text([string]$D, [string]$F) { return [IO.File]::ReadAllText((Join-Path $D $F), [Text.Encoding]::ASCII) }
function UsesOf([string]$Pas, [string]$Section) {
  # the names in one section's uses clause, comments not expected in the fixture
  $i = $Pas.IndexOf("`r`n$Section`r`n")
  if ($i -lt 0) { return @() }
  $rest = $Pas.Substring($i + $Section.Length + 4)
  if ($Section -eq 'interface') { $rest = $rest.Substring(0, $rest.IndexOf("`r`nimplementation`r`n")) }
  $m = [regex]::Match($rest, '^\s*uses\s+([^;]*);')
  if (-not $m.Success) { return @() }
  return @($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() })
}
function CompileRun([string]$D, [string]$Probe) {
  WriteAscii (Join-Path $D 'ChProbe.dpr') $Probe
  New-Item -ItemType Directory (Join-Path $D 'bin'), (Join-Path $D 'dcu') -Force | Out-Null
  $bat = Join-Path $D 'compile.bat'; $log = Join-Path $D 'compile.log'
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$D`"",
    "dcc64 -Q -B -NSSystem;Vcl;Winapi;System.Win;Data -E`"$D\bin`" -NU`"$D\dcu`" ChProbe.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  $cl = Get-Content $log -Raw -ErrorAction SilentlyContinue
  $errs = @(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' })
  $ok = ($cl -match 'BUILD_EXITCODE=0') -and ($errs.Count -eq 0)
  $out = ''
  if ($ok) { $out = (& (Join-Path $D 'bin\ChProbe.exe') 2>&1) -join "`n" }
  return [pscustomobject]@{ Compiled = $ok; Errors = ($errs -join ' | '); Out = $out }
}
function AssertConverted([string]$Tag, [string]$D) {
  $all = @('ChRoot', 'ChMid', 'ChMid2', 'ChLeaf', 'ChFrame', 'ChHost')
  $left = @()
  foreach ($u in $all) {
    foreach ($e in '.pas', '.dfm') {
      if ((Text $D "$u$e") -match 'TOld[QF]|ChLibOld|SqlText|FieldLen') { $left += "$u$e" }
    }
  }
  Check "$Tag no From type, From property or old unit is left in any unit" ($left.Count -eq 0) ($left -join ', ')

  $leafDfm = Text $D 'ChLeaf.dfm'
  Check "$Tag leaf: inherited Q1 retyped, keyword kept, override converted" ($leafDfm -match "inherited Q1: TNewQ\r\n\s+Statement = 'leaf'") $leafDfm
  Check "$Tag leaf: order-only [1] kept on the retype" ($leafDfm -match "inherited F2: TNewF \[1\]\r\n\s+DataLen = 33") $leafDfm
  Check "$Tag leaf: own instance is an object block, Size default carried" ($leafDfm -match "object Q2: TNewQ") $leafDfm
  Check "$Tag leaf: a property the block does not stream stays inherited (no Size written)" ($leafDfm -notmatch "inherited Q1: TNewQ\r\n[^\r]*\r\n\s+Size") $leafDfm
  $hostDfm = Text $D 'ChHost.dfm'
  Check "$Tag host: inline frame child retyped, keyword kept" (($hostDfm -match 'inline Fr: TChFrame') -and ($hostDfm -match "inherited Qf: TNewQ\r\n\s+Statement = 'hosted'")) $hostDfm

  $rootPas = Text $D 'ChRoot.pas'
  $leafPas = Text $D 'ChLeaf.pas'
  Check "$Tag root: To unit in the INTERFACE uses, implementation uses untouched" `
    ((@(UsesOf $rootPas 'interface') -contains 'ChLibNew') -and ((@(UsesOf $rootPas 'implementation') -join ',') -eq 'ChHelper')) $rootPas
  Check "$Tag leaf: To unit in the INTERFACE uses (own field Q2), once" `
    ((@(UsesOf $leafPas 'interface') -contains 'ChLibNew') -and (([regex]::Matches($leafPas, 'ChLibNew')).Count -eq 1)) $leafPas
  Check "$Tag leaf: code sites rewritten" ($leafPas -match "Q1\.Statement:= Q1\.Statement \+ Stamp;") $leafPas

  $run = CompileRun $D $ProbeNew
  Check "$Tag the chain compiles with dcc64" $run.Compiled $run.Errors
  $want = @("leaf=leaf size=7 f1=11 f2=33 own=own mid=leafmid", 'read=leafh/own', 'hosted=hosted', 'PROBE_OK') -join "`n"
  Check "$Tag RUN TIME: Delphi streams every written .dfm; the leaf overrides the root, the root's Size is inherited" ($run.Out -eq $want) "got: $($run.Out)"
}

# ---- RF: batch, root first ----------------------------------------------------
$d = NewCase 'rf'
Check 'V the fixture index was built' (Test-Path (Join-Path $d 'fx.sqlite'))
$r = Apply $d $OrderRoot @('--apply', '--no-backup')
Check 'RF batch root-first --apply exits 0' ($r.Code -eq 0) $r.Out
AssertConverted 'RF' $d

# ---- RV: batch, reversed ------------------------------------------------------
$d = NewCase 'rv'
$rev = @($OrderRoot); [array]::Reverse($rev)
$r = Apply $d $rev @('--apply', '--no-backup')
Check 'RV batch reversed --apply exits 0' ($r.Code -eq 0) $r.Out
AssertConverted 'RV' $d

# ---- RS: one process per unit, NO reindex -------------------------------------
$d = NewCase 'rs'
$ok = $true; $why = ''
foreach ($u in $OrderRoot) { $r = Apply $d @($u) @('--apply', '--no-backup'); if ($r.Code -ne 0) { $ok = $false; $why += "$u exit $($r.Code): $($r.Out)`n" } }
Check 'RS one process per unit, no reindex: each exits 0' $ok $why
AssertConverted 'RS' $d

# ---- RI: one process per unit, a reindex between ------------------------------
$d = NewCase 'ri'
$ok = $true; $why = ''
foreach ($u in $OrderRoot) { $r = Apply $d @($u) @('--apply', '--no-backup'); if ($r.Code -ne 0) { $ok = $false; $why += "$u exit $($r.Code): $($r.Out)`n" }; Reindex $d }
Check 'RI one process per unit, reindex between: each exits 0' $ok $why
AssertConverted 'RI' $d

# ---- RD: a descendant that REDECLARES the ancestor's field -------------------
# The designer never writes this, but it compiles: `F1: TOldF` in the descendant's
# own interface. The retype used to leave that line typed TOldF and put the To unit
# in the implementation uses, so the #unuse made it E2003 (E-CONVAPPLY-IFACE-USES).
$d = NewCase 'rd'
$r = Apply $d @('ChRoot.pas', 'ChShadow.pas') @('--apply', '--no-backup')
Check 'RD redeclared field: --apply exits 0' ($r.Code -eq 0) $r.Out
$sp = Text $d 'ChShadow.pas'
Check 'RD the root class''s redeclared field is retyped' ($sp -match "TChShadow = class\(TChRoot\)\r\n  published\r\n    F1: TNewF;") $sp
Check 'RD CONTROL another class''s same-named field is left alone' ($sp -match "TChOther = class\(TObject\)\r\n    F1: TOldF;") $sp
Check 'RD the To unit is in the INTERFACE uses, the implementation uses untouched' `
  ((@(UsesOf $sp 'interface') -contains 'ChLibNew') -and ((@(UsesOf $sp 'implementation') -join ',') -eq 'ChHelper')) $sp
Check 'RD the .dfm block is retyped, keyword kept' ((Text $d 'ChShadow.dfm') -match "inherited F1: TNewF\r\n\s+DataLen = 44") (Text $d 'ChShadow.dfm')
# the unrelated TChOther keeps the old type, so it goes for the compile
[IO.File]::WriteAllText((Join-Path $d 'ChShadow.pas'), $sp.Replace("  TChOther = class(TObject)`r`n    F1: TOldF;`r`n  end;`r`n", ''), [Text.Encoding]::ASCII)
$run = CompileRun $d "program ChProbe;`n`n{`$APPTYPE CONSOLE}`n`nuses`n  System.SysUtils, ChShadow;`n`nvar`n  S: TChShadow;`nbegin`n  try`n    S:= TChShadow.Create(nil);`n    Writeln('f1=', S.F1.DataLen);`n  except`n    on E: Exception do Writeln('PROBE_DIED ', E.ClassName, ': ', E.Message);`n  end;`nend.`n"
Check 'RD it compiles with dcc64 and streams: f1=44' ($run.Compiled -and ($run.Out -eq 'f1=44')) "compiled=$($run.Compiled) errors=$($run.Errors) out=$($run.Out)"
$d = NewCase 'rdplain'
$r = Apply $d @('ChRoot.pas', 'ChMid.pas') @('--apply', '--no-backup')
Check 'RD CONTROL a descendant with no redeclaration: no field edit, no field warning' (($r.Code -eq 0) -and ($r.Out -notmatch 'could not locate field') -and ((Text $d 'ChMid.pas') -notmatch 'ChLibNew')) $r.Out

# ---- CN: the leaf alone, ancestor unconverted ---------------------------------
$d = NewCase 'cn'
$before = Text $d 'ChLeaf.dfm'
$r = Apply $d @('ChLeaf.pas') @('--format', 'json')
$j = $null; try { $j = $r.Out.Substring($r.Out.IndexOf('{')) | ConvertFrom-Json } catch {}
$q = @($j.inherited | Where-Object { $_.name -eq 'Q1' })
Check 'CN CONTROL ancestor unconverted: Q1 skipped, state unconverted' (($q.Count -eq 1) -and ($q[0].action -eq 'skipped') -and ($q[0].ancestor_state -eq 'unconverted')) $r.Out
$r = Apply $d @('ChLeaf.pas') @('--apply', '--no-backup')
$after = Text $d 'ChLeaf.dfm'
Check 'CN CONTROL ... --apply keeps the inherited blocks byte-unchanged' ($after.Contains("inherited Q1: TOldQ`r`n    SqlText = 'leaf'`r`n  end`r`n  inherited F2: TOldF [1]")) "before:`n$before`nafter:`n$after"

# ---- CR: the root converted, the leaf not: the load dies ----------------------
$d = NewCase 'cr'
$r = Apply $d @('ChRoot.pas') @('--apply', '--no-backup')
Check 'CR CONTROL root alone --apply exits 0' ($r.Code -eq 0) $r.Out
# the leaf's code is taken out of the way, so the failure is the LOAD, not the compile
$lp = Join-Path $d 'ChLeaf.pas'
[IO.File]::WriteAllText($lp, (Text $d 'ChLeaf.pas').Replace("  Q1.SqlText:= Q1.SqlText + Stamp;`r`n", '').Replace("Q1.SqlText + '/' + Q2.SqlText", "Q2.SqlText + Stamp"), [Text.Encoding]::ASCII)
$run = CompileRun $d ($ProbeOld -replace 'L\.Q1\.SqlText', 'L.Q1.Statement' -replace 'L\.F1\.FieldLen', 'L.F1.DataLen' -replace 'L\.F2\.FieldLen', 'L.F2.DataLen')
Check 'CR CONTROL the unconverted leaf compiles under the converted root' $run.Compiled $run.Errors
Check 'CR CONTROL ... and DIES at load: Delphi reads the From property on the converted component' ($run.Out -match 'PROBE_DIED EReadError') "out=$($run.Out)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if ($WorkDir -like 'C:\TEMP\draglint_convert_apply_inh_chain_*' -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
