<#
  run_schema_read_compat.ps1 -- 150 SC: an engine reads an index in [SCHEMA_READ_MIN, SCHEMA_VERSION]
  with full function, and refuses one below SCHEMA_READ_MIN with a named reason -- never an AV.

  Spec: docs\superpowers\specs\2026-11-09-schema-read-compat.md.
  Origin (149 INT, LEDGER 08:11:40): SCHEMA_VERSION 24 + a library at 23 made every
  `index --library-db` die (EAccessViolation, TLibraryOracle -> FindSymbolsByExactName on a nil
  prepared query); 556ad9d7e then SKIPPED the library, so every bind ran without it.

  The engine's range is read from `schema --format json` (engine_schema_version /
  engine_schema_read_min). An exe without those keys (pre-150) is taken as READ_MIN = its schema.

  Fixture (temp dir): library LibU (TLibBase, TLibThing = class(TLibBase) with Run) indexed by -Exe;
  project App.dpr / AppU.pas calling TLibThing.Create / Run / Free and testing
  {$IF Declared(TLibThing)}.
  Arm R (read-compat): the library and a project index are stamped DOWN to READ_MIN and the three
  schema-24 file-fact tables are dropped (= a real index built by a READ_MIN engine).
    R1 index --project --library-db <lib@READ_MIN>: exit 0, '+ library-db', no 'skipped', no AV
    R2 ... and the call to TLibThing.Run binds INTO the library (refs.external_target) -- the
       function, not just the absence of a crash (positive: 0 when the library is skipped)
    R3 lint-all --library-db (pp-unresolved-if: PPUnitSource opener): exit 0/1, no AV
    R4 lint-tree --unit AppU.pas --db <proj@READ_MIN>: exit <> 2, no refusal, no AV
    R5 uses-recover --db <proj@READ_MIN> --library-db <lib@READ_MIN>: no 'cannot read index', no AV
    R6 query --name Go --db <proj@READ_MIN>: answers (AppU.Go), no 'index schema v' refusal
    R7 schema --db <lib@READ_MIN>: schema_readable = true
  When the engine is AT READ_MIN (SCHEMA_VERSION = SCHEMA_READ_MIN, the 150 lane state) arm R
  runs at the current schema and says so ('R: engine at READ_MIN'); it bites once INT flips 24.
  Arm U (unreadable): copies stamped to READ_MIN - 1.
    U1 index --library-db <lib@MIN-1>: exit 0, 'library-db skipped' + 'older than this engine reads', no AV
    U2 query --db <proj@MIN-1>: 'index schema v<MIN-1> <' refusal, no AV
    U3 lint-tree --db <proj@MIN-1>: exit 2 + 'older than this engine reads', no AV
    U4 uses-recover --db <proj@MIN-1>: 'older than this engine reads', no AV
    U5 schema --db <lib@MIN-1>: schema_readable = false (skipped on a pre-150 exe)
  POSITIVE CONTROL (recorded in lanes\150\SC\REPORT.md): the base 1.49 build with
  SCHEMA_VERSION set to 24 fails R1/R2 (library skipped -> 0 external binds) -- the guard can fail.
  Needs python (stdlib sqlite3) to stamp; missing python = FATAL, never a skip.

  Usage: pwsh -File tests\autotest\run_schema_read_compat.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { Write-Host 'FATAL: python not found (needed to stamp an old schema_version)'; exit 2 }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("schemarc-" + [Guid]::NewGuid().ToString('N'))
$libDir = Join-Path $tmp 'lib'
$appDir = Join-Path $tmp 'app'
$hppDir = Join-Path $tmp 'hpp'
foreach ($d in @($libDir, $appDir, $hppDir)) { [IO.Directory]::CreateDirectory($d) | Out-Null }
$script:Failed = $false

