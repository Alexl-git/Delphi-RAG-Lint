<#
  run_fts_targeted_patch.ps1 -- an incremental index patches the two FTS5 text
  indexes (string_fts, string_fts_tri) in set statements, and the result is the
  same index a full rebuild produces.

  WHY THIS EXISTS. Until 2026-10-14 an incremental run kept the string_literals
  sync triggers live for its first 16 files. FTS5 flushes a segment at every
  statement boundary, and each trigger firing is its own statement, so every
  literal became a one-row segment for the automerge to fold into the trigram
  index: ten form units cost 259 s of literals + 73 s of open-tx on the
  TestCopy ProjectA index, 45 s for UFEditB.pas alone. Now the run drops
  the triggers, keeps a receipt (temp.dl_fts_gone / dl_fts_files) and patches
  both indexes at the end; the same ten units cost 2.6 s.

  Checks:
    1. the incremental run PATCHES (stderr 'fts        patched') -- RED on the
       exe before the change, which never printed it;
    2. the patched indexes pass FTS5 'integrity-check';
    3. their fts5vocab 'instance' rows equal those of a rebuild of the same
       table (a changed literal, a removed one, an added one, and a whole file
       pruned from disk all covered);
    4. a query sees the new text and not the old;
    5. the bulk load from an empty table still REBUILDS (the other branch).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_fts_patch_$PID"
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Unit([string]$Name, [string[]]$Texts) {
  $lines = ($Texts | ForEach-Object { "  S := '$_';" }) -join "`r`n"
  Write-Ascii (Join-Path $src "$Name.pas") @"
unit $Name;

interface

procedure Go;

implementation

procedure Go;
var
  S: string;
begin
$lines
end;

end.
"@
}

Write-Unit 'uA' @('alpha_one keep', 'SELECT * FROM CUSTOMER', 'gone_soon text')
Write-Unit 'uB' @('bravo_two', 'UPDATE ITEM SET X = 1')
Write-Unit 'uC' @('charlie_three')
Write-Unit 'uD' @('delta_four')
Write-Unit 'uE' @('echo_five')
Write-Unit 'uF' @('foxtrot_six pruned')

$py = @'
import sqlite3, sys, shutil
mode, db = sys.argv[1], sys.argv[2]
def vocab(path):
    c = sqlite3.connect(path)
    out = []
    for t in ('string_fts', 'string_fts_tri'):
        c.execute(f"CREATE VIRTUAL TABLE IF NOT EXISTS temp.v_{t} USING fts5vocab(main, {t}, 'instance')")
        out += [(t,) + r for r in c.execute(f"SELECT term, doc, col, offset FROM temp.v_{t} ORDER BY 1,2,3,4")]
    c.close()
    return out
if mode == 'integrity':
    c = sqlite3.connect(db)
    for t in ('string_fts', 'string_fts_tri'):
        c.execute(f"INSERT INTO {t}({t}, rank) VALUES('integrity-check', 1)")
    print('OK')
elif mode == 'vs-rebuild':
    ref = db + '.rebuilt'
    shutil.copy(db, ref)
    c = sqlite3.connect(ref)
    for t in ('string_fts', 'string_fts_tri'):
        c.execute(f"INSERT INTO {t}({t}) VALUES('rebuild')")
    c.commit(); c.close()
    a, b = vocab(db), vocab(ref)
    print('SAME' if a == b else f'DIFF patched={len(a)} rebuilt={len(b)}')
elif mode == 'match':
    c = sqlite3.connect(db)
    for term in sys.argv[3:]:
        n = c.execute("SELECT COUNT(*) FROM string_fts WHERE string_fts MATCH ?", ('"' + term + '"',)).fetchone()[0]
        m = c.execute("SELECT COUNT(*) FROM string_fts_tri WHERE string_fts_tri MATCH ?", ('"' + term + '"',)).fetchone()[0]
        print(f'{term}={n}/{m}')
'@
$pyf = Join-Path $scratch 'fts.py'
Write-Ascii $pyf $py

Push-Location C:\TEMP
try {
  $db = Join-Path $scratch 'idx.sqlite'
  $out1 = & $exePath index $src --db $db 2>&1 | Out-String
  Check 'bulk load from an empty table REBUILDS the text indexes' ($out1 -match 'fts +rebuilt both text indexes') $out1

  # A changed literal, a removed one, an added one -- and a whole file pruned.
  Write-Unit 'uA' @('omega_new keep', 'SELECT * FROM CUSTOMER', 'added_later text')
  Remove-Item (Join-Path $src 'uF.pas')
  $out2 = & $exePath index $src --db $db 2>&1 | Out-String
  Check 'the incremental run PATCHES the text indexes instead of rebuilding' ($out2 -match 'fts +patched both text indexes') $out2

  $integ = & python $pyf integrity $db 2>&1 | Out-String
  Check 'FTS5 integrity-check passes on both patched indexes' ($integ -match 'OK') $integ

  $cmp = & python $pyf vs-rebuild $db 2>&1 | Out-String
  Check 'the patched indexes equal a rebuild of the same table (fts5vocab instance rows)' ($cmp -match 'SAME') $cmp

  $m = & python $pyf match $db 'omega_new' 'alpha_one' 'added_later' 'gone_soon' 'foxtrot_six' 'bravo_two' 2>&1 | Out-String
  Check 'queries see the new text, not the old, and untouched files stay' `
        ($m -match 'omega_new=1/1' -and $m -match 'alpha_one=0/0' -and $m -match 'added_later=1/1' -and
         $m -match 'gone_soon=0/0' -and $m -match 'foxtrot_six=0/0' -and $m -match 'bravo_two=1/1') $m
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_fts_patch_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
