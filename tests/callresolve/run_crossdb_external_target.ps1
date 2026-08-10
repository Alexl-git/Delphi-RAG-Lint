<#
  run_crossdb_external_target.ps1 -- schema v21: a call into ANOTHER index is
  recorded BY QUALIFIED NAME on refs.external_target.

  WHY BY NAME AND NOT AS AN EDGE. call_edges.target_symbol_id is
  `NOT NULL REFERENCES symbols(id)` -- a hard FK into THIS database. A library
  symbol (System.JSON.TJSONArray.Create, a DevExpress or Spring method) has no row
  here, so no edge to it can exist and cross-DB resolution had nowhere to put its
  answer. Making the FK nullable and adding target_qname/target_db was the
  alternative and was rejected: 28 sites read target_symbol_id and 5 join
  call_edges to symbols, so one missed NULL check silently drops or miscounts
  edges. Recording the name on the REF is additive -- call_edges keeps exactly the
  meaning it has today.

  Two databases, as in real use: xdb_lib.pas indexed alone (the "library"), then
  xdb_app.pas indexed as the project WITH --library-db pointing at it.

  THE CONTROL MATTERS AS MUCH AS THE RESULT. The same app is indexed twice --
  without and with --library-db -- and external_target must be NULL in the first
  run. Without that control the assertion would also pass if the column were
  populated by something other than the cross-DB rung.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\xdb')).Path

$scratch = Join-Path C:\TEMP 'draglint_xdb'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
$libDir = Join-Path $scratch 'lib'
$appDir = Join-Path $scratch 'app'
New-Item -ItemType Directory -Path $libDir -Force | Out-Null
New-Item -ItemType Directory -Path $appDir -Force | Out-Null
Copy-Item (Join-Path $fixDir 'xdb_lib.pas') $libDir -Force
Copy-Item (Join-Path $fixDir 'xdb_app.pas') $appDir -Force
$libDb = Join-Path $scratch 'lib.sqlite'
$appDb = Join-Path $scratch 'app.sqlite'

# Reads refs.external_target for a given call name via the engine's own schema
# dump would be indirect; query the sqlite file with the bundled python instead.
function Get-Ext([string]$db, [string]$callName) {
  $py = @"
import sqlite3
c = sqlite3.connect(r'$db')
r = c.execute("select external_target from refs where kind='call' and name_text=? collate nocase", ('$callName',)).fetchone()
print('' if (r is None or r[0] is None) else r[0])
"@
  ($py | & python -) 2>$null | Select-Object -First 1
}

Push-Location C:\TEMP
try {
  & $exePath index $libDir --db $libDb 2>$null | Out-Null
  Check 'library index built' ($LASTEXITCODE -eq 0)

  # --- CONTROL: no --library-db -> nothing external is recorded --------------
  & $exePath index $appDir --db $appDb 2>$null | Out-Null
  Check 'app index built (control run)' ($LASTEXITCODE -eq 0)
  $ctl = Get-Ext $appDb 'Create'
  Check 'CONTROL: without --library-db, external_target is EMPTY' ($ctl -eq '') "got='$ctl'"

  # --- with the library consulted -------------------------------------------
  Remove-Item $appDb -Force
  $out = & $exePath index $appDir --db $appDb --library-db $libDb 2>&1 | Out-String
  Check 'app index built (cross-DB run)' ($LASTEXITCODE -eq 0)
  Check 'the library db is reported as opened' ($out -match 'library-db') $out

  $ext = Get-Ext $appDb 'Create'
  Check 'RESOLVED BY NAME: external_target = xdb_lib.TJsonThing.Create' `
    ($ext -eq 'xdb_lib.TJsonThing.Create') "got='$ext'"

  # --- and it stays FP-conservative -----------------------------------------
  # TNeverDeclared exists in no index. The rung answers only when exactly one
  # type AND exactly one member match, so this must stay empty: absence beats a
  # guess, and a wrong external name is a wrong FACT rendered into documentation.
  $py = @"
import sqlite3
c = sqlite3.connect(r'$appDb')
rows = c.execute("select r.name_text, r.receiver_text, r.external_target from refs r where r.kind='call'").fetchall()
bad = [x for x in rows if x[1] == 'TNeverDeclared' and x[2]]
print('LEAK' if bad else 'CLEAN')
"@
  $unknown = ($py | & python -) 2>$null | Select-Object -First 1
  Check 'FP-CONSERVATIVE: a type no index declares gets NO external_target' `
    ($unknown -eq 'CLEAN') "got='$unknown'"

  # --- a local answer must always win ---------------------------------------
  # external_target is only ever set when TargetSymbolId = 0; the cross-DB rung
  # runs LAST. Adding a library store can never change an edge that already
  # existed, which is what makes this safe to enable by default later.
  $py2 = @"
import sqlite3
c = sqlite3.connect(r'$appDb')
n = c.execute("select count(*) from refs r join call_edges e on e.ref_id=r.id where r.external_target is not null").fetchone()[0]
print(n)
"@
  $both = ($py2 | & python -) 2>$null | Select-Object -First 1
  Check 'no ref carries BOTH a local edge and an external_target' ($both -eq '0') "got='$both'"
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
