<#
  run_index_stamp_fast_path.ps1 -- an unchanged file is taken as up to date from
  its write time and size, without reading it, and a changed file is still
  re-parsed (2026-10-14, STAMP FAST PATH in TIndexer.IndexFileBody).

  WHY THIS EXISTS. The up-to-date test compares the stored SHA, so every run read
  and hashed every file of its scope -- 1.3 s of a nothing-changed run over the
  2,218 files of the TestCopy ProjectA closure. files.size now records the
  byte count of the content a row describes, and a same-time, same-size file is
  skipped before any read. The checks pin both directions, because a fast path
  that skips a changed file would leave the index silently stale.

  Checks:
    1. after an index, every files row carries the size of its file
       (RED on the exe before the change: there is no size column);
    2. a run with nothing changed parses nothing;
    3. a file whose content (and size) changed is re-parsed, and its new
       symbol is in the index;
    4. a row with no recorded size (an older database) still counts as up to
       date through the full test, which then records the size.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_stamp_fast_$PID"
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)
}
function Write-Unit([string]$Name, [string]$Extra = '') {
  Write-Ascii (Join-Path $src "$Name.pas") @"
unit $Name;

interface

procedure Run$Name;
$Extra
implementation

procedure Run$Name;
begin
end;

end.
"@
}
foreach ($n in 'uOne', 'uTwo', 'uThree') { Write-Unit $n }

$py = @'
import sqlite3, sys, os
c = sqlite3.connect(sys.argv[2])
if sys.argv[1] == 'sizes':
    bad = 0
    for path, size in c.execute('SELECT path, size FROM files'):
        if size is None or size != os.path.getsize(path): bad += 1; print('BAD=' + os.path.basename(path) + ' ' + str(size))
    print('BAD_COUNT=%d' % bad)
elif sys.argv[1] == 'null':
    c.execute("UPDATE files SET size = NULL WHERE path LIKE '%uTwo.pas'"); c.commit()
elif sys.argv[1] == 'size2':
    print('SIZE2=%s' % c.execute("SELECT size FROM files WHERE path LIKE '%uTwo.pas'").fetchone()[0])
elif sys.argv[1] == 'sym':
    print('SYM=%d' % c.execute("SELECT COUNT(*) FROM symbols WHERE name = 'Fresh'").fetchone()[0])
'@
$pyf = Join-Path $scratch 'q.py'
Write-Ascii $pyf $py
function Q([string]$What, [string]$Db) { return (& python $pyf $What $Db 2>&1 | Out-String) }
# Files parsed this run = the per-file progress lines ("<path> -> N symbols, ..."); main's Done line has no parsed count.
function Parsed([string]$Out) { return @($Out -split "`r?`n" | Where-Object { $_ -match ' -> \d+ symbols' }).Count }

$db = Join-Path $scratch 'idx.sqlite'
Push-Location C:\TEMP
try {
  & $exePath index $src --db $db 2>&1 | Out-Null
  $s1 = Q 'sizes' $db
  Check '1: every files row carries the size of its file' ($s1 -match 'BAD_COUNT=0') $s1

  $o2 = & $exePath index $src --db $db 2>&1 | Out-String
  Check '2: a run with nothing changed parses nothing' ((Parsed $o2) -eq 0) ($o2 -split "`r?`n" | Select-String 'Done' | Out-String)

  Start-Sleep -Milliseconds 1100
  Write-Unit 'uOne' 'procedure Fresh;'
  $o3 = & $exePath index $src --db $db 2>&1 | Out-String
  Check '3: a changed file is re-parsed' ((Parsed $o3) -eq 1) ($o3 -split "`r?`n" | Select-String 'Done' | Out-String)
  Check '3: and its new declaration is in the index' ((Q 'sym' $db) -match 'SYM=1') (Q 'sym' $db)

  Q 'null' $db | Out-Null
  $o4 = & $exePath index $src --db $db 2>&1 | Out-String
  Check '4: a row with no recorded size is still up to date (full test)' ((Parsed $o4) -eq 0) ($o4 -split "`r?`n" | Select-String 'Done' | Out-String)
  Check '4: and the full test records the size' ((Q 'size2' $db) -match 'SIZE2=\d+') (Q 'size2' $db)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_stamp_fast_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
