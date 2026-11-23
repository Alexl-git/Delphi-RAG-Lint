<#
  run_v153_symid_fk_classes.ps1 -- GitHub #18 slice 2 (1.53.0 symbol-id reuse), spec A10.

  Symbol-id reuse keeps a re-emitted symbol's id, so the ON DELETE CASCADE / SET NULL that used
  to clear every row keyed by the old id no longer fires for it. Every column that holds a
  symbols.id must therefore be CLASSIFIED in TSQLiteSymbolStore's SYMBOL_ID_COLUMN_CLASSES
  (DRagLint.Storage.SQLite.pas) as
      E  emit-owned      -- cleared for the file's ids when the file is re-emitted
      R  resolver-written, cross-file -- kept for a claimed id, rebound by the scoped pass
      D  derived whole-table -- rebuilt by its own pass every run
      P  purity verdict  -- cleared for every claimed routine
  This guard indexes a 3-unit fixture into a fresh database, reads every column that
  REFERENCES symbols(id) from sqlite_master (plus the known non-FK holders), parses the class
  list out of the .pas source (no new verb) and FAILS naming every unclassified column and every
  classified column the schema no longer has.

  POSITIVE CONTROL: one parsed entry is dropped in memory; the same check must then name it.

  Run from a neutral CWD (C:\TEMP), pwsh 7. Needs Python 3 (py or python).
#>
[CmdletBinding()]
param(
  [string]$Exe = '',
  [switch]$KeepScratch
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$scratch = Join-Path C:\TEMP "draglint_symidfk_$PID"
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))
}

$exePath = (Resolve-Path $Exe).Path
$pyExe = 'python'; $pyPre = @('-I')
if (Get-Command py -ErrorAction SilentlyContinue) { $pyExe = 'py'; $pyPre = @('-I') }

if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

Write-Ascii (Join-Path $src 'uA.pas') @'
unit uA;

interface

type
  TBase = class
  public
    procedure Run; virtual;
  end;

function Calc(AValue: Integer): Integer;

implementation

procedure TBase.Run;
begin
end;

function Calc(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

end.
'@
Write-Ascii (Join-Path $src 'uB.pas') @'
unit uB;

interface

uses
  uA;

type
  TDerived = class(TBase)
  public
    procedure Run; override;
  end;

implementation

procedure TDerived.Run;
begin
  Calc(2);
end;

end.
'@
Write-Ascii (Join-Path $src 'uC.pas') @'
unit uC;

interface

uses
  uA, uB;

procedure Go;

implementation

procedure Go;
var
  D: TDerived;
begin
  D := TDerived.Create;
  D.Run;
  Calc(3);
end;

end.
'@

$db = Join-Path $scratch 'fk.sqlite'
Push-Location C:\TEMP
try {
  $out = & { $ErrorActionPreference = 'Continue'; & $exePath index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-String
} finally { Pop-Location }
Check 'SANITY: the fixture indexed into a fresh database' (Test-Path $db) ($out -split "`n" | Select-Object -Last 4 | Out-String)

# Every column that REFERENCES symbols(id), plus the holders sqlite_master cannot name.
$py = Join-Path $scratch 'fkcols.py'
[System.IO.File]::WriteAllText($py, @'
import sqlite3, sys
c = sqlite3.connect('file:' + sys.argv[1] + '?mode=ro', uri=True)
cols = set()
for (t,) in c.execute("select name from sqlite_master where type='table'"):
    for row in c.execute("pragma foreign_key_list('%s')" % t.replace("'", "''")):
        if row[2] == 'symbols':
            cols.add('%s.%s' % (t, row[3]))
names = set(r[0] for r in c.execute("select name from sqlite_master where type='table'"))
for extra in ('orm_links.delphi_symbol_id', 'orm_links.sql_symbol_id', 'type_ancestors.ancestor_symbol_id'):
    t, col = extra.split('.')
    if t in names and any(r[1] == col for r in c.execute("pragma table_info('%s')" % t)):
        cols.add(extra)
for x in sorted(cols):
    print(x)
'@, (New-Object System.Text.ASCIIEncoding))
$schemaCols = @(& $pyExe @pyPre $py $db | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
Check "SANITY: the schema holds symbol-id columns ($($schemaCols.Count))" ($schemaCols.Count -ge 30) ($schemaCols -join ', ')

# The class list, parsed out of the source (no debug verb by design).
$pas = [System.IO.File]::ReadAllText((Join-Path $Repo 'src\storage\DRagLint.Storage.SQLite.pas'))
$classes = @{}
$m = [regex]::Match($pas, 'SYMBOL_ID_COLUMN_CLASSES\s*:\s*array\s*\[[^\]]*\]\s*of\s*string\s*=\s*\((?<body>.*?)\);', 'Singleline')
if ($m.Success) {
  foreach ($e in [regex]::Matches($m.Groups['body'].Value, "'(?<col>[a-z_]+\.[a-z_]+)=(?<cls>[ERDP])'")) { $classes[$e.Groups['col'].Value] = $e.Groups['cls'].Value }
}
Check 'the SYMBOL_ID_COLUMN_CLASSES const is present in DRagLint.Storage.SQLite.pas' $m.Success ''

function Get-Unclassified($cols, $map) { @($cols | Where-Object { -not $map.ContainsKey($_) }) }
function Get-Stale($cols, $map) { @($map.Keys | Where-Object { $cols -notcontains $_ } | Sort-Object) }

$missing = @(Get-Unclassified $schemaCols $classes)
Check "every symbol-id column is classified E/R/D/P ($($schemaCols.Count) columns)" ($missing.Count -eq 0) ("unclassified ($($missing.Count)): " + ($missing -join ', '))
$stale = @(Get-Stale $schemaCols $classes)
Check 'no classified column is missing from the schema' ($stale.Count -eq 0) ("stale: " + ($stale -join ', '))

# POSITIVE CONTROL: drop one entry in memory -- the same check must name it.
if ($classes.Count -gt 0) {
  $victim = @($classes.Keys | Sort-Object)[0]
  $copy = @{}; foreach ($k in $classes.Keys) { if ($k -ne $victim) { $copy[$k] = $classes[$k] } }
  $pcMissing = @(Get-Unclassified $schemaCols $copy)
  Check "POSITIVE CONTROL: dropping '$victim' from the list is reported" (($pcMissing.Count -eq 1) -and ($pcMissing[0] -eq $victim)) ("reported: " + ($pcMissing -join ', '))
} else {
  Check 'POSITIVE CONTROL: needs a parsed class list' $false 'no entries parsed'
}

} finally {
  if (-not $KeepScratch -and (Test-Path $scratch)) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($fail) { Write-Host 'RESULT: FAIL'; exit 1 } else { Write-Host 'RESULT: PASS'; exit 0 }
