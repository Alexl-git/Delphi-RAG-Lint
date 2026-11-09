<#
  run_index_stale_library_guard.ps1 -- 149 INT: `index --library-db <stale schema>` degrades, never crashes.

  Found at 149 INT (SCHEMA_VERSION 23 -> 24, lane EX2): every `index ... --library-db` against a
  library index still at schema 23 died in the calls stage with
    EAccessViolation ... Data.DB.TDataSet.GetActive (read of address 0x125)
  stack: CollectByName <- TSQLiteSymbolStore.FindSymbolsByExactName <- TLibraryOracle.Collect
         <- BindBare <- TCallResolver.BindExternally <- ResolveCallTargets.
  Cause: OpenLibraryStores (CLI) opened the library with a bare TSQLiteSymbolStore.Create; on a
  stale schema the constructor skips PrepareStatements, so every FQ* query is nil (the same trap
  OpenLibraryStoreIfCurrent documents for the lint verbs since schema 21 -> 22).

  Fixture (built in a temp dir): a library unit LibU (TLibThing) indexed with -Exe into lib.sqlite,
  a project App.dpr whose unit calls TLibThing.Create / Free.
  Checks:
    P1  POSITIVE CONTROL: lib.sqlite at the CURRENT schema -> index exits 0 and prints '+ library-db'.
    S1  lib.sqlite stamped one schema version older -> index exits 0 (RED on 149 INT before the fix:
        exit 3, EAccessViolation).
    S2  ... and the output names the skip and the schema ('library-db skipped' + 'schema').
    S3  ... and no EAccessViolation text in the output.
  Needs python (stdlib sqlite3) to stamp the old schema_version; missing python = FATAL, never a skip.

  Usage: pwsh -File tests\autotest\run_index_stale_library_guard.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'src\cli\Win64\Debug\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { Write-Host 'FATAL: python not found (needed to stamp an old schema_version)'; exit 2 }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("stalelib-" + [Guid]::NewGuid().ToString('N'))
$libDir = Join-Path $tmp 'lib'
$appDir = Join-Path $tmp 'app'
[IO.Directory]::CreateDirectory($libDir) | Out-Null
[IO.Directory]::CreateDirectory($appDir) | Out-Null
$script:Failed = $false

function StaleLib-Check([string]$Id, [bool]$Ok, [string]$What) {
  if ($Ok) { Write-Host "PASS $Id $What" } else { Write-Host "FAIL $Id $What"; $script:Failed = $true }
}
function StaleLib-Write([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, (($Text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}

try {
  StaleLib-Write (Join-Path $libDir 'LibU.pas') @'
unit LibU;

interface

type
  TLibThing = class
  public
    procedure Run;
  end;

implementation

procedure TLibThing.Run;
begin
end;

end.
'@
  StaleLib-Write (Join-Path $appDir 'AppU.pas') @'
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
end;

end.
'@
  StaleLib-Write (Join-Path $appDir 'App.dpr') @'
program App;

uses
  AppU in 'AppU.pas';

begin
  Go;
end.
'@
  $lib = Join-Path $tmp 'lib.sqlite'
  & $exePath index $libDir --db $lib 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "library index exit $LASTEXITCODE" }

  $outP = & $exePath index --project (Join-Path $appDir 'App.dpr') --db (Join-Path $tmp 'p1.sqlite') --library-db $lib 2>&1 | Out-String
  StaleLib-Check 'P1' (($LASTEXITCODE -eq 0) -and ($outP -match '\+ library-db')) "current-schema library is attached (exit $LASTEXITCODE)"

  $stamp = Join-Path $tmp 'stamp.py'
  [IO.File]::WriteAllText($stamp, @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
v = int(c.execute("SELECT value FROM schema_meta WHERE key = 'schema_version'").fetchone()[0])
c.execute("UPDATE schema_meta SET value = ? WHERE key = 'schema_version'", (str(v - 1),))
c.commit()
c.close()
print(v - 1)
'@)
  $old = & $py -I $stamp $lib
  Write-Host "library stamped schema v$old"

  $outS = & $exePath index --project (Join-Path $appDir 'App.dpr') --db (Join-Path $tmp 's1.sqlite') --library-db $lib 2>&1 | Out-String
  $codeS = $LASTEXITCODE
  StaleLib-Check 'S1' ($codeS -eq 0) "stale-schema library: index exits 0 (got $codeS)"
  StaleLib-Check 'S2' (($outS -match 'library-db skipped') -and ($outS -match 'schema')) 'the skip names the library and its schema'
  StaleLib-Check 'S3' (-not ($outS -match 'AccessViolation')) 'no access violation'
  if ($script:Failed) { Write-Host '--- stale-run output (tail) ---'; ($outS -split "`n" | Select-Object -Last 8) | ForEach-Object { Write-Host $_ } }
}
finally {
  try { [IO.Directory]::Delete($tmp, $true) } catch { Write-Verbose "temp dir left: $tmp" }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
