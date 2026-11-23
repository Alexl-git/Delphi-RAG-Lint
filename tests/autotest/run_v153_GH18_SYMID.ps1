<#
  run_v153_GH18_SYMID.ps1 -- GitHub #18 slice 2 (1.53.0): symbol-id reuse on an incremental
  index. Spec docs\superpowers\specs\2026-11-20-gh18-calls-design.md (acceptance A1-A10), plan
  docs\superpowers\plans\2026-11-20-gh18-symid.md (Task 2).

  A 16-unit fixture, one edit per scenario. For each edit three databases are built from the
  same edited tree --
      R  base + incremental, symbol-id REUSE            (the shipped path)
      N  base + incremental, DRAGLINT_NO_SYMBOL_ID_REUSE (1.52 delete + insert, same binary)
      F  a fresh full index
  -- and tools\measure\index_db_diff.py must report R = N and R = F (0 differing rows, A4).

  ID STABILITY (A1): Python compares the edited file's rows of base and R by identity key
  (kind, lower(qualified_name), signature unless a property, occurrence). On a position-only,
  body-only or hub body-only edit 100 % of the ids must be kept, and the calls-stage line
  "symbol-id reuse: K kept, 0 changed, 0 added, 0 removed ...; 0 name(s) in the name scope"
  must say no name of the file entered the scope.

  HATCH (A8): the blank-line edit with DRAGLINT_NO_SYMBOL_ID_REUSE=1 keeps 0 % of the ids.

  POSITIVE CONTROL (A5, load-bearing): the test seam DRAGLINT_TEST_SYMID_NO_FP=1 treats every
  claimed row as unchanged -- a deliberately WRONG scope. On the fingerprint-only edits (a
  property's type, a class's ancestor) that must show diff rows against N, else index_db_diff
  could not see a stale binding and every "0 rows" above would prove nothing.

  RED (before 1.53.0): no reuse line in the log and 0 % of the ids kept.
  Run from a neutral CWD (C:\TEMP), pwsh 7. Needs Python 3 (py or python).
#>
[CmdletBinding()]
param(
  [string]$Exe = '',
  [string[]]$Only = @(),
  [switch]$KeepScratch
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$scratch = Join-Path C:\TEMP "draglint_symid_$PID"
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$diffPy  = Join-Path $Repo 'tools\measure\index_db_diff.py'
$pyExe = 'python'; $pyPre = @('-I')
if (Get-Command py -ErrorAction SilentlyContinue) { $pyExe = 'py'; $pyPre = @('-I') }

if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$env:DRAGLINT_RULE_CACHE = '0'

function Write-Ascii($p, $t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))
}
function Remove-Db($db) { foreach ($s in '', '-wal', '-shm') { if (Test-Path -LiteralPath "$db$s") { [System.IO.File]::Delete("$db$s") } } }
function Copy-Db($from, $to) { Remove-Db $to; [System.IO.File]::Copy($from, $to, $true) }

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

# index_db_diff: exit 0 = identical, 1 = differences, 2 (or anything else) = could not compare (RED).
function Compare-Db($a, $b) {
  $out = & { $ErrorActionPreference = 'Continue'; & $pyExe @pyPre $diffPy $a $b 2>&1 | ForEach-Object { "$_" } }
  $code = $LASTEXITCODE
  if ($code -ne 0 -and $code -ne 1) { $out = @("index_db_diff exit $code -- NOT a comparison") + $out }
  $tell = @($out | Where-Object { $_ -match 'DIFF|only A|only B|^\s+[AB] |TABLE ONLY|FILE ONLY|index_db_diff|Traceback|Error' } | Select-Object -First 16)
  if ($tell.Count -eq 0) { $tell = @($out | Select-Object -Last 6) }
  $rows = @($out | Where-Object { $_ -match '^\s+[AB] \(' } | ForEach-Object { $_.Trim() })
  return @{ Same = ($code -eq 0); Code = $code; Text = ($tell -join "`n      "); Rows = $rows }
}

