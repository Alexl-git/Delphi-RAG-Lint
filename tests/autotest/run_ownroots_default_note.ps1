<#
  run_ownroots_default_note.ps1 -- when <project>\_D-RAG\drag-lint-project.json
  is ABSENT, lint-all must say which ownRoots it defaulted to (L2).

  THE DEFECT. The declaration file is gitignored, so a fresh clone or a git
  worktree does not have it. TOwnRoots then defaults -- correctly, per the
  house rule -- to the project file's own folder. For a project whose .dproj
  sits in a SUBFOLDER (this repo's src\cli) that default classifies almost the
  whole codebase as third-party, and lint-all scanned a handful of files. The
  skip summary gave a count, but nothing said the declaration was missing or
  which root had been assumed, so the short run read as a small project. The
  same thing is why `lint <file>` and `lint-all` seemed to disagree (L8): the
  per-file verb lints the file it is given; lint-all had silently skipped it.

  FIXTURE: the worktree shape. app\App.dpr is the project; shared\U2.pas is a
  real member of its closure OUTSIDE the project folder.
    A. no declaration -> the loud NOTE names the missing file, the defaulted
       root and the skipped count; U2 is not scanned.
    B. declaration ["..\\"] -> no note; U2 IS scanned (positive control: the
       declaration is what widens the run, so the note was about the right thing).
    C. no declaration, nothing outside -> the one-line "ownRoots = ... (DEFAULT"
       form, never the loud one.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-ownroots-note"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, (($Body -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$app    = Join-Path $WorkDir 'repo\app'
$shared = Join-Path $WorkDir 'repo\shared'
New-Item -ItemType Directory -Force (Join-Path $app '_D-RAG'), $shared | Out-Null

Write-Ascii (Join-Path $app 'App.dpr') @'
program App;

uses
  U1 in 'U1.pas',
  U2 in '..\shared\U2.pas';

begin
  Go;
  Help;
end.
'@
Write-Ascii (Join-Path $app 'U1.pas') @'
unit U1;

interface

procedure Go;

implementation

procedure Go;
begin
end;

end.
'@
Write-Ascii (Join-Path $shared 'U2.pas') @'
unit U2;

interface

procedure Help;

implementation

procedure Help;
var
  Idle: Integer;
begin
end;

end.
'@
$db   = Join-Path $app '_D-RAG\App.sqlite'
$decl = Join-Path $app '_D-RAG\drag-lint-project.json'
& $Exe index --project (Join-Path $app 'App.dpr') --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host "FATAL: no index" -ForegroundColor Red; exit 2 }

function LintAll {
  Push-Location $WorkDir
  try { return (& $Exe lint-all --db $db --output (Join-Path $WorkDir 'rep.txt') 2>&1 | Out-String) }
  finally { Pop-Location }
}

Write-Host 'A. no declaration, a member outside the project folder' -ForegroundColor Cyan
$a = LintAll
Check 'A0 CONTROL: the outside member was skipped' ($a -match '1 file\(s\) outside the project''s own roots skipped') 'if not, the fixture does not have the worktree shape'
Check 'A1 the NOTE names the missing declaration' ($a -match 'NOTE: .*drag-lint-project\.json does not exist') 'RED = the default was applied in silence'
Check 'A2 and says it is gitignored / absent in a worktree' ($a -match 'gitignored') ''
Check 'A3 and names the DEFAULTED root' ($a -match ('ownRoots DEFAULTED to the project folder ' + [regex]::Escape($app))) ''
Check 'A4 and the skipped count' ($a -match 'the 1 file\(s\) outside it were treated as third-party') ''
Check 'A5 U2 was not linted' (-not ($a -match 'U2\.pas:\d+:\d+')) ''

Write-Host ''
Write-Host 'B. declaration present -> no note, and the outside member IS linted' -ForegroundColor Cyan
[IO.File]::WriteAllText($decl, '{ "ownRoots": ["..\\.."] }', [Text.Encoding]::ASCII)
$b = LintAll
Check 'B1 no ownRoots note' (-not ($a -eq $b) -and -not ($b -match 'ownRoots DEFAULTED|ownRoots = ')) ''
Check 'B2 U2 is scanned now (unused-local on Idle)' ($b -match 'U2\.pas:\d+:\d+\s+\[\w+\]\s+unused-local') 'the declaration is what widens the run'

Write-Host ''
Write-Host 'C. no declaration, nothing outside -> the quiet one-line form' -ForegroundColor Cyan
Remove-Item $decl -Force
Write-Ascii (Join-Path $app 'App.dpr') @'
program App;

uses
  U1 in 'U1.pas';

begin
  Go;
end.
'@
& $Exe index --project (Join-Path $app 'App.dpr') --db $db --rebuild 2>&1 | Out-Null
$c = LintAll
Check 'C1 names the defaulted root in one line' ($c -match ('ownRoots = ' + [regex]::Escape($app) + ' \(DEFAULT')) ''
Check 'C2 and not the loud form (nothing was skipped)' (-not ($c -match 'ownRoots DEFAULTED')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
