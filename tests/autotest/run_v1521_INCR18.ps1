<#
  run_v1521_INCR18.ps1 -- GitHub #18: a one-file incremental index must not re-run
  whole-database work, and the narrower resolve scope must write the SAME database.

  PART 1 (fixture, about a minute): a 15-unit fixture, one edit per scenario. For each edit
  three databases are built from the same edited tree --
      S  base + incremental, SCOPED resolve            (the shipped path)
      W  base + incremental, DRAGLINT_NO_SCOPED_RESOLVE (whole-database resolve, same binary)
      F  a fresh full index
  -- and tools\measure\index_db_diff.py must report S = W and S = F (0 differing rows).
  Scenarios: rename a local, add a parameter, rename a routine other units call, edit an
  enum, edit a DFM-bound handler, edit an include host, edit the include itself.
  (The include is a routine-body fragment: the engine keeps no symbols for it, so that edit
  asserts the diffs only, not a narrowing line.)

  POSITIVE CONTROL (load-bearing): the test seam DRAGLINT_TEST_SCOPE_NO_NAMES=1 gives the
  scoped pass a deliberately WRONG scope (changed files only, no names). On the add-a-parameter
  edit that must show diff rows against W -- else index_db_diff could not see a lost edge and
  every "0 rows" above would prove nothing. The path assertions (SCOPED / WHOLE-DB in the log)
  keep the A/B from comparing whole-DB against whole-DB.

  NARROWING WITNESS (the RED of #18 cause 1): on the rename-a-local edit the scoped pass must
  say it left local / parameter names out of the name scope; on the include edits it must say
  it kept them (a routine body split over an include is the one cross-file reach of a local).

  PART 1b (step 3, closure cache; a 12-unit project fixture): `index --project` keeps what the
  compile-closure walk read out of each unit and reuses it while the unit and EVERY include file
  its scan read are unchanged. Edits: a nested include (its define switches a uses entry on),
  a missing include created, an include deleted, a constant another unit's IF reads. Per edit
  C (cache on) = U (DRAGLINT_NO_CLOSURE_CACHE) = F (fresh full index), 0 diff rows, the closure
  really changed, and run C really reused stored scans. POSITIVE CONTROL: the seam
  DRAGLINT_TEST_CC_STAMP_ONLY=1 (unit stamp only, the key main declined) must
  leave a stale closure and diff rows on the nested-include edit.

  PART 1c (step 4, scoped purity; an 8-unit fixture): after a scoped resolve pass the purity
  stage re-derives only what the pass can have moved and keeps every other stored verdict.
  Edits: a callee gains a global write (callers two files away must flip), a called routine is
  withdrawn, a base class gains a field a descendant writes, a body edit that moves no verdict,
  a procedural type appears (the run must fall back to the whole database and say why). Per edit
  S (scoped purity) = P (DRAGLINT_NO_SCOPED_PURITY) = F (fresh full index), 0 diff rows over
  symbol_facts and every other table. POSITIVE CONTROL: the seam
  DRAGLINT_TEST_PURITY_SEEDS_ONLY=1 (callers not followed) must leave a stale verdict and diff
  rows. Part 1 and Part 2 assert the same equality on their own edits: their S run now runs
  purity scoped and their W run whole.

  PART 2 (drag-lint's own CLI project; OPT-IN with -Dl -- the battery's run_*.ps1 discovery runs
  this script without arguments, and Part 2 costs a full index plus four whole-database resolves,
  30 minutes and more): a copy of src\ is indexed in full, then
    * TIMING GATE: one file (DRagLint.CLI.Hover.pas) forced stale, incremental index, median of
      3 wall times <= -MaxSeconds (default 5);
    * the S = W diff on real edits of that tree (local rename, added parameter, a signature
      other units use, an enum value).
  -DlWork <dir> keeps the tree copy and the base index between runs (rebuilt when the exe is
  newer than the base). -DlTree <dir> -DlBase <db> reuse an existing tree and its full index.

  Run from a neutral CWD (C:\TEMP), pwsh 7. Needs Python 3 (py or python) for index_db_diff.
#>
[CmdletBinding()]
param(
  [string]$Exe = '',
  [switch]$Dl,
  [string]$DlWork = '',
  [string]$DlTree = '',
  [string]$DlBase = '',
  [double]$MaxSeconds = 5.0,
  [string[]]$DlScenarios = @('local', 'param', 'decl', 'enum'),
  [switch]$KeepScratch
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$scratch = Join-Path C:\TEMP "draglint_incr18_$PID"
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$diffPy  = Join-Path $Repo 'tools\measure\index_db_diff.py'
$pyExe = 'python'; $pyPre = @()
if (Get-Command py -ErrorAction SilentlyContinue) { $pyExe = 'py'; $pyPre = @('-I') }

if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$env:DRAGLINT_RULE_CACHE = '0'

function Write-Ascii($p, $t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))
}
function Remove-Db($db) { foreach ($s in '', '-wal', '-shm') { if (Test-Path -LiteralPath "$db$s") { Remove-Item -LiteralPath "$db$s" -Force } } }
function Copy-Db($from, $to) { Remove-Db $to; Copy-Item -LiteralPath $from -Destination $to }

# Runs the engine with extra environment variables; returns stdout + stderr as one string.
function Invoke-Engine([string[]]$ArgList, [hashtable]$EnvSet) {
  if ($EnvSet) { foreach ($k in $EnvSet.Keys) { Set-Item "Env:\$k" $EnvSet[$k] } }
  try {
    $out = & { $ErrorActionPreference = 'Continue'; & $exePath @ArgList 2>&1 | ForEach-Object { "$_" } } | Out-String
    $script:LastEngineExit = $LASTEXITCODE
  } finally {
    if ($EnvSet) { foreach ($k in $EnvSet.Keys) { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue } }
  }
  return $out
}

# index_db_diff: returns @{ Same = bool; Text = last lines }.
function Compare-Db($a, $b) {
  $out = & { $ErrorActionPreference = 'Continue'; & $pyExe @pyPre $diffPy $a $b 2>&1 | ForEach-Object { "$_" } }
  $code = $LASTEXITCODE
  # exit 0 = identical, 1 = differences, 2 (or anything else) = the tool could not compare.
  if ($code -ne 0 -and $code -ne 1) { $out = @("index_db_diff exit $code -- NOT a comparison") + $out }
  $tell = @($out | Where-Object { $_ -match 'DIFF|only A|only B|^\s+[AB] |TABLE ONLY|FILE ONLY|index_db_diff|Traceback|Error' } | Select-Object -First 16)
  if ($tell.Count -eq 0) { $tell = @($out | Select-Object -Last 6) }
  return @{ Same = ($code -eq 0); Code = $code; Text = ($tell -join "`n      ") }
}

