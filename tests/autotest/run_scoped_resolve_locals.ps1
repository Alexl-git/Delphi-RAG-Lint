<#
  run_scoped_resolve_locals.ps1 -- a re-indexed file's PARAMS and LOCALS must
  not widen the scoped call-resolve (backlog #53, Gitea drag-lint#40).

  WHY THIS EXISTS. The scoped pass re-resolves "refs in the changed files, plus
  refs elsewhere named like a symbol the changed files declared". Until
  2026-10-14 that name set included every param and local_var. A local `Text`
  and a param `SQL` in UFEditA.pas pulled 37,014 refs from 1,936 files into a
  one-file pass on ProjectA -- most of a ~48 s calls stage. No ref in another
  file can bind to a routine's param or local, so those names buy nothing.

  The fixture builds the shape on purpose:

      uLocal.pas     procedure Touch(Sentinel: Integer); var Probe: Integer;
                     (the file the run re-indexes -- a body edit)
      uUse1..3.pas   each calls its own Sentinel and Probe 5 times apiece

  Checks:
    1. the run really is scoped (else the counts below say nothing);
    2. the affected-ref count leaves out the 30 consumer call sites
       named Sentinel/Probe (RED on the exe before the fix);
    3. the scoped edges equal a whole-DB resolve of the same tree (soundness);
    4. POSITIVE CONTROL: renaming the unit routine `Touch` -- not a local --
       DOES pull its 3 consumer call sites in, so check 2 is not passing because
       the scope stopped growing altogether. (Since symbol reuse, 2026-10-14, a
       body edit no longer puts `Touch` in scope at all: its row keeps its id.)

  Fixture size is load-bearing: the scoped pass declines at a third of the
  corpus, so one changed file needs at least 4 files in the index.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_scoped_locals_$PID"
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Local([string]$Body, [string]$RoutineName = 'Touch') {
  Write-Ascii (Join-Path $src 'uLocal.pas') @"
unit uLocal;

interface

procedure $RoutineName(Sentinel: Integer);

implementation

procedure $RoutineName(Sentinel: Integer);
var
  Probe: Integer;
begin
  Probe := Sentinel;
$Body
end;

end.
"@
}

Write-Local '  Probe := Probe + 1;'

# Consumers: each declares its OWN Sentinel and Probe and calls them 10 times,
# plus one call to uLocal.Touch for the positive control.
foreach ($n in 1..3) {
  $calls = (1..5 | ForEach-Object { "  Sentinel;`r`n  Probe;" }) -join "`r`n"
  Write-Ascii (Join-Path $src "uUse$n.pas") @"
unit uUse$n;

interface

uses
  uLocal;

procedure Sentinel;
procedure Probe;
procedure Run$n;

implementation

procedure Sentinel;
begin
end;

procedure Probe;
begin
end;

procedure Run$n;
begin
$calls
  Touch(1);
end;

end.
"@
}

$py = @'
import sqlite3, sys, os
c = sqlite3.connect(sys.argv[1])
for x in c.execute("""
    SELECT f.path, r.start_line, r.start_col, r.name_text,
           COALESCE(s.qualified_name,'?'), COALESCE(e.confidence,'')
    FROM call_edges e
    JOIN refs r ON r.id = e.ref_id
    JOIN files f ON f.id = r.file_id
    LEFT JOIN symbols s ON s.id = e.target_symbol_id
    ORDER BY f.path, r.start_line, r.start_col, r.name_text""").fetchall():
    row = list(x); row[0] = os.path.basename(row[0])
    print('EDGE|' + '|'.join(str(i) for i in row))
'@
$pyf = Join-Path $scratch 'dump.py'
Write-Ascii $pyf $py

function RunIndex([string]$Db, [string]$NoScoped) {
  Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE -ErrorAction SilentlyContinue
  if ($NoScoped) { $env:DRAGLINT_NO_SCOPED_RESOLVE = $NoScoped }
  try   { return (& $exePath index $src --db $Db 2>&1 | Out-String) }
  finally { Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE -ErrorAction SilentlyContinue }
}
function Affected([string]$Out) {
  if ($Out -match 'from (\d+) affected call-site ref\(s\)') { return [int]$Matches[1] }
  return -1
}

Push-Location C:\TEMP
try {
  $dbBase   = Join-Path $scratch 'base.sqlite'
  $dbScoped = Join-Path $scratch 'scoped.sqlite'
  $dbWhole  = Join-Path $scratch 'whole.sqlite'

  & $exePath index $src --db $dbBase 2>&1 | Out-Null
  Copy-Item $dbBase $dbScoped -Force
  Copy-Item $dbBase $dbWhole  -Force

  # A BODY edit: declarations, params and locals all come back unchanged.
  Write-Local "  Probe := Probe + 1;`r`n  Probe := Probe + 2;"

  $outScoped = RunIndex $dbScoped ''
  $outWhole  = RunIndex $dbWhole  '1'
  $nScoped   = Affected $outScoped

  Check 'CONTROL: the body-edit run took the SCOPED path' ($nScoped -ge 0) $outScoped
  Check 'CONTROL: the whole-DB run took the WHOLE DB path' ($outWhole -match 'WHOLE DB') $outWhole

  # uLocal itself has a handful of refs; the consumers have 30 Sentinel + 30
  # Probe call sites. Anything at or above 30 means the locals leaked in.
  Check 'params and locals of the changed file do not pull same-named refs from other files' `
        (($nScoped -ge 0) -and ($nScoped -lt 30)) "affected=$nScoped (30 consumer call sites are named Sentinel/Probe)"

  $dumpS = & python $pyf $dbScoped 2>&1 | Out-String
  $dumpW = & python $pyf $dbWhole  2>&1 | Out-String
  Check 'CONTROL: the whole-DB run binds the consumer calls (fixture builds the shape)' `
        ($dumpW -match 'uUse1\.pas\|\d+\|\d+\|Sentinel\|uUse1\.Sentinel') `
        (($dumpW -split "`r?`n" | Select-Object -First 8) -join "`n")
  Check 'scoped edges equal the whole-DB edges' ($dumpS -ceq $dumpW) "scoped=$($dumpS.Length) whole=$($dumpW.Length)"
  if ($dumpS -cne $dumpW) {
    $a = ($dumpS -split "`r?`n" | Where-Object { $_ }); $b = ($dumpW -split "`r?`n" | Where-Object { $_ })
    $b | Where-Object { $a -notcontains $_ } | Select-Object -First 10 |
      ForEach-Object { Write-Host "        missing: $_" -ForegroundColor DarkGray }
  }

  # POSITIVE CONTROL: a unit-level name still widens the scope. Renaming Touch
  # removes 'touch'; the 3 consumer calls to it must be re-resolved.
  $dbRename = Join-Path $scratch 'rename.sqlite'
  Copy-Item $dbScoped $dbRename -Force
  Write-Local "  Probe := Probe + 1;`r`n  Probe := Probe + 2;" 'Touched'
  $outRename = RunIndex $dbRename ''
  $nRename   = Affected $outRename
  Check 'POSITIVE CONTROL: renaming the changed file''s unit routine pulls its 3 callers in' `
        ($nRename -ge 3) "rename affected=$nRename, body-edit affected=$nScoped"
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_scoped_locals_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
