<#
  run_register_project_in_repo.ps1 -- inside a repository configured by
  _D-RAG\config.json, `register-project` points at `init --project` instead of
  writing the manifest beside the exe (E3b item 6, 2026-10-14).

  THE GAP. register-project asked the anchor-aware manifest whether the project
  was already claimed -- inside a configured repository that is config.json --
  but a project NOT in it was then written into <exe dir>\drag-lint.json and its
  sibling copies. Inside the repository config.json wins over that manifest, so
  the registration had no effect on any later run there: a success message for
  a write nothing reads.

  NOW, inside a configured repository: a project config.json does not list is
  refused (exit 2, outcome "use-init") with the command that adds it,
  `drag-lint init <root> --project <file.dproj>`; one it lists is
  "already-registered", as before. Outside a configured repository nothing
  changes (run_register_project_guard covers the manifest path).

  DRY RUN ONLY. Without --apply nothing is written anywhere, so the pre-fix exe
  cannot touch the real manifest beside it while this runner proves it red.

  CASES:
    U   project not in config.json -> exit 2, outcome "use-init", names init   <- FIX
    L   CONTROL: project listed in config.json -> "already-registered", exit 0
  RED-CHECK: on the pre-fix exe U fails; L passes on both.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_regproj_repo_$PID"
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

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$root  = Join-Path $WorkDir 'repo'
$cfg   = Join-Path $root '_D-RAG\config.json'
$dproj = Join-Path $root 'App\App.dproj'
Write-Ascii $dproj "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <ProjectVersion>18.8</ProjectVersion>`n    <MainSource>App.dpr</MainSource>`n  </PropertyGroup>`n</Project>`n"
Write-Ascii (Join-Path $root 'App\App.dpr') "program App;`nbegin`nend.`n"

function Run([string[]]$argv) {
  Push-Location C:\TEMP
  try {
    $out = & $Exe @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
  } finally { Pop-Location }
}

Write-Host ''
Write-Host 'run_register_project_in_repo -- a configured repository adds projects with init' -ForegroundColor Cyan

Write-Host ''
Write-Host 'U -- a project config.json does not list' -ForegroundColor Cyan
Write-Ascii $cfg '{ "version": 1, "projects": [] }'
$u = Run @('register-project', $dproj, '--json')
$uj = $null; try { $uj = ($u.Text -replace '(?s)^[^{]*', '') | ConvertFrom-Json } catch { }
Check 'U exit 2' ($u.Code -eq 2) $u.Text
Check 'U outcome "use-init"' (($null -ne $uj) -and ($uj.outcome -eq 'use-init')) $u.Text
Check 'U the message names drag-lint init --project' ($u.Text -match 'drag-lint init .*--project') $u.Text
$ut = Run @('register-project', $dproj)
Check 'U text form: exit 2 naming init' (($ut.Code -eq 2) -and ($ut.Text -match 'drag-lint init .*--project')) $ut.Text

Write-Host ''
Write-Host 'L -- CONTROL: a project config.json lists' -ForegroundColor Cyan
Write-Ascii $cfg '{ "version": 1, "projects": [ { "name": "App", "dproj": "App\\App.dproj", "platform": "Win32", "delphi": "20.0" } ] }'
$l = Run @('register-project', $dproj, '--json')
$lj = $null; try { $lj = ($l.Text -replace '(?s)^[^{]*', '') | ConvertFrom-Json } catch { }
Check 'L outcome "already-registered"' (($null -ne $lj) -and ($lj.outcome -eq 'already-registered')) $l.Text
Check 'L exit 0' ($l.Code -eq 0) $l.Text

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up.
  foreach ($d23 in @("C:\TEMP\draglint_regproj_repo_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
