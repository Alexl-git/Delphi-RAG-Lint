<#
  run_config_ownroots.ps1 -- "ownRoots" is a key of _D-RAG\config.json (E3b
  item 1, 2026-10-14).

  THE GAP. Inside a repository configured by `drag-lint init`, config.json is
  the only configuration (E3a) -- but it had no "ownRoots". lint-all and
  `document --project` still read <anchor>\_D-RAG\drag-lint-project.json, an
  old loose file, from whichever folder the run anchored to: the repository
  root for `--db <root>\_D-RAG\App.sqlite`, the .dproj's folder for
  `--project`. So the same project got two different scopes depending on the
  flag, and the declaration lived outside the one file the repository is
  configured by.

  THE RULE NOW, inside a configured repository:
    * "ownRoots" at the top of config.json applies to every project;
    * "ownRoots" in a "projects" entry overrides it for that project;
    * entries are relative to the REPOSITORY ROOT (the folder holding _D-RAG);
    * an empty list is an error (exit 2), as it always was;
    * the key WINS over a loose drag-lint-project.json; without the key the
      loose file still answers -- the precedence config.json's "lint" and
      "layers" blocks have -- and with neither, the default note names
      config.json as the place to declare.
  Outside a configured repository nothing changes (run_lint_own_roots covers it).

  CASES (App.dpr + App\uMain.pas + Shared\uShared.pas + Vendor\uVendor.pas):
    N   no key, no loose file -> default scope, the note names config.json   <- FIX
    A   top-level ["App","Shared"], --db       -> 3 scanned, Vendor skipped   <- FIX
    A2  same, with --project App.dproj         -> 3 scanned (same scope)     <- FIX
    B   project-level ["App"] overrides        -> 2 scanned                  <- FIX
    C   "ownRoots": []                         -> exit 2 naming config.json  <- FIX
    W   the key + a loose file ["Vendor"]      -> the key wins, 3 scanned    <- FIX
    D   CONTROL: no key + loose file ["Vendor"] -> the loose file answers, 1
  RED-CHECK: on the pre-fix exe N, A, A2, B, C and W fail; D passes on both.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_cfg_ownroots_$PID"
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

function Run([string[]]$argv) {
  Push-Location C:\TEMP
  try {
    $out = & $Exe @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
  } finally { Pop-Location }
}

