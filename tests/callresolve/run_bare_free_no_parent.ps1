<#
  run_bare_free_no_parent.ps1 -- a BARE call to a TObject member (`Free`) inside
  a method of a class with NO written parent binds to the library's TObject.

  Lane 149-RB1 item 3 (146 b7 leftover: "A bare Free inside a no-parent class is
  not covered"). The typed-receiver path (`F.Free`) already ended a complete
  chain at the implicit root TObject; the bare path handed the oracle an empty
  scope type, so only a library ROUTINE named Free could answer -- none does.

  Needs the platform library (read only): -LibraryDb, default
  C:\Projects\.drag-lint\library-Win64.sqlite. Missing library = FATAL, never a skip.

  CASES (markers in the fixture; lines are read from it)
    B1 Free inside TFoo = class          -> external_target System.TObject.Free
    B2 Free inside TBar = class(TObject) -> System.TObject.Free (control, green on the base)
    B3 F.Free, F: TFoo                   -> System.TObject.Free (control, green on the base)
    N1 Free inside TRec = record         -> no external target (a record has no TObject root)

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_bare_free_no_parent.ps1 [-Exe <drag-lint.exe>] [-LibraryDb <lib.sqlite>]
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$LibraryDb = "C:\Projects\.drag-lint\library-Win64.sqlite",
  [string]$WorkDir   = "C:\TEMP\draglint_bare_free_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "FATAL: library DB not found: $LibraryDb" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

W (Join-Path $WorkDir 'uF.pas') @'
unit uF;

interface

type
  TFoo = class
  public
    procedure Done;
  end;

  TBar = class(TObject)
  public
    procedure Done;
  end;

  TRec = record
    procedure Done;
  end;

procedure Outer(F: TFoo);

implementation

procedure TFoo.Done;
begin
  Free; // B1
end;

procedure TBar.Done;
begin
  Free; // B2
end;

procedure TRec.Done;
begin
  Free; // N1
end;

procedure Outer(F: TFoo);
begin
  F.Free; // B3
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uF in 'uF.pas';

begin
end.
'@

$db = Join-Path $WorkDir 'App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db --library-db $LibraryDb 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Sql([string]$Q) {
  $j = & $Exe sql --db $db --json --limit 1000 --query $Q 2>$null | ConvertFrom-Json
  if ($null -eq $j) { return ,@() }
  $cols = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($row in $j.rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
    $out += [pscustomobject]$o
  }
  return ,$out
}
function LineOfMarker([string]$Marker) {
  $ls = [IO.File]::ReadAllLines((Join-Path $WorkDir 'uF.pas'))
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match ('// ' + [regex]::Escape($Marker) + '$')) { return $i + 1 } }
  return -1
}
function FreeAt([string]$Marker) {
  $ln = LineOfMarker $Marker
  return ,(Sql "SELECT r.id, r.external_target AS et, r.symbol_id AS sid FROM refs r JOIN files f ON f.id = r.file_id WHERE r.kind = 'call' AND r.name_text = 'Free' AND r.start_line = $ln AND f.path LIKE '%\uF.pas'")
}

foreach ($c in @(@{ M = 'B1'; Why = 'bare, no written parent' }, @{ M = 'B2'; Why = 'bare, class(TObject) control' }, @{ M = 'B3'; Why = 'typed receiver control' })) {
  $r = FreeAt $c.M
  Check ("{0}  Free -> System.TObject.Free ({1})" -f $c.M, $c.Why) `
    (($r.Count -eq 1) -and ($r[0].et -eq 'System.TObject.Free')) ("rows=$($r.Count) et=$($r[0].et) sid=$($r[0].sid)")
}
$r = FreeAt 'N1'
Check 'N1  Free in a RECORD method has no TObject root -> no external target' `
  (($r.Count -eq 1) -and ($null -eq $r[0].et)) ("rows=$($r.Count) et=$($r[0].et)")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_bare_free_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
