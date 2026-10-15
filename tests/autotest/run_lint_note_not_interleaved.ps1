<#
  run_lint_note_not_interleaved.ps1 -- the closing stderr note of `lint` must
  reach a merged stdout+stderr stream WHOLE (Gitea drag-lint#6).

  THE DEFECT. DoLint writes one of two notes with Writeln(ErrOutput) ("no index
  covers this file ..." without --db, "project rules ran for this file ..."
  with one). Both are longer than 128 bytes. The Delphi RTL flushes a Text per
  line only when the handle is a console; on a pipe or file it uses a 128-byte
  buffer, so with both streams on one handle (bash, cmd `2>&1`) the note was cut
  at byte 128, the first finding was glued to that half, and the tail came out
  after the summary. PowerShell's own `2>&1` re-merges two pipes line by line
  and hides it, so this runner uses ONE OS handle through cmd.

  WHAT THIS ASSERTS
    1. no --db: the note is one whole line                          <- THE FIX
    2. no --db: every finding line still starts with <file>:<l>:<c>  <- THE FIX
    3. with --db: the "project rules ran" note is one whole line    <- THE FIX
    4. CONTROL: stdout alone carries the findings and no note
    5. CONTROL: --quiet prints no note at all

  RED-CHECK: against the pre-fix build 1, 2 and 3 FAIL (the note is split at
  byte 128); 4 and 5 pass on both builds.
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

$work = Join-Path C:\TEMP "draglint_lintnote_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

function RunMerged([string[]]$ArgList) {
  $log = Join-Path $work ('m-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $quoted = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  cmd /c "`"$Exe`" $quoted > `"$log`" 2>&1" | Out-Null
  $txt = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  if ($null -eq $txt) { $txt = '' }
  return $txt
}
function RunStdout([string[]]$ArgList) {
  $log = Join-Path $work ('o-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $quoted = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  cmd /c "`"$Exe`" $quoted > `"$log`" 2>nul" | Out-Null
  $txt = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
  if ($null -eq $txt) { $txt = '' }
  return $txt
}

# Several findings, so the first one has a stdout line to glue onto.
$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'LintNote.dpr') @'
program LintNote;

uses
  UNote in 'UNote.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'UNote.pas') @'
unit UNote;

interface

function Calc(A: Integer): Integer;

implementation

function Calc(A: Integer): Integer;
begin
  Result := A * 37; Result := Result + 4211;
  if A > 999 then Result := 12345; A := 0;
end;

end.
'@
$unit = Join-Path $dir 'UNote.pas'
$rules = 'multiple-statements-per-line,magic-literal'

# Anchored on the drive letter: '^.+' would accept the glued line, which starts
# with "drag-lint: note: ... for pa" and still contains a valid finding.
$findingRx = '^[A-Za-z]:\\\S+\.pas:\d+:\d+\s+\['
function Lines([string]$t) { return @($t -split "`r?`n" | Where-Object { $_ -ne '' }) }

Write-Host ''
Write-Host '=== case 1-2: no --db ===' -ForegroundColor Cyan
$m = RunMerged @('lint', $unit, '--enable', $rules)
Write-Host $m -ForegroundColor DarkGray
$ls = Lines $m
$note = @($ls | Where-Object { $_ -match '^drag-lint: note: no index covers this file' })
Check '1. the no-index note is one whole line' `
  ($note.Count -eq 1 -and $note[0] -match 'A 0 above does not mean they are clean\.\s*$') "note=$($note -join ' | ')"
$findings = @($ls | Where-Object { $_ -match '\[(info|warning|error|hint)\]' })
$bad = @($findings | Where-Object { $_ -notmatch $findingRx })
Check '2. every finding line starts with <file>:<line>:<col>' `
  ($findings.Count -ge 2 -and $bad.Count -eq 0) "findings=$($findings.Count) bad=$($bad -join ' | ')"

Write-Host ''
Write-Host '=== case 3: with --db ===' -ForegroundColor Cyan
$db = Join-Path $work 'x.sqlite'
$null = RunMerged @('index', '--project', (Join-Path $dir 'LintNote.dpr'), '--db', $db)
$m2 = RunMerged @('lint', $unit, '--enable', $rules, '--db', $db)
Write-Host $m2 -ForegroundColor DarkGray
$note2 = @((Lines $m2) | Where-Object { $_ -match '^drag-lint: note: project rules ran for this file' })
Check '3. the project-rules note is one whole line' `
  ($note2.Count -eq 1 -and $note2[0] -match 'unit-not-in-dpr without --project\.\s*$') "note=$($note2 -join ' | ')"

Write-Host ''
Write-Host '=== case 4-5: CONTROLS ===' -ForegroundColor Cyan
$so = RunStdout @('lint', $unit, '--enable', $rules)
Check '4. CONTROL: stdout alone has the findings and no note' `
  (($so -match '\[(info|warning|error|hint)\]') -and -not ($so -match 'drag-lint: note:')) ''
$q = RunMerged @('lint', $unit, '--enable', $rules, '--quiet')
Check '5. CONTROL: --quiet prints no note' (-not ($q -match 'drag-lint: note:')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_lintnote_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
