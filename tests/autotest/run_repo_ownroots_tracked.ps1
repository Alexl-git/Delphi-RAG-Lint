<#
  run_repo_ownroots_tracked.ps1 -- this repo's own projects must carry a TRACKED
  _D-RAG\drag-lint-project.json, so lint-all in a fresh clone or a git worktree
  lints the whole project and not just the .dproj folder.

  THE DEFECT (docs\INBOX-lint-all-scope-filter-drops-units-outside-dproj-dir.md,
  2026-10-23). drag-lint.dproj sits in src\cli; 200 of its 206 member units live
  in src\<other>. The declaration ["..\\.."] existed only in the MAIN tree,
  untracked (hidden by a '*' .gitignore inside _D-RAG), so every worktree
  defaulted ownRoots to src\cli: lint-all on a lane DB scanned 6 files and
  reported 419 findings, every one under src\cli. Every "lint-all clean" check
  run from a worktree was silently that small.

  The engine behaviour is right (ownership must be declared; run_ownroots_default_note.ps1
  pins the default and its NOTE). What was missing is the declaration in git.

    A. each in-repo project with an index (src\cli, src\delphi-plugin, tests,
       tools\corpusscan) has its declaration TRACKED.
    B. the tracked src\cli declaration covers EVERY `in '...'` member of
       drag-lint.dpr. Positive control: the same coverage check with ownRoots
       ["."] (the default) reports uncovered members, so B cannot pass vacuously.
    C. behaviour: a fixture with the repo's shape (src\cli\App.dpr, member
       src\index\U2.pas with an unused local) and the TRACKED declaration text
       -> lint-all reports the U2 finding. Positive control: the same fixture
       without the declaration does NOT report it.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Repo    = "$PSScriptRoot\..\..",
  [string]$WorkDir = "$env:TEMP\drag-lint-repo-ownroots-$PID"
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
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, (($Body -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
# Members of a .dpr/.dpk: every `in '<path>'`, resolved against the project folder.
function Get-Members([string]$Dpr) {
  $dir = Split-Path -Parent $Dpr
  $txt = [IO.File]::ReadAllText($Dpr)
  foreach ($m in [regex]::Matches($txt, "\bin\s+'([^']+\.pas)'", 'IgnoreCase')) {
    [IO.Path]::GetFullPath((Join-Path $dir $m.Groups[1].Value))
  }
}
# Members not under any of the roots (roots relative to <projectdir>\_D-RAG's parent).
function Get-Uncovered([string]$Dpr, [string[]]$Roots) {
  $dir = Split-Path -Parent $Dpr
  $abs = foreach ($r in $Roots) { [IO.Path]::GetFullPath((Join-Path $dir $r)).TrimEnd('\') + '\' }
  @(Get-Members $Dpr | Where-Object { $p = $_; -not ($abs | Where-Object { $p.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) })
}

$Repo = (Resolve-Path $Repo).Path
Write-Host 'A. the in-repo declarations are tracked' -ForegroundColor Cyan
foreach ($d in 'src/cli', 'src/delphi-plugin', 'tests', 'tools/corpusscan') {
  $rel = "$d/_D-RAG/drag-lint-project.json"
  $tracked = (git -C $Repo ls-files -- $rel) -eq $rel
  Check "A $rel tracked" $tracked 'RED = a worktree/clone lints only the project folder'
}

Write-Host ''
Write-Host 'B. the tracked src\cli declaration covers every drag-lint.dpr member' -ForegroundColor Cyan
$dpr  = Join-Path $Repo 'src\cli\drag-lint.dpr'
$decl = (git -C $Repo show 'HEAD:src/cli/_D-RAG/drag-lint-project.json' 2>$null) -join "`n"
$members = @(Get-Members $dpr)
Check 'B0 CONTROL: the .dpr parses to members' ($members.Count -gt 100) "members=$($members.Count)"
$ctl = Get-Uncovered $dpr @('.')
Check 'B1 CONTROL: the default root ["."] leaves members uncovered' ($ctl.Count -gt 0) "uncovered=$($ctl.Count) (proves B2 can fail)"
$roots = @()
if ($decl) { $roots = @((ConvertFrom-Json $decl).ownRoots) }
Check 'B2 HEAD declaration has ownRoots' ($roots.Count -gt 0) ("roots=" + ($roots -join ','))
if ($roots.Count -gt 0) {
  # ownRoots resolve against the anchor = the folder that holds _D-RAG = the .dpr folder.
  $unc = Get-Uncovered $dpr $roots
  Check 'B3 every member covered' ($unc.Count -eq 0) ("uncovered=$($unc.Count) " + (($unc | Select-Object -First 3) -join '; '))
}

Write-Host ''
Write-Host 'C. lint-all reports a finding in a member outside the .dproj folder' -ForegroundColor Cyan
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$cli = Join-Path $WorkDir 'repo\src\cli'
$idx = Join-Path $WorkDir 'repo\src\index'
New-Item -ItemType Directory -Force (Join-Path $cli '_D-RAG'), $idx | Out-Null
Write-Ascii (Join-Path $cli 'App.dpr') @'
program App;

uses
  U1 in 'U1.pas',
  U2 in '..\index\U2.pas';

begin
  Go;
  Help;
end.
'@
Write-Ascii (Join-Path $cli 'U1.pas') @'
unit U1;

interface

procedure Go;

implementation

procedure Go;
begin
end;

end.
'@
Write-Ascii (Join-Path $idx 'U2.pas') @'
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
$db = Join-Path $cli '_D-RAG\App.sqlite'
& $Exe index --project (Join-Path $cli 'App.dpr') --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host "FATAL: no index" -ForegroundColor Red; exit 2 }
function LintAll {
  Push-Location $WorkDir
  try { return (& $Exe lint-all --db $db --output (Join-Path $WorkDir 'rep.txt') 2>&1 | Out-String) }
  finally { Pop-Location }
}
$u2 = 'U2\.pas:\d+:\d+\s+\[\w+\]\s+unused-local'
$c0 = LintAll
Check 'C0 CONTROL: without a declaration the U2 finding is dropped' (-not ($c0 -match $u2)) 'if it shows, the fixture lost the worktree shape'
if ($decl) { [IO.File]::WriteAllText((Join-Path $cli '_D-RAG\drag-lint-project.json'), $decl, [Text.Encoding]::ASCII) }
$c1 = LintAll
Check 'C1 with the TRACKED declaration the U2 finding is reported' ($c1 -match $u2) 'RED = the repo declaration does not widen lint-all'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-repo-ownroots-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