$WHOLE   = @{ DRAGLINT_NO_SCOPED_RESOLVE = '1' }
$NONAMES = @{ DRAGLINT_TEST_SCOPE_NO_NAMES = '1' }
$LEFT_OUT = 'local / parameter name\(s\) left out of the name scope'
$KEPT_IN  = 'local / parameter name\(s\) kept in the name scope'

# ------------------------------------------------------------------ PART 1: fixture
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

Write-Ascii (Join-Path $src 'uUtil.pas') @'
unit uUtil;

interface

type
  TMode = (mdOne, mdTwo);

function Helper(AValue: Integer): Integer;
function Shared(AValue: Integer): Integer;

implementation

function Helper(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

function Shared(AValue: Integer): Integer;
begin
  Result := Helper(AValue) * 2;
end;

end.
'@

# Locals named like uUtil's routines: before #18 their names pulled every `Helper` / `Shared`
# call of the other units into the scoped pass.
Write-Ascii (Join-Path $src 'uLeaf.pas') @'
unit uLeaf;

interface

function LeafCalc(AValue: Integer): Integer;

implementation

function LeafCalc(AValue: Integer): Integer;
var
  Helper: Integer;
  Shared: Integer;
begin
  Helper := AValue * 3;
  Shared := Helper + 1;
  Result := Helper + Shared;
end;

end.
'@

Write-Ascii (Join-Path $src 'uUserA.pas') @'
unit uUserA;

interface

uses
  uUtil, uLeaf;

function UseA(AValue: Integer): Integer;

implementation

function UseA(AValue: Integer): Integer;
var
  M: TMode;
begin
  M := mdOne;
  if M = mdTwo then Exit(0);
  Result := Helper(AValue) + Shared(AValue) + LeafCalc(AValue);
end;

end.
'@

Write-Ascii (Join-Path $src 'uUserB.pas') @'
unit uUserB;

interface

uses
  uUtil;

function UseB: Integer;

implementation

function UseB: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 3 do
    Result := Result + Shared(I) + Ord(mdTwo);
end;

end.
'@

Write-Ascii (Join-Path $src 'uForm.pas') @'
unit uForm;

interface

uses
  Classes, Forms, StdCtrls, uUtil;

type
  TForm1 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    FCount: Integer;
  public
    function Count: Integer;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.Button1Click(Sender: TObject);
begin
  FCount := Helper(FCount);
end;

function TForm1.Count: Integer;
begin
  Result := FCount;
end;

end.
'@

Write-Ascii (Join-Path $src 'uForm.dfm') @'
object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Form1'
  ClientHeight = 100
  ClientWidth = 200
  object Button1: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Go'
    OnClick = Button1Click
  end
end
'@

Write-Ascii (Join-Path $src 'uFormUser.pas') @'
unit uFormUser;

interface

uses
  uForm;

function FormCount: Integer;

implementation

function FormCount: Integer;
begin
  Result := Form1.Count;
end;

end.
'@

# A routine body split over an include: the local `Shared` is declared in the host and read
# in the include, the one shape in which a local reaches a ref of ANOTHER file.
Write-Ascii (Join-Path $src 'uHost.pas') @'
unit uHost;

interface

function HostCalc(AValue: Integer): Integer;

implementation

uses
  uUtil;

function HostCalc(AValue: Integer): Integer;
var
  Shared: Integer;
begin
  Shared := AValue;
  {$I uBody.inc}
end;

end.
'@

Write-Ascii (Join-Path $src 'uBody.inc') @'
  var Tmp: Integer := Shared + Helper(AValue);
  Result := Tmp;
'@

foreach ($n in 1..8) {
  Write-Ascii (Join-Path $src "uFill$n.pas") @"
unit uFill$n;

interface

uses
  uUtil;

function Fill$n(AValue: Integer): Integer;

implementation

function Fill$n(AValue: Integer): Integer;
begin
  Result := Helper(AValue) + $n;
end;

end.
"@
}

# name, file, find, replace, expected narrowing line ('' = not asserted)
$scenarios = @(
  @{ Name = 'rename a local';              File = 'uLeaf.pas'; Find = 'Shared';  Repl = 'Total'; Witness = $LEFT_OUT },
  @{ Name = 'add a parameter';             File = 'uUtil.pas'; Find = 'function Shared(AValue: Integer): Integer;'; Repl = 'function Shared(AValue: Integer; AScale: Integer = 2): Integer;'; Witness = $LEFT_OUT; Control = $true },
  @{ Name = 'rename a routine others call'; File = 'uUtil.pas'; Find = 'Helper';  Repl = 'HelperX'; Witness = '' },
  @{ Name = 'edit an enum';                File = 'uUtil.pas'; Find = '(mdOne, mdTwo)'; Repl = '(mdOne, mdTwo, mdThree)'; Witness = '' },
  @{ Name = 'edit a DFM-bound handler';    File = 'uForm.pas'; Find = 'FCount := Helper(FCount);'; Repl = 'FCount := Helper(FCount) + 1;'; Witness = '' },
  @{ Name = 'edit an include host';        File = 'uHost.pas'; Find = 'Shared := AValue;'; Repl = 'Shared := AValue + 0;'; Witness = $KEPT_IN },
  @{ Name = 'edit the include';            File = 'uBody.inc'; Find = 'Helper(AValue);'; Repl = 'Helper(AValue) + 0;'; Witness = '' }
)

Push-Location C:\TEMP
try {
  $dbBase = Join-Path $scratch 'base.sqlite'
  Invoke-Engine @('index', $src, '--db', $dbBase) $null | Out-Null
  $baseEdges = 0
  $cnt = Invoke-Engine @('sql', '--query', 'SELECT count(*) AS n FROM call_edges', '--db', $dbBase, '--json') $null
  if ($cnt -match '"rows"\s*:\s*\[\s*\[\s*(\d+)') { $baseEdges = [int]$Matches[1] }
  Check 'SANITY: the fixture base index holds call edges (an empty A/B proves nothing)' ($baseEdges -ge 10) "edges=$baseEdges`n$cnt"

  foreach ($sc in $scenarios) {
    $file = Join-Path $src $sc.File
    $keep = Join-Path $scratch ($sc.File + '.orig')
    [System.IO.File]::Copy($file, $keep, $true)
    $text = [System.IO.File]::ReadAllText($file)
    if (-not $text.Contains($sc.Find)) { Check "$($sc.Name): the edit applies" $false "no '$($sc.Find)' in $($sc.File)"; continue }
    Write-Ascii $file $text.Replace($sc.Find, $sc.Repl)

    $dbS = Join-Path $scratch 's.sqlite'; $dbW = Join-Path $scratch 'w.sqlite'; $dbF = Join-Path $scratch 'f.sqlite'
    Copy-Db $dbBase $dbS; Copy-Db $dbBase $dbW; Remove-Db $dbF
    $outS = Invoke-Engine @('index', $src, '--db', $dbS) $null
    $outW = Invoke-Engine @('index', $src, '--db', $dbW) $WHOLE
    Invoke-Engine @('index', $src, '--db', $dbF) $null | Out-Null

    Check "$($sc.Name): run S took the SCOPED path" ($outS -match 'starting SCOPED pass') ($outS -split "`n" | Select-String 'calls ' | Select-Object -First 4 | Out-String)
    Check "$($sc.Name): run W took the WHOLE-DB path" ($outW -match 'starting WHOLE-DB pass') ''
    # Step 4: S also ran the purity stage SCOPED and W ran it whole, so the two 0-row diffs below
    # compare scoped purity with whole purity and with a full reindex (symbol_facts included).
    Check "$($sc.Name): run S re-derived a purity scope, run W every routine" ($outS -match 'resolve: purity scope -- \d+ of \d+ routine\(s\) re-derived' -and $outW -notmatch 'resolve: purity scope -- \d+ of') ($outS -split "`n" | Select-String 'purity' | Out-String)
    $d = Compare-Db $dbS $dbW
    Check "$($sc.Name): scoped = whole-database resolve (0 diff rows)" $d.Same $d.Text
    $d = Compare-Db $dbS $dbF
    Check "$($sc.Name): scoped incremental = full reindex (0 diff rows)" $d.Same $d.Text
    if ($sc.Witness) {
      Check "$($sc.Name): narrowing line '$($sc.Witness -replace '\\', '')'" ($outS -match $sc.Witness) ($outS -split "`n" | Select-String 'calls ' | Select-Object -First 6 | Out-String)
    }
    if ($sc.Control) {
      $dbC = Join-Path $scratch 'c.sqlite'
      Copy-Db $dbBase $dbC
      $outC = Invoke-Engine @('index', $src, '--db', $dbC) $NONAMES
      $d = Compare-Db $dbC $dbW
      Check "$($sc.Name): POSITIVE CONTROL -- a files-only scope (test seam) took the SCOPED path" ($outC -match 'starting SCOPED pass') ''
      Check "$($sc.Name): POSITIVE CONTROL -- a files-only scope shows diff rows" (-not $d.Same -and $d.Code -eq 1) "index_db_diff exit $($d.Code): the diff cannot see a lost edge`n      $($d.Text)"
    }
    [System.IO.File]::Copy($keep, $file, $true)
  }
} finally { Pop-Location }

# ------------------------------------------------------------------ PART 1c: scoped purity (step 4)
# After a SCOPED call-target pass the purity stage re-derives only what that pass can have moved
# (the rewritten files' routines, the routines around a ref whose binding changed, the methods of
# a class whose own or inherited members can have moved, and every transitive caller) and keeps
# every other stored verdict. Per edit, three databases from the same edited tree:
#   S  scoped resolve + scoped purity       P  scoped resolve + DRAGLINT_NO_SCOPED_PURITY=1
#   F  fresh full index
# Required: S = P and S = F, 0 diff rows (index_db_diff compares symbol_facts.effect_free /
# effect_summary / effect_witness with every other table). POSITIVE CONTROL: the test seam
# DRAGLINT_TEST_PURITY_SEEDS_ONLY=1 (seeds re-derived, callers not followed) must show diff rows.
$psrc = Join-Path $scratch 'src_pur'
New-Item -ItemType Directory -Path $psrc | Out-Null

Write-Ascii (Join-Path $psrc 'uPurA.pas') @'
unit uPurA;

interface

var
  GCount: Integer;

function Leaf(AValue: Integer): Integer;
function Mid(AValue: Integer): Integer;
function Gone(AValue: Integer): Integer;

implementation

function Leaf(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

function Mid(AValue: Integer): Integer;
begin
  Result := Leaf(AValue) * 2;
end;

function Gone(AValue: Integer): Integer;
begin
  GCount := AValue;
  Result := AValue;
end;

end.
'@

Write-Ascii (Join-Path $psrc 'uPurB.pas') @'
unit uPurB;

interface

function Top(AValue: Integer): Integer;
function Over(AValue: Integer): Integer;
function UsesGone(AValue: Integer): Integer;
function Apart(AValue: Integer): Integer;

implementation

uses
  uPurA;

function Top(AValue: Integer): Integer;
begin
  Result := Mid(AValue) + 1;
end;

function Over(AValue: Integer): Integer;
begin
  Result := Top(AValue) + 1;
end;

function UsesGone(AValue: Integer): Integer;
begin
  Result := Gone(AValue);
end;

function Apart(AValue: Integer): Integer;
begin
  Result := AValue * 3;
end;

end.
'@

Write-Ascii (Join-Path $psrc 'uPurC.pas') @'
unit uPurC;

interface

function Far(AValue: Integer): Integer;

implementation

uses
  uPurB;

function Far(AValue: Integer): Integer;
begin
  Result := Over(AValue);
end;

end.
'@

# A call cycle in a file the edits never touch: its witnesses must come out the same text
# whether the cycle is re-derived alone (scoped) or with everything else (whole).
Write-Ascii (Join-Path $psrc 'uPurCyc.pas') @'
unit uPurCyc;

interface

function Ping(AValue: Integer): Integer;
function Pong(AValue: Integer): Integer;

implementation

uses
  uPurA;

function Ping(AValue: Integer): Integer;
begin
  if AValue > 0 then Result := Pong(AValue - 1)
  else Result := 0;
end;

function Pong(AValue: Integer): Integer;
begin
  if AValue > 0 then Result := Ping(AValue - 1)
  else Result := Leaf(AValue);
end;

end.
'@

Write-Ascii (Join-Path $psrc 'uPurBase.pas') @'
unit uPurBase;

interface

type
  TPurBase = class
  private
    FSeen: Integer;
  public
    function Seen: Integer;
  end;

implementation

function TPurBase.Seen: Integer;
begin
  Result := FSeen;
end;

end.
'@

Write-Ascii (Join-Path $psrc 'uPurKid.pas') @'
unit uPurKid;

interface

uses
  uPurBase;

type
  TPurKid = class(TPurBase)
  public
    procedure Work;
  end;

procedure DriveKid(AKid: TPurKid);

implementation

var
  Extra: Integer;

procedure TPurKid.Work;
begin
  Extra := 1;
end;

procedure DriveKid(AKid: TPurKid);
begin
  AKid.Work;
end;

end.
'@

Write-Ascii (Join-Path $psrc 'uPurT.pas') @'
unit uPurT;

interface

type
  THook = Integer;

implementation

end.
'@

Write-Ascii (Join-Path $psrc 'uPurP.pas') @'
unit uPurP;

interface

uses
  uPurT;

var
  Hook: THook;

procedure CallHook;

implementation

procedure CallHook;
var
  Kept: THook;
begin
  Kept := Hook;
  if Kept = Hook then Exit;
end;

end.
'@

$NOSCOPEDPURITY = @{ DRAGLINT_NO_SCOPED_PURITY = '1' }
$SEEDSONLY      = @{ DRAGLINT_TEST_PURITY_SEEDS_ONLY = '1' }
$SCOPE_LINE     = 'resolve: purity scope -- (\d+) of (\d+) routine\(s\) re-derived'

# The effect_free value of the one routine named $name (-1 = no such row / NULL).
function Get-EffectFree($db, $name) {
  $o = Invoke-Engine @('sql', '--query', "SELECT ifnull(sf.effect_free, -1) AS e FROM symbol_facts sf JOIN symbols s ON s.id = sf.symbol_id WHERE s.name = '$name'", '--db', $db, '--json') $null
  if ($o -match '"rows"\s*:\s*\[\s*\[\s*(-?\d+)') { return [int]$Matches[1] }
  return -1
}

# name, file, find, replace; Whole = the run must fall back to the whole database and say why;
# Small = the scope must be smaller than the database; Control = run the seeds-only seam too;
# Flip = a routine of ANOTHER file whose verdict the edit must move (effect-free 1 -> 0).
$purScenarios = @(
  @{ Name = 'PUR a callee gains a global write'; File = 'uPurA.pas'; Find = '  Result := AValue + 1;'; Repl = "  GCount := AValue;`r`n  Result := AValue + 1;"; Control = $true; Flip = 'Far'; Small = $true },
  @{ Name = 'PUR a called routine is withdrawn'; File = 'uPurA.pas'; Find = 'Gone'; Repl = 'Gone2'; Small = $true },
  @{ Name = 'PUR a base class gains a field a descendant writes'; File = 'uPurBase.pas'; Find = '    FSeen: Integer;'; Repl = "    FSeen: Integer;`r`n    Extra: Integer;"; Small = $true },  # 1.52.3 INCR-BASEFIELD closed its FullGap: the descendant's file lists the ancestor's file (schema_meta file_ancestors:)
  @{ Name = 'PUR a body edit that moves no verdict'; File = 'uPurC.pas'; Find = 'Result := Over(AValue);'; Repl = 'Result := Over(AValue) + 0;'; Small = $true },
  @{ Name = 'PUR a procedural type appears'; File = 'uPurT.pas'; Find = 'THook = Integer;'; Repl = 'THook = procedure;'; Whole = $true }
)

Push-Location C:\TEMP
try {
  $dbPur = Join-Path $scratch 'pur_base.sqlite'
  $outBase = Invoke-Engine @('index', $psrc, '--db', $dbPur) $null
  Check 'PUR SANITY: the full index of the fixture ran purity over the whole database (no scope line)' ($outBase -match 'resolve: purity -- \d+ routine' -and $outBase -notmatch 'resolve: purity scope') ($outBase -split "`n" | Select-String 'purity' | Out-String)
  Check 'PUR SANITY: Far is effect-free and UsesGone is not, before any edit' ((Get-EffectFree $dbPur 'Far') -eq 1 -and (Get-EffectFree $dbPur 'UsesGone') -eq 0) "Far=$(Get-EffectFree $dbPur 'Far') UsesGone=$(Get-EffectFree $dbPur 'UsesGone')"

  foreach ($sc in $purScenarios) {
    $file = Join-Path $psrc $sc.File
    $keep = Join-Path $scratch ($sc.File + '.orig')
    [System.IO.File]::Copy($file, $keep, $true)
    $text = [System.IO.File]::ReadAllText($file)
    if (-not $text.Contains($sc.Find)) { Check "$($sc.Name): the edit applies" $false "no '$($sc.Find)' in $($sc.File)"; continue }
    Write-Ascii $file $text.Replace($sc.Find, $sc.Repl)

    $dbS = Join-Path $scratch 'ps.sqlite'; $dbP = Join-Path $scratch 'pp.sqlite'; $dbF = Join-Path $scratch 'pf.sqlite'
    Copy-Db $dbPur $dbS; Copy-Db $dbPur $dbP; Remove-Db $dbF
    $outS = Invoke-Engine @('index', $psrc, '--db', $dbS) $null
    $outP = Invoke-Engine @('index', $psrc, '--db', $dbP) $NOSCOPEDPURITY
    Invoke-Engine @('index', $psrc, '--db', $dbF) $null | Out-Null
    $purLines = ($outS -split "`n" | Select-String 'purity|SCOPED|WHOLE' | Out-String)

    Check "$($sc.Name): run S resolved SCOPED" ($outS -match 'starting SCOPED pass') $purLines
    if ($sc.Whole) {
      Check "$($sc.Name): run S fell back to the whole database and said why" ($outS -match 'resolve: purity scope -- whole database: the procedural type names') $purLines
    } else {
      $scoped = $outS -match $SCOPE_LINE
      $n = 0; $m = 0; if ($scoped) { $n = [int]$Matches[1]; $m = [int]$Matches[2] }
      Check "$($sc.Name): run S re-derived a purity scope" $scoped $purLines
      if ($sc.Small) { Check "$($sc.Name): the scope is smaller than the database ($n of $m)" ($scoped -and $n -ge 1 -and $n -lt $m) $purLines }
    }
    Check "$($sc.Name): run P re-derived every routine (DRAGLINT_NO_SCOPED_PURITY)" ($outP -match 'resolve: purity scope -- whole database: DRAGLINT_NO_SCOPED_PURITY is set') ($outP -split "`n" | Select-String 'purity' | Out-String)
    $d = Compare-Db $dbS $dbP
    Check "$($sc.Name): scoped purity = whole purity (0 diff rows)" $d.Same $d.Text
    $d = Compare-Db $dbS $dbF
    if ($sc.FullGap) {
      # An incremental index that differs from a full one BEFORE purity runs (the input rows
      # differ, with scoped purity on or off: S = P above). Reported, not asserted.
      Write-Host "[NOTE] $($sc.Name): incremental $(if ($d.Same) { '=' } else { '<>' }) full reindex -- known input gap: $($sc.FullGap)" -ForegroundColor Yellow
    } else {
      Check "$($sc.Name): scoped purity = full reindex (0 diff rows)" $d.Same $d.Text
    }
    if ($sc.Flip) {
      Check "$($sc.Name): the verdict of $($sc.Flip), two files away, moved to not-effect-free" ((Get-EffectFree $dbS $sc.Flip) -eq 0) "effect_free=$(Get-EffectFree $dbS $sc.Flip)"
    }
    if ($sc.Control) {
      $dbC = Join-Path $scratch 'pc.sqlite'
      Copy-Db $dbPur $dbC
      $outC = Invoke-Engine @('index', $psrc, '--db', $dbC) $SEEDSONLY
      $d = Compare-Db $dbC $dbF
      Check "$($sc.Name): POSITIVE CONTROL -- the seeds-only seam ran scoped" ($outC -match 'TEST SEAM DRAGLINT_TEST_PURITY_SEEDS_ONLY') ($outC -split "`n" | Select-String 'purity' | Out-String)
      Check "$($sc.Name): POSITIVE CONTROL -- a scope that does not follow callers shows diff rows" (-not $d.Same -and $d.Code -eq 1) "index_db_diff exit $($d.Code): the diff cannot see a stale verdict`n      $($d.Text)"
      Check "$($sc.Name): POSITIVE CONTROL -- $($sc.Flip) kept its stale effect-free verdict" ((Get-EffectFree $dbC $sc.Flip) -eq 1) "effect_free=$(Get-EffectFree $dbC $sc.Flip)"
    }
    [System.IO.File]::Copy($keep, $file, $true)
  }
} finally { Pop-Location }

# ------------------------------------------------------------------ PART 1b: closure cache (step 3)
# `index --project` keeps what the compile-closure walk read out of each unit (table
# closure_cache) and reuses it while the unit AND every include file its scan read are
# unchanged. A unit's uses clause can hang on a define an include sets, so the include files
# are part of the key: editing, creating or deleting one must change the closure exactly as an
# uncached walk does. Per edit three databases from the same edited tree --
#     C  base + incremental, closure cache on         (the shipped path)
#     U  base + incremental, DRAGLINT_NO_CLOSURE_CACHE (cold walk, same binary)
#     F  a fresh full index
# -- and C = U, C = F (0 differing rows), the closure really changed, and run C really reused
# stored scans. POSITIVE CONTROL: the seam DRAGLINT_TEST_CC_STAMP_ONLY=1 validates a
# stored scan by the unit's own stamp only (the key main declined as unsound); on the
# nested-include edit it must leave the new unit OUT of the closure and show diff rows against F.
# A scan that asked another unit for a constant ({$IF} on a used unit's const) is never stored.
# An edit may carry HostGap (a known incremental-indexer gap): it then asserts C = U and the
# closure membership and prints the difference to F as a NOTE. 1.52.2 INCRPP closed the two
# that had it (a missing include created; a constant another unit's IF reads), so every edit
# now asserts C = F (run_v1522_INCRPP_incremental.ps1 is their own RED/GREEN test).
$cc = Join-Path $scratch 'cc'
New-Item -ItemType Directory -Path $cc | Out-Null
$ccProj = Join-Path $cc 'Proj.dpr'

Write-Ascii $ccProj @'
program Proj;

uses
  uMain in 'uMain.pas';

begin
  Run;
end.
'@

Write-Ascii (Join-Path $cc 'uMain.pas') @'
unit uMain;

interface

procedure Run;

implementation

uses
  uA, uB, uD, uIf;

procedure Run;
begin
  ValueA;
  ValueB;
  ValueD;
  ValueIf;
end;

end.
'@

# uA: the uses entry hangs on a define set two includes down (cc18cfg.inc -> cc18cfg2.inc).
Write-Ascii (Join-Path $cc 'uA.pas') @'
unit uA;

{$I cc18cfg.inc}

interface

uses
  uBase
  {$IFDEF WITH_EXTRA}, uExtra{$ENDIF}
  ;

function ValueA: Integer;

implementation

function ValueA: Integer;
begin
  Result := BaseValue;
end;

end.
'@
Write-Ascii (Join-Path $cc 'cc18cfg.inc') @'
{$I cc18cfg2.inc}
'@
Write-Ascii (Join-Path $cc 'cc18cfg2.inc') @'
{ no define yet }
'@

# uB: its include does not exist yet.
Write-Ascii (Join-Path $cc 'uB.pas') @'
unit uB;

{$I cc18opt.inc}

interface

uses
  uBase
  {$IFDEF OPT_ON}, uOpt{$ENDIF}
  ;

function ValueB: Integer;

implementation

function ValueB: Integer;
begin
  Result := BaseValue + 1;
end;

end.
'@

# uD: its include exists and switches a unit ON; deleting it takes the unit out.
Write-Ascii (Join-Path $cc 'uD.pas') @'
unit uD;

{$I cc18on.inc}

interface

uses
  uBase
  {$IFDEF D_ON}, uDx{$ENDIF}
  ;

function ValueD: Integer;

implementation

function ValueD: Integer;
begin
  Result := BaseValue + 2;
end;

end.
'@
Write-Ascii (Join-Path $cc 'cc18on.inc') @'
{$DEFINE D_ON}
'@

# uIf: an {$IF} on a constant of ANOTHER unit decides its uses clause -- no include involved.
Write-Ascii (Join-Path $cc 'uIf.pas') @'
unit uIf;

interface

uses
  uConsts;

function ValueIf: Integer;

implementation

{$IF CC_LEVEL > 1}
uses
  uIfX;
{$IFEND}

function ValueIf: Integer;
begin
  Result := CC_LEVEL;
end;

end.
'@
Write-Ascii (Join-Path $cc 'uConsts.pas') @'
unit uConsts;

interface

const
  CC_LEVEL = 1;

implementation

end.
'@

Write-Ascii (Join-Path $cc 'uBase.pas') @'
unit uBase;

interface

function BaseValue: Integer;

implementation

function BaseValue: Integer;
begin
  Result := 1;
end;

end.
'@
foreach ($u in 'uExtra', 'uOpt', 'uDx', 'uIfX') {
  Write-Ascii (Join-Path $cc "$u.pas") @"
unit $u;

interface

function ${u}Value: Integer;

implementation

function ${u}Value: Integer;
begin
  Result := 7;
end;

end.
"@
}

$PROF    = @{ DRAGLINT_PROFILE = '1' }
$NOCACHE = @{ DRAGLINT_PROFILE = '1'; DRAGLINT_NO_CLOSURE_CACHE = '1' }
$NOINCS  = @{ DRAGLINT_PROFILE = '1'; DRAGLINT_TEST_CC_STAMP_ONLY = '1' }
# A file modified under two seconds before a walk is never stored (its stamp could repeat).
$SETTLE_MS = 2500

# 'CLOSURE CACHE: 9 unit scan(s) reused, 2 computed (2 not cacheable)' -> the three counts, or $null.
function Get-ClosureCacheLine($out) {
  if ($out -match 'CLOSURE CACHE: (\d+) unit scan\(s\) reused, (\d+) computed \((\d+) not cacheable\)') {
    return @{ Reused = [int]$Matches[1]; Computed = [int]$Matches[2]; NotCacheable = [int]$Matches[3] }
  }
  return $null
}
# How many files rows the database holds for a unit file name (0 = not in the closure).
function Get-FileRows($db, $fileName) {
  $q = "SELECT count(*) AS n FROM files WHERE lower(path) LIKE '%\" + $fileName.ToLower() + "'"
  $r = Invoke-Engine @('sql', '--query', $q, '--db', $db, '--json') $null
  if ($r -match '"rows"\s*:\s*\[\s*\[\s*(\d+)') { return [int]$Matches[1] }
  return -1
}

Push-Location C:\TEMP
try {
  $ccBase = Join-Path $scratch 'cc_base.sqlite'
  Start-Sleep -Milliseconds $SETTLE_MS
  $outBase = Invoke-Engine @('index', '--project', $ccProj, '--db', $ccBase) $PROF
  $lineBase = Get-ClosureCacheLine $outBase
  Check 'CC: the base index ran the closure walk with the cache on and computed scans it can store' ($null -ne $lineBase -and $lineBase.Computed -gt $lineBase.NotCacheable) (($outBase -split "`n") | Select-Object -Last 8 | Out-String)
  Check 'CC: the base closure holds uDx (include cc18on.inc defines D_ON) and not uExtra / uOpt / uIfX' `
    ((Get-FileRows $ccBase 'udx.pas') -eq 1 -and (Get-FileRows $ccBase 'uextra.pas') -eq 0 -and (Get-FileRows $ccBase 'uopt.pas') -eq 0 -and (Get-FileRows $ccBase 'uifx.pas') -eq 0) `
    "uDx=$(Get-FileRows $ccBase 'udx.pas') uExtra=$(Get-FileRows $ccBase 'uextra.pas') uOpt=$(Get-FileRows $ccBase 'uopt.pas') uIfX=$(Get-FileRows $ccBase 'uifx.pas')"
  Check 'CC: the unit whose IF asks another unit for a constant is not cacheable' ($null -ne $lineBase -and $lineBase.NotCacheable -ge 1) "$($lineBase | Out-String)"

  # Nothing changed: every stored scan answers; only the uncacheable unit is computed again.
  $dbN = Join-Path $scratch 'cc_n.sqlite'
  Copy-Db $ccBase $dbN
  $outN = Invoke-Engine @('index', '--project', $ccProj, '--db', $dbN) $PROF
  $lineN = Get-ClosureCacheLine $outN
  Check 'CC nothing changed: stored scans are reused and no cacheable unit is computed again' `
    ($null -ne $lineN -and $lineN.Reused -ge 6 -and $lineN.Computed -eq $lineN.NotCacheable) (($outN -split "`n") | Select-String 'CLOSURE CACHE' | Out-String)
  $d = Compare-Db $dbN $ccBase
  Check 'CC nothing changed: the cached run leaves the database as it was (0 diff rows)' $d.Same $d.Text

  # name; the edit (returns the undo); the unit file whose membership flips; whether it joins.
  $ccEdits = @(
    @{ Name = 'edit a NESTED include (a define two includes down switches a uses entry on)'; Unit = 'uextra.pas'; Joins = $true; Control = $true; Settle = $true
       File = 'cc18cfg2.inc'; Text = '{$DEFINE WITH_EXTRA}' },
    @{ Name = 'create a MISSING include'; Unit = 'uopt.pas'; Joins = $true
       File = 'cc18opt.inc'; Text = '{$DEFINE OPT_ON}' },
    @{ Name = 'delete an include'; Unit = 'udx.pas'; Joins = $false
       File = 'cc18on.inc'; Text = $null },
    @{ Name = 'edit a constant another unit''s IF reads (no include)'; Unit = 'uifx.pas'; Joins = $true
       File = 'uConsts.pas'; Find = 'CC_LEVEL = 1;'; Repl = 'CC_LEVEL = 2;' }
  )
  foreach ($e in $ccEdits) {
    $file = Join-Path $cc $e.File
    $keep = Join-Path $scratch ('cc_' + $e.File + '.orig')
    $had = [System.IO.File]::Exists($file)
    if ($had) { [System.IO.File]::Copy($file, $keep, $true); $stamp = [System.IO.File]::GetLastWriteTimeUtc($file) }
    try {
      if ($e.Find) { Write-Ascii $file ([System.IO.File]::ReadAllText($file).Replace($e.Find, $e.Repl)) }
      elseif ($null -eq $e.Text) { [System.IO.File]::Delete($file) }
      else { Write-Ascii $file ($e.Text + "`r`n") }

      $dbC = Join-Path $scratch 'cc_c.sqlite'; $dbU = Join-Path $scratch 'cc_u.sqlite'; $dbF = Join-Path $scratch 'cc_f.sqlite'
      Copy-Db $ccBase $dbC; Copy-Db $ccBase $dbU; Remove-Db $dbF
      $outC = Invoke-Engine @('index', '--project', $ccProj, '--db', $dbC) $PROF
      $outU = Invoke-Engine @('index', '--project', $ccProj, '--db', $dbU) $NOCACHE
      Invoke-Engine @('index', '--project', $ccProj, '--db', $dbF) $NOCACHE | Out-Null

      $want = [int][bool]$e.Joins
      $lineC = Get-ClosureCacheLine $outC
      Check "CC $($e.Name): run C reused stored scans" ($null -ne $lineC -and $lineC.Reused -gt 0) (($outC -split "`n") | Select-String 'CLOSURE CACHE' | Out-String)
      Check "CC $($e.Name): run U walked cold" ($null -eq (Get-ClosureCacheLine $outU)) ''
      Check "CC $($e.Name): the closure changed ($($e.Unit) rows: full index $want, cached $want)" `
        ((Get-FileRows $dbF $e.Unit) -eq $want -and (Get-FileRows $dbC $e.Unit) -eq $want -and (Get-FileRows $ccBase $e.Unit) -ne $want) `
        "base=$(Get-FileRows $ccBase $e.Unit) F=$(Get-FileRows $dbF $e.Unit) C=$(Get-FileRows $dbC $e.Unit)"
      $d = Compare-Db $dbC $dbU
      Check "CC $($e.Name): cached = uncached (0 diff rows)" $d.Same $d.Text
      $d = Compare-Db $dbC $dbF
      if ($e.HostGap) {
        # Not the closure's doing and the same with the cache off (C = U above), measured on
        # 1251010cd too: the INDEXER keeps the unchanged host's rows (unit_uses, pp_regions,
        # file_includes). The closure itself is right -- the membership check above reads F.
        $state = if ($d.Same) { 'now equal: drop HostGap from this edit' } else { 'still differ' }
        Write-Host "[NOTE] CC $($e.Name): cached vs full index $state -- known incremental-indexer gap ($($e.HostGap))" -ForegroundColor Yellow
      } else {
        Check "CC $($e.Name): cached = full index (0 diff rows)" $d.Same $d.Text
      }

      if ($e.Control) {
        $dbK = Join-Path $scratch 'cc_k.sqlite'
        Copy-Db $ccBase $dbK
        $outK = Invoke-Engine @('index', '--project', $ccProj, '--db', $dbK) $NOINCS
        $lineK = Get-ClosureCacheLine $outK
        Check "CC $($e.Name): POSITIVE CONTROL -- the unit-stamp-only key (test seam) reused stored scans" ($null -ne $lineK -and $lineK.Reused -gt 0) ''
        Check "CC $($e.Name): POSITIVE CONTROL -- the unit-stamp-only key leaves a STALE closure ($($e.Unit) missing)" ((Get-FileRows $dbK $e.Unit) -eq 0) "rows=$(Get-FileRows $dbK $e.Unit)"
        $d = Compare-Db $dbK $dbF
        Check "CC $($e.Name): POSITIVE CONTROL -- the unit-stamp-only key shows diff rows" (-not $d.Same -and $d.Code -eq 1) "index_db_diff exit $($d.Code): the diff cannot see a stale closure`n      $($d.Text)"
      }
      if ($e.Settle) {
        # Once the edit is older than the racy window the new scan is stored, then reused.
        Start-Sleep -Milliseconds $SETTLE_MS
        $out2 = Invoke-Engine @('index', '--project', $ccProj, '--db', $dbC) $PROF
        $out3 = Invoke-Engine @('index', '--project', $ccProj, '--db', $dbC) $PROF
        $line2 = Get-ClosureCacheLine $out2; $line3 = Get-ClosureCacheLine $out3
        Check "CC $($e.Name): the settled edit is scanned once more and stored" ($null -ne $line2 -and $line2.Computed -gt $line2.NotCacheable) (($out2 -split "`n") | Select-String 'CLOSURE CACHE' | Out-String)
        Check "CC $($e.Name): then every stored scan answers again" ($null -ne $line3 -and $line3.Computed -eq $line3.NotCacheable -and $line3.Reused -gt $lineC.Reused) (($out3 -split "`n") | Select-String 'CLOSURE CACHE' | Out-String)
        $d = Compare-Db $dbC $dbF
        Check "CC $($e.Name): the re-stored cache still equals the full index (0 diff rows)" $d.Same $d.Text
      }
    } finally {
      if ($had) { [System.IO.File]::Copy($keep, $file, $true); [System.IO.File]::SetLastWriteTimeUtc($file, $stamp) }
      elseif ([System.IO.File]::Exists($file)) { [System.IO.File]::Delete($file) }
    }
  }
} finally { Pop-Location }

# ------------------------------------------------------------------ PART 2: drag-lint's own index
if (-not $Dl) {
  Write-Host '[SKIP] PART 2 (drag-lint CLI index: timing gate + diff on real edits) -- opt-in, pass -Dl' -ForegroundColor Yellow
} else {
  $work = $DlWork
  if (-not $work) { $work = Join-Path $scratch 'dl' }
  New-Item -ItemType Directory -Force $work | Out-Null
  $tree = Join-Path $work 'tree'
  $base = Join-Path $work 'base.sqlite'
  # -DlTree + -DlBase: an existing source tree and its full index, used as they are (the caller
  # answers for the base having been built from that tree by an engine of the same fingerprint).
  if ($DlTree -and $DlBase) { $tree = $DlTree; $base = $DlBase }
  $proj = Join-Path $tree 'src\cli\drag-lint.dproj'
  $fresh = (Test-Path $base) -and (Test-Path $proj) -and
           (($DlTree -and $DlBase) -or ((Get-Item $base).LastWriteTimeUtc -gt (Get-Item $exePath).LastWriteTimeUtc))
  Push-Location C:\TEMP
  try {
    if (-not $fresh) {
      Remove-Db $base
      & robocopy (Join-Path $Repo 'src') (Join-Path $tree 'src') /MIR /XD Win32 Win64 __history __recovery _D-RAG /XF *.dcu *.exe *.bpl *.dcp *.map *.rsm *.sqlite *.sqlite-wal *.sqlite-shm *.identcache *.local /NFL /NDL /NJH /NJS /NP | Out-Null
      & robocopy (Join-Path $Repo 'third_party\delphi-tree-sitter') (Join-Path $tree 'third_party\delphi-tree-sitter') *.pas *.inc /S /NFL /NDL /NJH /NJS /NP | Out-Null
      $sw = [Diagnostics.Stopwatch]::StartNew()
      $outFull = Invoke-Engine @('index', '--project', $proj, '--platform', 'win32', '--db', $base, '--rebuild') $null
      Write-Host ("      full index of the tree copy: {0:n0} s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
      Check 'DL: full index of the tree copy' ($script:LastEngineExit -eq 0 -and $outFull -match '(?m)^Done\.') (($outFull -split "`n") | Select-Object -Last 4 | Out-String)
    }

    $stalePy = Join-Path $scratch 'stale.py'
    Write-Ascii $stalePy @'
import sqlite3, sys
db, names = sys.argv[1], sys.argv[2:]
c = sqlite3.connect(db)
c.execute('PRAGMA journal_mode=WAL')
hit = 0
cols = [r[1] for r in c.execute('PRAGMA table_info(files)')]
for n in names:
    key = ('%' + chr(92) + n.lower(),)
    hit += c.execute("UPDATE files SET sha256='forced' WHERE lower(path) LIKE ?", key).rowcount
    if 'size' in cols:
        c.execute("UPDATE files SET size = NULL WHERE lower(path) LIKE ?", key)
c.execute("INSERT OR REPLACE INTO schema_meta(key, value) VALUES ('perf_warmup', '1')")
c.commit()
c.execute("DELETE FROM schema_meta WHERE key = 'perf_warmup'")
c.commit()
c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
c.close()
print(hit)
'@

    # ---- timing gate: one file forced stale, median of 3 ----
    $walls = @()
    foreach ($i in 1..3) {
      $dbT = Join-Path $work 't.sqlite'
      Copy-Db $base $dbT
      $hit = & $pyExe @pyPre $stalePy $dbT 'DRagLint.CLI.Hover.pas'
      $load = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
      $sw = [Diagnostics.Stopwatch]::StartNew()
      $outT = Invoke-Engine @('index', '--project', $proj, '--platform', 'win32', '--db', $dbT) @{ DRAGLINT_PROFILE = '1' }
      $sw.Stop()
      $walls += [math]::Round($sw.Elapsed.TotalSeconds, 1)
      $stages = ([regex]::Matches($outT, '(?m)^stage: (\S+) -- done in ([0-9.]+)s') | ForEach-Object { '{0}={1}' -f $_.Groups[1].Value, $_.Groups[2].Value }) -join ' '
      Write-Host ("      one-file run {0}: {1} s (CPU load before: {2}%, forced {3})  {4}" -f $i, $walls[-1], [int]$load, $hit, $stages) -ForegroundColor DarkGray
      if ($i -eq 1) {
        Check 'DL: the one-file run re-parsed one file and took the SCOPED path' ($outT -match 'starting SCOPED pass over 1 changed file') (($outT -split "`n") | Select-String 'calls |re-parsing' | Select-Object -First 4 | Out-String)
        # Deterministic, unlike the wall time: the leaf's 24 local / parameter names stay out of the scope.
        Check 'DL: the one-file run left the local / parameter names out of the name scope' ($outT -match $LEFT_OUT) (($outT -split "`n") | Select-String 'calls ' | Select-Object -First 6 | Out-String)
        $aff = 0; if ($outT -match 'from (\d+) affected call-site ref\(s\)') { $aff = [int]$Matches[1] }
        Write-Host "      affected call-site refs: $aff" -ForegroundColor DarkGray
      }
    }
    $median = ($walls | Sort-Object)[1]
    Check ("DL TIMING GATE: one-file incremental index, median of 3 = {0} s <= {1} s  (runs: {2})" -f $median, $MaxSeconds, ($walls -join ', ')) ($median -le $MaxSeconds) 'see the per-run stage lines above; a loaded machine inflates this -- rerun idle before reading it as a regression'

    # ---- S = W on real edits of the tree copy ----
    $dlEdits = @{
      local = @{ File = 'src\cli\DRagLint.CLI.Hover.pas'; Find = '\bFmt\b'; Repl = 'FmtRenamed' }
      param = @{ File = 'src\cli\DRagLint.CLI.Hover.pas'; Find = 'function DoContrastSelfTest: Integer;'; Repl = 'function DoContrastSelfTest(AUnused: Integer = 0): Integer;'; Literal = $true }
      decl  = @{ File = 'src\analysis\DRagLint.Analysis.Cfg.pas'; Find = 'function IsValuedExit\('; Repl = 'function IsValuedExit(const AExtra: Integer; ' }
      enum  = @{ File = 'src\refactor\DRagLint.Refactor.TextEdit.pas'; Find = 'TTextEditKind = (tekInsertInLine,'; Repl = 'TTextEditKind = (tekIncr18Added, tekInsertInLine,'; Literal = $true }
    }
    foreach ($name in $DlScenarios) {
      $e = $dlEdits[$name]
      if (-not $e) { Check "DL $name`: a known scenario" $false "one of: $($dlEdits.Keys -join ', ')"; continue }
      $file = Join-Path $tree $e.File
      $keep = Join-Path $scratch 'dl_edit.orig'
      [System.IO.File]::Copy($file, $keep, $true)
      $text = [System.IO.File]::ReadAllText($file)
      if ($e.Literal) { $new = $text.Replace($e.Find, $e.Repl) }
      elseif ($e.First) { $new = ([regex]$e.Find).Replace($text, $e.Repl, 1) }
      else { $new = [regex]::Replace($text, $e.Find, $e.Repl) }
      if ($new -ceq $text) { Check "DL $name`: the edit applies" $false "pattern '$($e.Find)' not in $($e.File)"; continue }
      try {
        [System.IO.File]::WriteAllText($file, $new, (New-Object System.Text.UTF8Encoding($false)))
        $dbS = Join-Path $work 's.sqlite'; $dbW = Join-Path $work 'w.sqlite'
        Copy-Db $base $dbS; Copy-Db $base $dbW
        $outS = Invoke-Engine @('index', '--project', $proj, '--platform', 'win32', '--db', $dbS) $null
        $outW = Invoke-Engine @('index', '--project', $proj, '--platform', 'win32', '--db', $dbW) $WHOLE
        Check "DL $name`: run S took the SCOPED path" ($outS -match 'starting SCOPED pass') (($outS -split "`n") | Select-String 'calls ' | Select-Object -First 4 | Out-String)
        Check "DL $name`: run W took the WHOLE-DB path" ($outW -match 'starting WHOLE-DB pass') ''
        $dlScope = (($outS -split "`n") | Select-String 'resolve: purity scope' | Select-Object -First 1 | Out-String).Trim()
        Check "DL $name`: run S re-derived a purity scope, run W every routine [$dlScope]" ($outS -match 'resolve: purity scope -- \d+ of \d+ routine\(s\) re-derived' -and $outW -notmatch 'resolve: purity scope -- \d+ of') (($outS -split "`n") | Select-String 'purity' | Out-String)
        $d = Compare-Db $dbS $dbW
        Check "DL $name`: scoped = whole-database resolve (0 diff rows)" $d.Same $d.Text
      } finally {
        [System.IO.File]::Copy($keep, $file, $true)
      }
    }
    foreach ($n in 't', 's', 'w') { Remove-Db (Join-Path $work "$n.sqlite") }
  } finally { Pop-Location }
}

if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  Remove-Item Env:\DRAGLINT_RULE_CACHE -ErrorAction SilentlyContinue
  if ((-not $KeepScratch) -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
