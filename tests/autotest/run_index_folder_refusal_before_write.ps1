<#
  run_index_folder_refusal_before_write.ps1 -- `index <folder>` aimed at a
  PROJECT database must be refused before anything writes to it (Gitea
  drag-lint#22).

  THE DEFECT. DoIndex ran Migrate, the fingerprint stamp and --rebuild's
  ClearAllFiles BEFORE the folder-into-project refusal. So
  `index <dir> --db <projectDb> --rebuild` printed the refusal and exited 2
  -- after `--rebuild: cleared N indexed file(s)`. Measured on a 2-file
  fixture: files went 2 -> 0. Aiming a folder where a .dproj was meant cost
  the whole project index.

  It also decides the order against the one-writer lock (#17): a folder aimed
  at a project index is refused for what it is, even while another run holds
  the lock, which is what run_index_wal_checkpointed.ps1 CONTROL A expects.

  WHAT THIS ASSERTS
    1. --rebuild: the refusal exits 2 and the project rows are all still there  <- THE FIX
    2. --rebuild: nothing says it cleared anything                             <- THE FIX
    3. lock held by another run: the folder is still refused AS A FOLDER
       (the refusal text, not the lock message)                                <- ordering
    4. CONTROL: a plain `index <dir>` (no --rebuild) is refused and keeps the rows
    5. CONTROL: `index --project` on the same database still works

  RED-CHECK (2026-10-09, on the build that had the lock but the old order):
  1, 2 and 3 FAIL -- rows 2 -> 0, "cleared 2", and the lock message instead
  of the folder refusal; 4 then fails only in cascade (case 1 had already
  emptied the database); 5 passes on both builds.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
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

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
function Run([string[]]$ArgList) {
  $out = Join-Path $work ('o-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $quoted = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  cmd /c "`"$Exe`" $quoted > `"$out`" 2>&1" | Out-Null
  $code = $LASTEXITCODE
  $o = if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Raw } else { '' }
  if ($null -eq $o) { $o = '' }
  return @{ Out = $o; Code = $code }
}
# Indexed file count, read through the engine itself (sql verb, read-only).
function FileCount([string]$db) {
  $r = Run @('sql', '--query', 'SELECT COUNT(*) AS n FROM files', '--db', $db, '--json')
  if ($r.Out -match '"n"\s*:\s*(\d+)') { return [int]$Matches[1] }
  if ($r.Out -match '(?m)^\s*(\d+)\s*$') { return [int]$Matches[1] }
  return -1
}

$work = Join-Path C:\TEMP "draglint_folderrefuse_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'R.dpr') @'
program R;

uses
  UR in 'UR.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'UR.pas') @'
unit UR;

interface

procedure P;

implementation

procedure P;
begin
end;

end.
'@
$dpr = Join-Path $dir 'R.dpr'
$db = Join-Path $work 'r.sqlite'
$seed = Run @('index', '--project', $dpr, '--db', $db)
$n0 = FileCount $db
Check 'seed: project index built' (($seed.Code -eq 0) -and ($n0 -ge 2)) "exit=$($seed.Code) files=$n0"

Write-Host ''
Write-Host '=== index <folder> --rebuild into the project database ===' -ForegroundColor Cyan
$r = Run @('index', $dir, '--db', $db, '--rebuild')
Write-Host $r.Out -ForegroundColor DarkGray
$n1 = FileCount $db
Check '1. refused (exit 2) and every project row is still there' `
  (($r.Code -eq 2) -and ($r.Out -match 'refusing to index a FOLDER into a PROJECT database') -and ($n1 -eq $n0)) "exit=$($r.Code) files $n0 -> $n1"
Check '2. nothing was cleared' (-not ($r.Out -match 'cleared \d+ indexed file')) ''

Write-Host ''
Write-Host '=== the same, while another run holds the index lock ===' -ForegroundColor Cyan
$held = [System.IO.File]::Open($db + '.indexing.lock', 'OpenOrCreate', 'ReadWrite', 'None')
try {
  $l = Run @('index', $dir, '--db', $db)
  Check '3. still refused as a FOLDER, not as a busy database' `
    (($l.Code -eq 2) -and ($l.Out -match 'refusing to index a FOLDER') -and -not ($l.Out -match 'another index run is writing')) "out=$($l.Out.Trim())"
} finally {
  $held.Dispose()
  Remove-Item -LiteralPath ($db + '.indexing.lock') -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '=== CONTROLS ===' -ForegroundColor Cyan
$p = Run @('index', $dir, '--db', $db)
Check '4. CONTROL: plain index <folder> refused, rows kept' (($p.Code -eq 2) -and ((FileCount $db) -eq $n0)) "exit=$($p.Code)"
$ok = Run @('index', '--project', $dpr, '--db', $db)
Check '5. CONTROL: index --project on it still works' (($ok.Code -eq 0) -and ((FileCount $db) -eq $n0)) "exit=$($ok.Code)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_folderrefuse_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