function Src-Check([string]$Id, [bool]$Ok, [string]$What) {
  if ($Ok) { Write-Host "PASS $Id $What" } else { Write-Host "FAIL $Id $What"; $script:Failed = $true }
}
function Src-Write([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, (($Text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Src-Run([string[]]$CliArgs) {
  $o = & $exePath @CliArgs 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Src-NoAv([string]$Text) { return -not ($Text -match 'AccessViolation|Access violation') }

try {
  Src-Write (Join-Path $libDir 'LibU.pas') @'
unit LibU;

interface

type
  TLibBase = class
  public
    procedure Base;
  end;

  TLibThing = class(TLibBase)
  public
    procedure Run;
  end;

implementation

procedure TLibBase.Base;
begin
end;

procedure TLibThing.Run;
begin
end;

end.
'@
  Src-Write (Join-Path $appDir 'AppU.pas') @'
unit AppU;

interface

procedure Go;

implementation

uses LibU;

procedure Go;
var
  T: TLibThing;
begin
  T:= TLibThing.Create;
  T.Run;
  T.Free;
{$IF Declared(TLibThing)}
  T:= nil;
{$IFEND}
end;

end.
'@
  Src-Write (Join-Path $appDir 'App.dpr') @'
program App;

uses
  AppU in 'AppU.pas';

begin
  Go;
end.
'@
  $lib = Join-Path $tmp 'lib.sqlite'
  $r = Src-Run @('index', $libDir, '--db', $lib)
  if ($r.Code -ne 0) { throw "library index exit $($r.Code)`n$($r.Out)" }
  $proj = Join-Path $tmp 'proj.sqlite'
  $r = Src-Run @('index', '--project', (Join-Path $appDir 'App.dpr'), '--db', $proj, '--library-db', $lib)
  if ($r.Code -ne 0) { throw "project index exit $($r.Code)`n$($r.Out)" }

  # The engine's range.
  $sj = (Src-Run @('schema', '--db', $lib, '--format', 'json')).Out
  $sj = $sj.Substring($sj.IndexOf('{'))
  $schema = $sj | ConvertFrom-Json
  $engine = if ($null -ne $schema.engine_schema_version) { [int]$schema.engine_schema_version } else { [int]$schema.schema_version }
  $readMin = if ($null -ne $schema.engine_schema_read_min) { [int]$schema.engine_schema_read_min } else { $engine }
  $hasKeys = $null -ne $schema.engine_schema_read_min
  Write-Host "engine schema v$engine, reads v$readMin..v$engine (keys present: $hasKeys)"
  if ($engine -eq $readMin) { Write-Host 'R: engine at READ_MIN -- arm R runs at the current schema (bites after the 24 flip)' }

  $stamp = Join-Path $tmp 'stamp.py'
  [IO.File]::WriteAllText($stamp, @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("UPDATE schema_meta SET value = ? WHERE key = 'schema_version'", (sys.argv[2],))
for t in ("file_includes", "dfm_objects", "pp_regions"):
    c.execute("DROP TABLE IF EXISTS " + t)
c.commit()
c.close()
'@)
  function Src-StampCopy([string]$Src, [string]$Dst, [int]$Ver) {
    [IO.File]::Copy($Src, $Dst, $true)
    & $py -I $stamp $Dst "$Ver"
    if ($LASTEXITCODE -ne 0) { throw "stamp $Dst v$Ver failed" }
  }

  # ---- arm R: READ_MIN ------------------------------------------------------------------
  $libR = Join-Path $tmp 'lib-r.sqlite'; Src-StampCopy $lib $libR $readMin
  $projR = Join-Path $tmp 'proj-r.sqlite'; Src-StampCopy $proj $projR $readMin
  $r1db = Join-Path $tmp 'r1.sqlite'
  $r = Src-Run @('index', '--project', (Join-Path $appDir 'App.dpr'), '--db', $r1db, '--library-db', $libR)
  Src-Check 'R1' (($r.Code -eq 0) -and ($r.Out -match '\+ library-db') -and -not ($r.Out -match 'library-db skipped') -and (Src-NoAv $r.Out)) "index --library-db <lib@v$readMin> attaches it (exit $($r.Code))"
  if ($script:Failed) { ($r.Out -split "`n" | Select-Object -Last 6) | ForEach-Object { Write-Host "  | $_" } }
  $q = Src-Run @('sql', '--query', "SELECT COUNT(*) AS n FROM refs WHERE external_target LIKE '%TLibThing.Run%'", '--db', $r1db, '--json')
  $n = -1
  try { $qj = $q.Out.Substring($q.Out.IndexOf('{')) | ConvertFrom-Json; $n = [int]$qj.rows[0][0] } catch { $n = -1 }
  Src-Check 'R2' ($n -gt 0) "the call T.Run binds into the library (external_target rows=$n)"

  $r = Src-Run @('lint-all', '--db', $r1db, '--library-db', $libR, '--rule', 'pp-unresolved-if')
  Src-Check 'R3' ((($r.Code -eq 0) -or ($r.Code -eq 1)) -and (Src-NoAv $r.Out)) "lint-all --library-db <lib@v$readMin> pp-unresolved-if: exit $($r.Code), no AV"

  $r = Src-Run @('lint-tree', '--unit', (Join-Path $appDir 'AppU.pas'), '--db', $projR)
  Src-Check 'R4' (($r.Code -ne 2) -and -not ($r.Out -match 'older than this engine reads') -and (Src-NoAv $r.Out)) "lint-tree --db <proj@v$readMin>: exit $($r.Code)"

  $r = Src-Run @('uses-recover', '--db', $projR, '--hpp-dir', $hppDir, '--library-db', $libR)
  Src-Check 'R5' (-not ($r.Out -match 'cannot read index') -and (Src-NoAv $r.Out)) "uses-recover --db <proj@v$readMin>: exit $($r.Code), reads it"

  $r = Src-Run @('query', '--name', 'Go', '--db', $projR)
  Src-Check 'R6' (($r.Code -eq 0) -and ($r.Out -match 'AppU\.Go') -and -not ($r.Out -match 'index schema v\d+ <') -and (Src-NoAv $r.Out)) "query --db <proj@v$readMin> answers (exit $($r.Code))"

  if ($hasKeys) {
    $sr = (Src-Run @('schema', '--db', $libR, '--format', 'json')).Out
    $srj = $sr.Substring($sr.IndexOf('{')) | ConvertFrom-Json
    Src-Check 'R7' ($srj.schema_readable -eq $true) "schema reports v$readMin readable"
  } else { Write-Host 'SKIP R7 schema_readable key absent (pre-150 exe)' }

  # ---- arm U: READ_MIN - 1 --------------------------------------------------------------
  $old = $readMin - 1
  $libU = Join-Path $tmp 'lib-u.sqlite'; Src-StampCopy $lib $libU $old
  $projU = Join-Path $tmp 'proj-u.sqlite'; Src-StampCopy $proj $projU $old
  $r = Src-Run @('index', '--project', (Join-Path $appDir 'App.dpr'), '--db', (Join-Path $tmp 'u1.sqlite'), '--library-db', $libU)
  Src-Check 'U1' (($r.Code -eq 0) -and ($r.Out -match 'library-db skipped') -and ($r.Out -match 'older than this engine reads') -and (Src-NoAv $r.Out)) "index --library-db <lib@v$old> skips it with the named reason (exit $($r.Code))"

  $r = Src-Run @('query', '--name', 'Go', '--db', $projU)
  Src-Check 'U2' (($r.Out -match "index schema v$old <") -and (Src-NoAv $r.Out)) "query --db <proj@v$old> is refused by name (exit $($r.Code))"

  $r = Src-Run @('lint-tree', '--unit', (Join-Path $appDir 'AppU.pas'), '--db', $projU)
  Src-Check 'U3' (($r.Code -eq 2) -and ($r.Out -match 'older than this engine reads') -and (Src-NoAv $r.Out)) "lint-tree --db <proj@v$old>: exit $($r.Code) + reason"

  $r = Src-Run @('uses-recover', '--db', $projU, '--hpp-dir', $hppDir)
  Src-Check 'U4' (($r.Out -match 'older than this engine reads') -and (Src-NoAv $r.Out)) "uses-recover --db <proj@v$old>: refused with the reason (exit $($r.Code))"

  if ($hasKeys) {
    $su = (Src-Run @('schema', '--db', $libU, '--format', 'json')).Out
    $suj = $su.Substring($su.IndexOf('{')) | ConvertFrom-Json
    Src-Check 'U5' ($suj.schema_readable -eq $false) "schema reports v$old unreadable"
  } else { Write-Host 'SKIP U5 schema_readable key absent (pre-150 exe)' }
}
finally {
  try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Verbose "temp dir left: $tmp" }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