function Scanned([string]$text) {
  if ($text -match 'lint-all: scanning (\d+) \.pas file') { return [int]$Matches[1] }
  return -1
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$root = Join-Path $WorkDir 'repo'
$app  = Join-Path $root 'App'
$dhome = Join-Path $root '_D-RAG'
$cfg  = Join-Path $dhome 'config.json'
$db   = Join-Path $dhome 'App.sqlite'
$dproj = Join-Path $app 'App.dproj'

Write-Ascii $dproj "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <ProjectVersion>18.8</ProjectVersion>`n    <MainSource>App.dpr</MainSource>`n  </PropertyGroup>`n</Project>`n"
Write-Ascii (Join-Path $app 'App.dpr') @'
program App;
uses
  uMain in 'uMain.pas',
  uShared in '..\Shared\uShared.pas',
  uVendor in '..\Vendor\uVendor.pas';
begin
  Go;
  Share;
  Vend;
end.
'@
foreach ($u in @(@('App','uMain','Go'), @('Shared','uShared','Share'), @('Vendor','uVendor','Vend'))) {
  Write-Ascii (Join-Path (Join-Path $root $u[0]) ($u[1] + '.pas')) @"
unit $($u[1]);
interface
procedure $($u[2]);
implementation
procedure $($u[2]);
begin
end;
end.
"@
}

function Set-Config([string]$top, [string]$proj) {
  $p = '{ "name": "App", "dproj": "App\\App.dproj", "platform": "Win32", "delphi": "20.0"' + $proj + ' }'
  Write-Ascii $cfg ('{ "version": 1, "projects": [ ' + $p + ' ]' + $top + ' }')
}

Write-Host ''
Write-Host 'run_config_ownroots -- "ownRoots" lives in config.json inside a configured repository' -ForegroundColor Cyan

Set-Config '' ''
$ix = Run @('index', '--project', $dproj)
Check 'the fixture indexed into <root>\_D-RAG\App.sqlite' (($ix.Code -eq 0) -and (Test-Path $db)) $ix.Text
if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host 'CONTROL -- no "ownRoots": the default scope (the repository root) lints all 4' -ForegroundColor Cyan
$c0 = Run @('lint-all', '--db', $db)
Check 'CONTROL 4 file(s) scanned' ((Scanned $c0.Text) -eq 4) $c0.Text
Check 'N the DEFAULT note names config.json as the place to declare' ($c0.Text -match 'DEFAULT -- .*_D-RAG\\config\.json') $c0.Text

Write-Host ''
Write-Host 'A -- top-level "ownRoots": ["App","Shared"]' -ForegroundColor Cyan
Set-Config ', "ownRoots": ["App", "Shared"]' ''
$a = Run @('lint-all', '--db', $db)
Check 'A not refused (exit 0 or 1)' ($a.Code -le 1) $a.Text
Check 'A 3 file(s) scanned (Vendor is third-party)' ((Scanned $a.Text) -eq 3) $a.Text
Check 'A the skip lines name Vendor' ($a.Text -match '(?m)^\s+1\s+.*\\Vendor\s*$') $a.Text
Check 'A no DEFAULT note (the roots are declared)' (-not ($a.Text -match 'DEFAULT')) $a.Text
Check 'A "declare in" names config.json' ($a.Text -match 'declare in .*_D-RAG\\config\.json') $a.Text

Write-Host ''
Write-Host 'A2 -- the same scope with --project (anchored at the .dproj folder)' -ForegroundColor Cyan
$a2 = Run @('lint-all', '--project', $dproj, '--db', $db)
Check 'A2 3 file(s) scanned: roots are relative to the repository root, not the anchor' ((Scanned $a2.Text) -eq 3) $a2.Text

Write-Host ''
Write-Host 'B -- a project-level "ownRoots" overrides the top-level one' -ForegroundColor Cyan
Set-Config ', "ownRoots": ["App", "Shared"]' ', "ownRoots": ["App"]'
$b = Run @('lint-all', '--db', $db)
Check 'B 2 file(s) scanned (App.dpr, uMain.pas)' ((Scanned $b.Text) -eq 2) $b.Text

Write-Host ''
Write-Host 'C -- an empty "ownRoots" is refused' -ForegroundColor Cyan
Set-Config ', "ownRoots": []' ''
$c = Run @('lint-all', '--db', $db)
Check 'C exit 2' ($c.Code -eq 2) $c.Text
Check 'C the error names config.json' ($c.Text -match 'config\.json.*empty "ownRoots"') $c.Text

Write-Host ''
Write-Host 'W -- the config.json key wins over a loose drag-lint-project.json' -ForegroundColor Cyan
Write-Ascii (Join-Path $dhome 'drag-lint-project.json') '{ "ownRoots": ["Vendor"] }'
Set-Config ', "ownRoots": ["App", "Shared"]' ''
$w = Run @('lint-all', '--db', $db)
Check 'W 3 file(s) scanned (config.json, not the loose ["Vendor"])' ((Scanned $w.Text) -eq 3) $w.Text

Write-Host ''
Write-Host 'D -- CONTROL: without the key the loose file still answers' -ForegroundColor Cyan
Set-Config '' ''
$d = Run @('lint-all', '--db', $db)
Check 'D 1 file scanned (the loose ["Vendor"])' ((Scanned $d.Text) -eq 1) $d.Text

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up.
  foreach ($d23 in @("C:\TEMP\draglint_cfg_ownroots_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
