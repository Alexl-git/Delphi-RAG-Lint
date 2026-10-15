<#
  run_query_notes_out_of_closure.ps1 -- a QUERY against a project index that
  holds rows outside its compile closure must say so, even when the index is
  current (Gitea drag-lint#8), and every freshness note must reach a merged
  stdout+stderr whole and before the results (#27 in plans\correcoes).

  THE DEFECT. `index --project` reports "scope: N indexed file(s) are outside
  this project's compile closure" and stamps out_of_closure_count, but the only
  reader of that stamp was the STALE branch of the freshness note. A current
  index stayed silent while its non-member rows took part in every answer: on
  the xe ProjectA index a .dpr copied from another folder counted as one more
  `unit-usage` user, and a deleted unit was the target every `uses` resolved to.

  THE INTERLEAVING. The notes are written with Writeln(ErrOutput) before the
  first stdout line. The RTL flushes a Text per line only on a console; on a
  pipe it has a 128-byte buffer, so the tail of a long note came out after the
  results.

  WHAT THIS ASSERTS
    1. shared db, current: `query --name` prints the out-of-closure note    <- THE FIX
    2. the note names the exact count (P2's two rows) and --rebuild
    3. in ONE merged handle the note is a whole line and precedes the
       first stdout line                                                    <- #27
    4. `query unit-usage` prints it too (the verb the defect was found on)
    5. CONTROL: stdout alone is unchanged by the note (no note text there)
    6. CONTROL: a stale index prints the older "of those" sentence ONCE and
       not the new one as well -- one fact, one sentence
    7. CONTROL: a single-project db prints no out-of-closure note
    8. CONTROL: after `index --project --rebuild` the note is gone

  RED-CHECK: against the pre-fix build cases 1, 2, 3 and 4 FAIL (no note at
  all on a current index); 5-8 assert absence or old behaviour and pass there
  too, so they are controls, not evidence.
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

$work = Join-Path C:\TEMP "draglint_querynote_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

# ONE OS handle for both streams: the ordering assertion (case 3) is about the
# bytes the process writes, and PowerShell's own `2>&1` re-merges two pipes
# line by line, which hides the defect.
function RunCap([string[]]$ArgList) {
  $log = Join-Path $work ('run-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $quoted = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  cmd /c "`"$Exe`" $quoted > `"$log`" 2>&1" | Out-Null
  $code = $LASTEXITCODE
  $txt = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  if ($null -eq $txt) { $txt = '' }
  return @{ Out = $txt; Code = $code }
}
function RunStdout([string[]]$ArgList) {
  $log = Join-Path $work ('out-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $quoted = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  cmd /c "`"$Exe`" $quoted > `"$log`" 2>nul" | Out-Null
  $txt = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  if ($null -eq $txt) { $txt = '' }
  return $txt
}

$aDir = Join-Path $work 'a'
$bDir = Join-Path $work 'b'

Write-Ascii (Join-Path $aDir 'P1.dpr') @'
program P1;

uses
  UnitA1 in 'UnitA1.pas',
  UnitA2 in 'UnitA2.pas';

begin
end.
'@

Write-Ascii (Join-Path $aDir 'UnitA1.pas') @'
unit UnitA1;

interface

type
  TThingA1 = class
  public
    procedure DoA1;
  end;

implementation

procedure TThingA1.DoA1;
begin
end;

end.
'@

Write-Ascii (Join-Path $aDir 'UnitA2.pas') @'
unit UnitA2;

interface

uses UnitA1;

procedure UseA1(const T: TThingA1);

implementation

procedure UseA1(const T: TThingA1);
begin
  T.DoA1;
end;

end.
'@

Write-Ascii (Join-Path $bDir 'P2.dpr') @'
program P2;

uses
  UnitB1 in 'UnitB1.pas';

begin
end.
'@

Write-Ascii (Join-Path $bDir 'UnitB1.pas') @'
unit UnitB1;

interface

implementation

end.
'@

$db = Join-Path $work 'x.sqlite'
$p1 = Join-Path $aDir 'P1.dpr'
$p2 = Join-Path $bDir 'P2.dpr'
$newNote = '^drag-lint: note: (\d+) indexed file\(s\) lie OUTSIDE this project.s compile closure and may appear in answers\. .*--rebuild\s*$'

Write-Host ''
Write-Host '=== seeding: P2 then P1 into ONE db, then P1 again (current index) ===' -ForegroundColor Cyan
$s2 = RunCap @('index','--project',$p2,'--db',$db)
Check 'seed: P2 indexes' ($s2.Code -eq 0) "exit=$($s2.Code)"
$s1 = RunCap @('index','--project',$p1,'--db',$db)
Check 'seed: P1 indexes' ($s1.Code -eq 0) "exit=$($s1.Code)"
$s1b = RunCap @('index','--project',$p1,'--db',$db)
Check 'seed: P1 again stamps out_of_closure_count' ($s1b.Out -match '(?m)^scope: 2 indexed file\(s\) are outside') "out=$($s1b.Out)"

Write-Host ''
Write-Host '=== case 1-3: query --name on a CURRENT shared db ===' -ForegroundColor Cyan
$q = RunCap @('query','--name','TThingA1','--db',$db,'--exact')
Write-Host $q.Out -ForegroundColor DarkGray
$lines = @($q.Out -split "`r?`n")
$noteIdx = -1; $firstOut = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($noteIdx -lt 0 -and $lines[$i] -match $newNote) { $noteIdx = $i }
  if ($firstOut -lt 0 -and $lines[$i] -match 'TThingA1') { $firstOut = $i }
}
Check '1. the out-of-closure note is printed on a current index' ($noteIdx -ge 0) 'pre-fix build prints nothing'
$n = 0
if ($noteIdx -ge 0 -and $lines[$noteIdx] -match $newNote) { $n = [int]$Matches[1] }
Check '2. it names exactly P2''s two rows' ($n -eq 2) "count=$n"
Check '3. the note is whole and precedes the first stdout line' `
  ($noteIdx -ge 0 -and $firstOut -gt $noteIdx -and -not ($lines[$firstOut] -match 'note:')) `
  "noteIdx=$noteIdx firstOut=$firstOut"

Write-Host ''
Write-Host '=== case 4: query unit-usage (the verb of the report) ===' -ForegroundColor Cyan
$u = RunCap @('query','unit-usage','--unit','UnitA1','--db',$db)
Write-Host $u.Out -ForegroundColor DarkGray
Check '4. unit-usage prints the note too' ((@($u.Out -split "`r?`n") -match $newNote).Count -eq 1) ''

Write-Host ''
Write-Host '=== case 5: CONTROL -- stdout alone carries no note ===' -ForegroundColor Cyan
$so = RunStdout @('query','--name','TThingA1','--db',$db,'--exact')
Check '5. CONTROL: stdout has the answer and no note text' `
  (($so -match 'TThingA1') -and -not ($so -match 'note:')) "out=$so"

Write-Host ''
Write-Host '=== case 6: CONTROL -- a stale index says it once ===' -ForegroundColor Cyan
Start-Sleep -Milliseconds 1100
$b1 = Join-Path $bDir 'UnitB1.pas'
Write-Ascii $b1 ((Get-Content -LiteralPath $b1 -Raw) + "`r`n{ touched }`r`n")
$st = RunCap @('query','--name','TThingA1','--db',$db,'--exact')
Write-Host $st.Out -ForegroundColor DarkGray
Check '6. CONTROL: the stale "of those" sentence is printed' ($st.Out -match 'of those indexed file\(s\) lie OUTSIDE') ''
Check '6b. CONTROL: and the current-index sentence is NOT added to it' `
  ((@($st.Out -split "`r?`n") -match $newNote).Count -eq 0) ''
# #27: this ~300-byte sentence was cut at the 128-byte buffer and its tail
# printed after the results. Whole line, and before the first stdout line.
$stLines = @($st.Out -split "`r?`n")
$ofIdx = -1; $stOut = -1
for ($i = 0; $i -lt $stLines.Count; $i++) {
  if ($ofIdx -lt 0 -and $stLines[$i] -match '^drag-lint: note: \d+ of those indexed file\(s\) lie OUTSIDE.*--rebuild\s*$') { $ofIdx = $i }
  if ($stOut -lt 0 -and $stLines[$i] -match 'TThingA1') { $stOut = $i }
}
Check '6c. the stale "of those" note is one whole line before the results (#27)' `
  ($ofIdx -ge 0 -and $stOut -gt $ofIdx) "ofIdx=$ofIdx firstOut=$stOut"

Write-Host ''
Write-Host '=== case 7: CONTROL -- a single-project db ===' -ForegroundColor Cyan
$dbSolo = Join-Path $work 'solo.sqlite'
$null = RunCap @('index','--project',$p1,'--db',$dbSolo)
$solo = RunCap @('query','--name','TThingA1','--db',$dbSolo,'--exact')
Check '7. CONTROL: no out-of-closure note' (-not ($solo.Out -match 'OUTSIDE')) "out=$($solo.Out)"

Write-Host ''
Write-Host '=== case 8: CONTROL -- --rebuild clears it ===' -ForegroundColor Cyan
$rb = RunCap @('index','--project',$p1,'--db',$db,'--rebuild')
Check 'rebuild: exit 0' ($rb.Code -eq 0) "exit=$($rb.Code)"
$after = RunCap @('query','--name','TThingA1','--db',$db,'--exact')
Check '8. CONTROL: after --rebuild the note is gone' (-not ($after.Out -match 'OUTSIDE')) "out=$($after.Out)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_querynote_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
