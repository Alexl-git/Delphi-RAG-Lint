<#
  run_library_db_value_receiver.ps1 -- with --library-db, a call on a VALUE
  whose type lives in the library is answered, inherited members included.

  THE PROBLEM (evaluation on ProjectA, 2026-09-28). The cross-DB rung
  (ResolveExternally) offered the library the RECEIVER TEXT as a type name, so
  `vQ.Open` with `vQ: TFDQuery` asked the library for a type called `vQ` and got
  nothing -- only a receiver that was itself a type name (`TFoo.Create`) could
  be answered. It also looked only at the type's own members, so a method the
  type inherits (TFDQuery.Open is TDataSet's) was never found.

  THE FIX (resolver 1.15.0-alpha). A value receiver is looked up by its declared
  TYPE; the member is searched on the type and then its ancestors, nearest level
  first; several library types of one name are told apart by the caller's uses.

  The answer lands on refs.external_target (a qualified NAME -- a call edge
  cannot point into another database), read here with python/sqlite3.

  Usage: pwsh -File tests/callresolve/run_library_db_value_receiver.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_libdb_value_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$lib = Join-Path $WorkDir 'lib'
$app = Join-Path $WorkDir 'app'
New-Item -ItemType Directory -Path $lib, $app | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# The "library": a dataset hierarchy, and two same-named list types.
Write-Ascii (Join-Path $lib 'LibData.pas') @'
unit LibData;

interface

type
  TLibDataSet = class(TObject)
  public
    procedure Open;
  end;

  TLibQuery = class(TLibDataSet)
  public
    procedure ExecSQL;
  end;

implementation

procedure TLibDataSet.Open;
begin
end;

procedure TLibQuery.ExecSQL;
begin
end;

end.
'@
foreach ($u in @('LibListA', 'LibListB')) {
  Write-Ascii (Join-Path $lib "$u.pas") @"
unit $u;

interface

type
  TLibList = class(TObject)
  public
    procedure Clear;
  end;

implementation

procedure TLibList.Clear;
begin
end;

end.
"@
}

# The project: values typed by library types.
Write-Ascii (Join-Path $app 'uApp.pas') @'
unit uApp;

interface

uses
  LibData, LibListB;

procedure UseOwn;
procedure UseInherited;
procedure UseListB;

implementation

procedure UseOwn;
var
  Q: TLibQuery;
begin
  Q.ExecSQL;
end;

procedure UseInherited;
var
  Q: TLibQuery;
begin
  Q.Open;
end;

procedure UseListB;
var
  L: TLibList;
begin
  L.Clear;
end;

end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'
$appDb = Join-Path $WorkDir 'app.sqlite'
& $exePath index $lib --db $libDb --quiet 2>&1 | Out-Null
Check 'precondition: library index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
& $exePath index $app --db $appDb --library-db $libDb --quiet 2>&1 | Out-Null
Check 'precondition: project index with --library-db exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$py = Join-Path $WorkDir 'ext.py'
Write-Ascii $py @'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
rows = c.execute("""select s.name, r.name_text, ifnull(r.external_target,'')
  from refs r join symbols s on s.id = r.enclosing_symbol_id
  where r.name_text in ('ExecSQL','Open','Clear')""").fetchall()
print(json.dumps({f"{a}.{b}": t for a, b, t in rows}))
'@
$ext = (python $py $appDb) -join '' | ConvertFrom-Json

Check 'ASSERT: a value whose type DECLARES the method is answered (Q.ExecSQL)' `
  ($ext.'UseOwn.ExecSQL' -eq 'LibData.TLibQuery.ExecSQL') "external_target='$($ext.'UseOwn.ExecSQL')'"
Check 'ASSERT: an INHERITED library method is answered (Q.Open -> TLibDataSet.Open)' `
  ($ext.'UseInherited.Open' -eq 'LibData.TLibDataSet.Open') "external_target='$($ext.'UseInherited.Open')'"
Check 'ASSERT: two library types of one name are told apart by the uses clause (LibListB)' `
  ($ext.'UseListB.Clear' -eq 'LibListB.TLibList.Clear') "external_target='$($ext.'UseListB.Clear')'"

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_libdb_value_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
