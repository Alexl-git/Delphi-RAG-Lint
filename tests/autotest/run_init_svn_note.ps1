<#
  run_init_svn_note.ps1 -- `drag-lint init` in an SVN working copy says how to
  keep _D-RAG out of `svn status`, without touching any versioned property
  (backlog #33, 2026-10-14).

  THE GAP. init writes a .gitignore inside _D-RAG and, in a CVS working copy, a
  _D-RAG line in <root>\.cvsignore. SVN has neither: ignores are the versioned
  svn:ignore property of the parent folder. In an SVN working copy (the .svn
  folder sits at the working-copy root, often ABOVE the repository root init
  was given -- D:\WorkRepo\.svn for ...\xe) the new _D-RAG showed up
  as "?" in `svn status` and init said nothing.

  NOW: init finds a .svn folder at or above the root and PRINTS the command,
  `svn propedit svn:ignore "<root>"` (add a line _D-RAG). It does not run it --
  changing a versioned property is the user's commit -- and propedit, not
  propset, because propset would replace whatever svn:ignore already holds.

  CASES:
    S   .svn two levels above the root -> the note names the root and propedit <- FIX
    S'  and nothing outside _D-RAG was written (no .cvsignore, .svn untouched)
    K   CONTROL: no .svn anywhere above -> no svn note
  RED-CHECK: on the pre-fix exe S fails; S' and K pass on both.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_init_svn_$PID"
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
function New-Repo([string]$root) {
  Write-Ascii (Join-Path $root 'App\App.dproj') "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <ProjectVersion>18.8</ProjectVersion>`n    <MainSource>App.dpr</MainSource>`n  </PropertyGroup>`n</Project>`n"
  Write-Ascii (Join-Path $root 'App\App.dpr') "program App;`nbegin`nend.`n"
}
function Run([string[]]$argv) {
  Push-Location C:\TEMP
  try {
    $out = & $Exe @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
  } finally { Pop-Location }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }

Write-Host ''
Write-Host 'run_init_svn_note -- init in an SVN working copy' -ForegroundColor Cyan

$wc   = Join-Path $WorkDir 'wc'
$root = Join-Path $wc 'trunk\xe'
New-Item -ItemType Directory (Join-Path $wc '.svn') -Force | Out-Null
Write-Ascii (Join-Path $wc '.svn\wc.db.marker') 'not a real working copy; only the folder matters'
New-Repo $root
$before = @(Get-ChildItem -Recurse -File (Join-Path $wc '.svn') | ForEach-Object { $_.FullName + '|' + $_.Length })

Write-Host ''
Write-Host 'S -- .svn two levels above the root' -ForegroundColor Cyan
$s = Run @('init', $root)
Check 'S init exits 0' ($s.Code -eq 0) $s.Text
Check 'S the note gives svn propedit svn:ignore for the root' ($s.Text -match ('svn propedit svn:ignore "' + [regex]::Escape($root) + '"')) $s.Text
Check 'S and says which line to add' ($s.Text -match 'add a line\s+_D-RAG') $s.Text
Check "S' no .cvsignore was written" (-not (Test-Path (Join-Path $root '.cvsignore'))) ''
$after = @(Get-ChildItem -Recurse -File (Join-Path $wc '.svn') | ForEach-Object { $_.FullName + '|' + $_.Length })
Check "S' the .svn folder is untouched" ((($before -join ';') -eq ($after -join ';'))) (($after -join ';'))

Write-Host ''
Write-Host 'K -- CONTROL: no .svn above the root' -ForegroundColor Cyan
$plain = Join-Path $WorkDir 'plain\xe'
New-Repo $plain
$k = Run @('init', $plain)
Check 'K init exits 0' ($k.Code -eq 0) $k.Text
Check 'K no svn note' (-not ($k.Text -match 'svn:ignore|svn propedit')) $k.Text

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up.
  foreach ($d23 in @("C:\TEMP\draglint_init_svn_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