# Id stability of one file between two databases, by identity key.
$idPy = Join-Path $scratch 'idkeep.py'
[System.IO.File]::WriteAllText($idPy, @'
import sqlite3, sys
def keyed(db, suffix):
    c = sqlite3.connect('file:' + db + '?mode=ro', uri=True)
    rows = c.execute("select s.id, s.kind, lower(s.qualified_name), coalesce(s.signature,'') from symbols s "
                     "join files f on f.id = s.file_id where lower(f.path) like ? order by s.id",
                     ('%' + suffix.lower(),)).fetchall()
    occ, out = {}, {}
    for i, k, q, sg in rows:
        t = (k, q, '' if k == 'property' else sg)
        n = occ.get(t, 0); occ[t] = n + 1
        out[t + (n,)] = i
    return out
a = keyed(sys.argv[1], sys.argv[3]); b = keyed(sys.argv[2], sys.argv[3])
same = sum(1 for k, v in a.items() if b.get(k) == v)
both = sum(1 for k in a if k in b)
print('kept=%d both=%d base=%d after=%d' % (same, both, len(a), len(b)))
'@, (New-Object System.Text.ASCIIEncoding))
function Get-IdKeep($a, $b, $file) {
  $o = & $pyExe @pyPre $idPy $a $b $file
  if ("$o" -match 'kept=(\d+) both=(\d+) base=(\d+) after=(\d+)') {
    return @{ Kept = [int]$Matches[1]; Both = [int]$Matches[2]; Base = [int]$Matches[3]; After = [int]$Matches[4]; Text = "$o" }
  }
  return @{ Kept = -1; Both = -1; Base = -1; After = -1; Text = "$o" }
}

$HATCH = @{ DRAGLINT_NO_SYMBOL_ID_REUSE = '1' }
$NOFP  = @{ DRAGLINT_TEST_SYMID_NO_FP = '1' }
$REUSE_RX = 'symbol-id reuse: (\d+) kept, (\d+) changed, (\d+) added, (\d+) removed in (\d+) file\(s\); (\d+) name\(s\) in the name scope'

# ------------------------------------------------------------------ fixture
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

Write-Ascii (Join-Path $src 'uUtil.pas') @'
unit uUtil;

interface

type
  TMode = (mdOne, mdTwo);

  TData = class
  public
    procedure Show;
  end;

  TOther = class
  public
    procedure Show;
    procedure Other;
  end;

  TBase = class
  public
    procedure Ping; virtual;
  end;

  THolder = class
  private
    FA: TData;
    function GetA: TData;
  public
    Field: TData;
    property A: TData read FA;
    property P: TData read FA;
  end;

function Helper(AValue: Integer): Integer;
function Shared(AValue: Integer): Integer;
function Over(AValue: Integer): Integer; overload;
function Over(const AValue: string): Integer; overload;
function Doomed(AValue: Integer): Integer;

implementation

procedure TData.Show;
begin
end;

procedure TOther.Show;
begin
end;

procedure TOther.Other;
begin
end;

procedure TBase.Ping;
begin
end;

function THolder.GetA: TData;
begin
  Result := FA;
end;

function Helper(AValue: Integer): Integer;
begin
  Result := AValue * 2;
end;

function Shared(AValue: Integer): Integer;
begin
  Result := Helper(AValue) + 1;
end;

function Over(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function Over(const AValue: string): Integer;
begin
  Result := Length(AValue);
end;

function Doomed(AValue: Integer): Integer;
begin
  Result := AValue - 1;
end;

end.
'@

Write-Ascii (Join-Path $src 'uKid.pas') @'
unit uKid;

interface

uses
  uUtil;

type
  TKid = class(TBase)
  public
    procedure Extra;
  end;

  TGone = class
  public
    procedure Bye;
  end;

implementation

procedure TKid.Extra;
begin
end;

procedure TGone.Bye;
begin
end;

end.
'@

Write-Ascii (Join-Path $src 'uUser.pas') @'
unit uUser;

interface

uses
  uUtil, uKid;

function UseAll(AValue: Integer): Integer;

implementation

function UseAll(AValue: Integer): Integer;
var
  H: THolder;
  K: TKid;
  G: TGone;
begin
  H := THolder.Create;
  K := TKid.Create;
  G := TGone.Create;
  H.Field.Show;
  H.A.Show;
  H.P.Show;
  K.Ping;
  G.Bye;
  Result := Helper(AValue) + Shared(AValue) + Over(AValue) + Doomed(AValue) + Ord(mdTwo);
end;

end.
'@

Write-Ascii (Join-Path $src 'uLeaf.pas') @'
unit uLeaf;

interface

uses
  uUtil;

function LeafCalc(AValue: Integer): Integer;

implementation

function LeafCalc(AValue: Integer): Integer;
var
  Total: Integer;
begin
  Total := Shared(AValue);
  Result := Total + Ord(mdOne);
end;

end.
'@

Write-Ascii (Join-Path $src 'uLeafUser.pas') @'
unit uLeafUser;

interface

uses
  uLeaf;

function TwiceLeaf(AValue: Integer): Integer;

implementation

function TwiceLeaf(AValue: Integer): Integer;
begin
  Result := LeafCalc(AValue) + LeafCalc(AValue + 1);
end;

end.
'@

Write-Ascii (Join-Path $src 'uDesc.pas') @'
unit uDesc;

interface

uses
  uUtil;

type
  TDesc = class(THolder)
  public
    property A;
  end;

function DescShow(D: TDesc): Integer;

implementation

function DescShow(D: TDesc): Integer;
begin
  D.A.Show;
  Result := 0;
end;

end.
'@

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
  Result := Helper(AValue) + Shared($n);
end;

end.
"@
}

# Indexed LAST, so no edited file owns the highest ids: SQLite re-issues a deleted max rowid, and a
# hub indexed last kept its ids even on the 1.52 delete + insert (an id check that cannot fail).
Write-Ascii (Join-Path $src 'uZLast.pas') @"
unit uZLast;

interface

function ZLast: Integer;

implementation

function ZLast: Integer;
begin
  Result := 0;
end;

end.
"@

# Id, File, Edits (@(find, replace) pairs), KeepAll (assert 100 % ids kept + nothing in scope),
# Hatch (assert 0 % kept), Control (seam must show diff rows).
$scenarios = @(
  @{ Id = 'S1';  Name = 'blank line at the top of a leaf unit';           File = 'uLeaf.pas'; Edits = @(,@('unit uLeaf;', "`r`nunit uLeaf;")); KeepAll = $true },
  @{ Id = 'S2';  Name = 'body-only edit of a routine another unit calls'; File = 'uLeaf.pas'; Edits = @(,@('Result := Total + Ord(mdOne);', 'Result := Total + Ord(mdOne) + 0;')); KeepAll = $true },
  @{ Id = 'S3';  Name = 'overload inserted before a called overload';     File = 'uUtil.pas'; Edits = @(@('function Over(AValue: Integer): Integer; overload;', "function Over(AValue: Double): Integer; overload;`r`nfunction Over(AValue: Integer): Integer; overload;"), @("function Over(AValue: Integer): Integer;`r`nbegin", "function Over(AValue: Double): Integer;`r`nbegin`r`n  Result := 0;`r`nend;`r`n`r`nfunction Over(AValue: Integer): Integer;`r`nbegin")) },
  @{ Id = 'S4';  Name = 'parameter type change of a called routine';      File = 'uUtil.pas'; Edits = @(,@('function Helper(AValue: Integer): Integer;', 'function Helper(AValue: Int64): Integer;')) },
  @{ Id = 'S5';  Name = 'field type change under X.Field.Method';         File = 'uUtil.pas'; Edits = @(,@('    Field: TData;', '    Field: TOther;')) },
  @{ Id = 'S6';  Name = 'property accessor renamed';                      File = 'uUtil.pas'; Edits = @(,@('property A: TData read FA;', 'property A: TData read GetA;')) },
  @{ Id = 'S6b'; Name = 'property type change under X.P.Method';          File = 'uUtil.pas'; Edits = @(,@('property P: TData read FA;', 'property P: TOther read FA;')); Control = $true },
  @{ Id = 'S7';  Name = 'routine renamed that other units call';          File = 'uUtil.pas'; Edits = @(,@('Doomed', 'Doomed2')) },
  @{ Id = 'S8';  Name = 'type withdrawn';                                 File = 'uKid.pas';  Edits = @(@("  TGone = class`r`n  public`r`n    procedure Bye;`r`n  end;`r`n", ''), @("procedure TGone.Bye;`r`nbegin`r`nend;`r`n", '')) },
  @{ Id = 'S9';  Name = 'type added with an ancestor in another unit';    File = 'uKid.pas';  Edits = @(,@("  TGone = class", "  TKid2 = class(TBase)`r`n  end;`r`n`r`n  TGone = class")) },
  @{ Id = 'S10a'; Name = 'edit of an include host';                       File = 'uHost.pas'; Edits = @(,@('Shared := AValue;', 'Shared := AValue + 0;')) },
  @{ Id = 'S10b'; Name = 'edit of the include';                           File = 'uBody.inc'; Edits = @(,@('Helper(AValue);', 'Helper(AValue) + 0;')) },
  @{ Id = 'S11'; Name = 'blank line over a redeclared property Foo;';     File = 'uDesc.pas'; Edits = @(,@('unit uDesc;', "`r`nunit uDesc;")) },
  @{ Id = 'S12'; Name = 'enum value added';                               File = 'uUtil.pas'; Edits = @(,@('(mdOne, mdTwo)', '(mdOne, mdTwo, mdThree)')) },
  @{ Id = 'S13'; Name = 'routine deleted whose callers stay';             File = 'uUtil.pas'; Edits = @(@("function Doomed(AValue: Integer): Integer;`r`n`r`n", "`r`n"), @("function Doomed(AValue: Integer): Integer;`r`nbegin`r`n  Result := AValue - 1;`r`nend;`r`n", '')) },
  @{ Id = 'S14'; Name = 'hub body-only edit';                             File = 'uUtil.pas'; Edits = @(,@('Result := AValue * 2;', 'Result := AValue * 3;')); KeepAll = $true },
  @{ Id = 'S15'; Name = 'class ancestor changed under K.Method';          File = 'uKid.pas';  Edits = @(,@('TKid = class(TBase)', 'TKid = class(TOther)')); Control = $true },
  @{ Id = 'HATCH'; Name = 'blank line, DRAGLINT_NO_SYMBOL_ID_REUSE=1';    File = 'uLeaf.pas'; Edits = @(,@('unit uLeaf;', "`r`nunit uLeaf;")); Hatch = $true }
)
$allScenarios = $scenarios
if ($Only.Count -gt 0) { $scenarios = @($scenarios | Where-Object { $Only -contains $_.Id }) }

$controlsShowingDiff = 0; $controlsRun = 0; $known152 = @()
Push-Location C:\TEMP
try {
  $dbBase = Join-Path $scratch 'base.sqlite'
  Invoke-Engine @('index', $src, '--db', $dbBase) $null | Out-Null
  $cnt = Invoke-Engine @('sql', '--query', 'SELECT count(*) AS n FROM call_edges', '--db', $dbBase, '--json') $null
  $baseEdges = 0; if ($cnt -match '"rows"\s*:\s*\[\s*\[\s*(\d+)') { $baseEdges = [int]$Matches[1] }
  Check 'SANITY: the fixture base index holds call edges (an empty A/B proves nothing)' ($baseEdges -ge 15) "edges=$baseEdges"

  foreach ($sc in $scenarios) {
    $tag = "$($sc.Id) $($sc.Name)"
    $file = Join-Path $src $sc.File
    $keep = Join-Path $scratch ($sc.File + '.orig')
    [System.IO.File]::Copy($file, $keep, $true)
    $text = [System.IO.File]::ReadAllText($file)
    $applies = $true
    foreach ($e in $sc.Edits) {
      if (-not $text.Contains($e[0])) { $applies = $false; Check "${tag}: the edit applies" $false "no '$($e[0])' in $($sc.File)"; break }
      $text = $text.Replace($e[0], $e[1])
    }
    if (-not $applies) { continue }
    Write-Ascii $file $text

    $dbR = Join-Path $scratch 'r.sqlite'; $dbN = Join-Path $scratch 'n.sqlite'; $dbF = Join-Path $scratch 'f.sqlite'
    Copy-Db $dbBase $dbR; Copy-Db $dbBase $dbN; Remove-Db $dbF
    $outR = Invoke-Engine @('index', $src, '--db', $dbR) $(if ($sc.Hatch) { $HATCH } else { $null })
    $outN = Invoke-Engine @('index', $src, '--db', $dbN) $HATCH
    Invoke-Engine @('index', $src, '--db', $dbF) $null | Out-Null

    Check "${tag}: run R took the SCOPED path" ($outR -match 'starting SCOPED pass') ($outR -split "`n" | Select-String 'calls ' | Select-Object -First 4 | Out-String)
    $dRN = Compare-Db $dbR $dbN
    $dRF = Compare-Db $dbR $dbF
    $dNF = Compare-Db $dbN $dbF
    if ($dNF.Same) {
      Check "${tag}: reuse = 1.52 delete + insert (0 diff rows)" $dRN.Same $dRN.Text
      Check "${tag}: reuse incremental = full reindex (0 diff rows)" $dRF.Same $dRF.Text
    } else {
      # A pre-existing incremental != fresh difference: the 1.52 path (N) differs from a full
      # reindex too, so R = N is not the right gate. It is reported, and reuse must be NO WORSE:
      # every row R differs from F by is a row N differs from F by.
      $script:known152 += $sc.Id
      Write-Host "[KNOWN] ${tag}: incremental != full reindex on the 1.52 path too (N != F) -- pre-existing, reported" -ForegroundColor Yellow
      Write-Host "      N vs F: $($dNF.Text)" -ForegroundColor DarkGray
      $extra = @($dRF.Rows | Where-Object { $dNF.Rows -notcontains $_ })
      Check "${tag}: reuse is no worse than 1.52 against a full reindex (R-F rows within N-F rows; $($dRF.Rows.Count) vs $($dNF.Rows.Count))" (($dRF.Code -eq 0 -or $dRF.Code -eq 1) -and $extra.Count -eq 0) ($extra -join "`n      ")
    }

    $k = Get-IdKeep $dbBase $dbR $sc.File
    $line = ($outR -split "`n" | Select-String 'symbol-id reuse:' | Select-Object -First 1)
    Write-Host ("      ids: {0}   log: {1}" -f $k.Text, $(if ($line) { "$line".Trim() } else { '(no reuse line)' })) -ForegroundColor DarkGray
    if ($sc.KeepAll) {
      Check "${tag}: A1 every symbol id of the file kept" (($k.Base -gt 0) -and ($k.Kept -eq $k.Base) -and ($k.After -eq $k.Base)) $k.Text
      $ok = $false
      if ($outR -match $REUSE_RX) { $ok = ([int]$Matches[2] -eq 0) -and ([int]$Matches[3] -eq 0) -and ([int]$Matches[4] -eq 0) -and ([int]$Matches[6] -eq 0) }
      Check "${tag}: A9 shape -- 0 changed / added / removed, 0 names in the name scope" $ok "$line"
    }
    if ($sc.Hatch) {
      Check "${tag}: A8 the hatch keeps no id (delete + insert)" (($k.Base -gt 0) -and ($k.Kept -eq 0)) $k.Text
      Check "${tag}: A8 the hatch prints no reuse line" ($outR -notmatch 'symbol-id reuse:') "$line"
    }
    if ($sc.Control) {
      $controlsRun++
      $dbC = Join-Path $scratch 'c.sqlite'
      Copy-Db $dbBase $dbC
      $outC = Invoke-Engine @('index', $src, '--db', $dbC) $NOFP
      $dc = Compare-Db $dbC $dbN
      Write-Host ("      control (seam): index_db_diff exit {0}" -f $dc.Code) -ForegroundColor DarkGray
      if ($dc.Code -eq 1) { $controlsShowingDiff++ }
      if ($dc.Code -ne 0 -and $dc.Code -ne 1) { Check "${tag}: POSITIVE CONTROL compared" $false $dc.Text }
    }
    [System.IO.File]::Copy($keep, $file, $true)
  }

  # CHAIN: several incremental runs on ONE reused database -- each claims against ids the previous
  # run reused, so an ordering or snapshot error compounds here and nowhere above.
  if ($Only.Count -eq 0 -or $Only -contains 'CHAIN') {
    $dbK = Join-Path $scratch 'k.sqlite'; $dbF = Join-Path $scratch 'f.sqlite'
    Copy-Db $dbBase $dbK
    $orig = @{}
    foreach ($id in 'S3', 'S6', 'S9', 'S12', 'S13', 'S14', 'REVERT') {
      if ($id -eq 'REVERT') { foreach ($k in $orig.Keys) { [System.IO.File]::WriteAllText($k, $orig[$k]) } }
      else {
        $sc = $allScenarios | Where-Object { $_.Id -eq $id }
        $file = Join-Path $src $sc.File; $text = [System.IO.File]::ReadAllText($file)
        if (-not $orig.ContainsKey($file)) { $orig[$file] = $text }
        foreach ($e in $sc.Edits) { if (-not $text.Contains($e[0])) { Check "CHAIN ${id}: the edit applies" $false $e[0] }; $text = $text.Replace($e[0], $e[1]) }
        Write-Ascii $file $text
      }
      $outK = Invoke-Engine @('index', $src, '--db', $dbK) $null
      Remove-Db $dbF; Invoke-Engine @('index', $src, '--db', $dbF) $null | Out-Null
      $d = Compare-Db $dbK $dbF
      Check "CHAIN after ${id}: cumulative reuse = full reindex (0 diff rows)" $d.Same $d.Text
    }
  }
} finally { Pop-Location }

if ($known152.Count -gt 0) { Write-Host ("KNOWN 1.52 incremental != fresh (not gated here): " + ($known152 -join ', ')) -ForegroundColor Yellow }
if ($controlsRun -gt 0) {
  Check "POSITIVE CONTROL (A5): the NO_FP seam shows diff rows on at least one fingerprint-only edit ($controlsShowingDiff of $controlsRun)" ($controlsShowingDiff -ge 1) 'seam not honoured, or index_db_diff cannot see a stale binding'
}

} finally {
  if (-not $KeepScratch -and (Test-Path $scratch)) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($fail) { Write-Host 'RESULT: FAIL'; exit 1 } else { Write-Host 'RESULT: PASS'; exit 0 }
