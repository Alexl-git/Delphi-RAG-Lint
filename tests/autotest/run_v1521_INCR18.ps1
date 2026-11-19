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
      enum  = @{ File = 'src\analysis\DRagLint.Analysis.Cfg.pas'; Find = '(?m)^(\s+T\w+\s*=\s*\()(\w+)'; Repl = '${1}incr18Added, ${2}'; First = $true }
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
