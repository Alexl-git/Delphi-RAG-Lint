<#
  prepare_battery.ps1 -- create the UNTRACKED artifacts the battery's guards need,
  so a fresh git worktree does not fail ~7 guards on files that merely were never
  built. Idempotent: an artifact that already exists is left alone (-Force
  rebuilds all). Called by tests\run_battery.ps1 before it runs anything
  (skip with -SkipPrepare there).

  Artifacts (all gitignored; each is a guard prerequisite, not a product):
    tests\calls.sqlite                       run_mcp_protocol_guard
        = engine `index tests\fixtures\Calls.pas` (same as run_phase1_e2e.bat)
    tests\autotest\fixtures\lspproxy\Win64\Debug\LspStubServer.exe
                                             run_lsp_proxy_*_guard (dcc64)
    src\tools\lsp-switch\Win64\Debug\drag-lint-switch.exe
                                             run_lsp_switch_params_guard (msbuild)
    src\tools\uri-handler\Win64\Debug\drag-lint-open.exe
                                             run_uri_handler / run_protocol_verb (STAGED copy)
    tests\fixtures\T2..T7 *.exe              run_v021_doctests.bat (dcc64)
    src\cli\_D-RAG\drag-lint.sqlite          self-index several guards query
        = engine `index --project src\cli\drag-lint.dproj` (slow: minutes)
    src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite
                                             run_menu_drift_guard (plugin self-index)
        = engine `index --project src\delphi-plugin\dclDragLintWizard.dproj`; refreshed
          INCREMENTALLY on every run (a stale one makes that guard GUARD BROKEN)

  The ENGINE (src\cli\Win64\Debug\drag-lint.exe) is NOT built here -- run
  build\build_draglint_win64.bat first. Without it the two engine-made
  artifacts are reported as MISSING (exit 1), never silently skipped.

  Run from any CWD, pwsh 7. Exit 0 = every artifact present, 1 = something missing.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [switch]$Force,
  [switch]$SkipSelfIndex,
  # -Only calls,stub : build just those prerequisites (a standalone guard runner needs two, not the
  # doctest/plugin/self-index set). Implies -SkipSelfIndex.
  [ValidateSet('calls','stub')][string[]]$Only
)
if ($Only) { $SkipSelfIndex = $true }
$ErrorActionPreference = 'Continue'
$root  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$work  = Join-Path $env:TEMP ("draglint-prepare-" + $PID)
New-Item -ItemType Directory -Force -Path $work | Out-Null
$script:missing = New-Object System.Collections.Generic.List[string]

function Say([string]$m) { Write-Host "[prepare_battery] $m" }

# Run a 3-line wrapper .bat (rsvars -> cd -> command) with output to a log, per
# the delphi-build recipe. Returns the log path.
function Invoke-Wrapped([string]$Name, [string]$Cmd) {
  $bat = Join-Path $work "$Name.bat"
  $log = Join-Path $work "$Name.log"
  $lines = @('@echo off', ('call "{0}" >NUL' -f $rsvars), ('cd /d "{0}"' -f $root), $Cmd)
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  Start-Process -FilePath $bat -Wait -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  $script:lastLog = $log
  return $log
}

function Need([string]$Path, [string]$What, [scriptblock]$Make) {
  if ((Test-Path -LiteralPath $Path) -and -not $Force) { Say "ok      $What"; return }
  Say "building $What"
  & $Make
  if (Test-Path -LiteralPath $Path) { Say "created $What" }
  else {
    Say "MISSING $What ($Path)"; $script:missing.Add($What)
    if ($script:lastLog -and (Test-Path -LiteralPath $script:lastLog)) { Select-String -LiteralPath $script:lastLog -Pattern 'Error|Fatal' | Select-Object -First 5 | ForEach-Object { Say ('  ' + $_.Line) } }
  }
}

# --- calls.sqlite --------------------------------------------------------
$calls = Join-Path $root 'tests\calls.sqlite'
if ((-not $Only) -or ($Only -contains 'calls')) { Need $calls 'tests\calls.sqlite' {
  if (Test-Path -LiteralPath $Exe) {
    if (Test-Path -LiteralPath $calls) { [IO.File]::Delete($calls) }
    $null = & $Exe index (Join-Path $root 'tests\fixtures\Calls.pas') --db $calls 2>&1
  } else { Say "  engine not built: $Exe (run build\build_draglint_win64.bat)" }
} }

# --- LspStubServer.exe -----------------------------------------------------
$stubDir = Join-Path $root 'tests\autotest\fixtures\lspproxy'
$stub = Join-Path $stubDir 'Win64\Debug\LspStubServer.exe'
if ((-not $Only) -or ($Only -contains 'stub')) { Need $stub 'LspStubServer.exe' {
  New-Item -ItemType Directory -Force -Path (Join-Path $stubDir 'Win64\Debug') | Out-Null
  $dcu = Join-Path $work 'dcu-stub'; New-Item -ItemType Directory -Force -Path $dcu | Out-Null
  $null = Invoke-Wrapped 'stub' ('dcc64 -NU"{0}" -E"{1}" -U"{2}" "{3}\LspStubServer.dpr"' -f $dcu, (Join-Path $stubDir 'Win64\Debug'), $stubDir, $stubDir)
} }

if (-not $Only) {
# --- drag-lint-switch.exe --------------------------------------------------
$sw = Join-Path $root 'src\tools\lsp-switch\Win64\Debug\drag-lint-switch.exe'
Need $sw 'drag-lint-switch.exe' {
  $null = Invoke-Wrapped 'switch' 'msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal src\tools\lsp-switch\drag-lint-switch.dproj'
}

# --- drag-lint-open.exe (X-06) ---------------------------------------------
# Staged (copied from the main checkout / dll-win64), never built here; the same helper the
# run_uri_handler / run_protocol_verb guards use, so a fresh worktree battery starts GREEN on them.
. (Join-Path $PSScriptRoot 'lib\UriHandlerExe.ps1')
$openExe = Join-Path $root 'src\tools\uri-handler\Win64\Debug\drag-lint-open.exe'
Need $openExe 'drag-lint-open.exe' { [void](Initialize-UriHandlerExe -Path $openExe) }

# --- T2..T7 doctest fixtures -----------------------------------------------
$fx = Join-Path $root 'tests\fixtures'
$srcDirs = ((Get-ChildItem -LiteralPath (Join-Path $root 'src') -Directory | ForEach-Object { $_.FullName }) + (Join-Path $root 'third_party\delphi-tree-sitter')) -join ';'
foreach ($t in 'T2_typecheck','T3_regions','T4_xmldoc','T5_pasdoc','T6_dispatch','T7_storage') {
  $fxExe = Join-Path $fx "$t.exe"
  Need $fxExe "$t.exe" {
    $dcu = Join-Path $work "dcu-$t"; New-Item -ItemType Directory -Force -Path $dcu | Out-Null
    $null = Invoke-Wrapped $t ('dcc64 "-NSSystem;System.Win;Winapi;Data" -NU"{0}" -E"{1}" -U"{2}" "{3}\{4}.dpr"' -f $dcu, $fx, $srcDirs, $fx, $t)
  }
}

}
# --- self-index ----------------------------------------------------------
if (-not $SkipSelfIndex) {
  $self = Join-Path $root 'src\cli\_D-RAG\drag-lint.sqlite'
  Need $self 'src\cli\_D-RAG\drag-lint.sqlite (self-index)' {
    if (Test-Path -LiteralPath $Exe) {
      New-Item -ItemType Directory -Force -Path (Split-Path $self) | Out-Null
      $o = & $Exe index --project (Join-Path $root 'src\cli\drag-lint.dproj') --db $self 2>&1 | Out-String
      if (-not (Test-Path -LiteralPath $self)) { Say ('  engine output tail: ' + (($o -split "`n" | Select-Object -Last 3) -join ' | ')) }
    } else { Say "  engine not built: $Exe" }
  }
  # Plugin self-index (run_menu_drift_guard). Unlike the artifacts above it is
  # refreshed on EVERY run, incrementally (seconds when nothing changed): an
  # existing-but-stale index would make the guard refuse with exit 3.
  $plug = Join-Path $root 'src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite'
  if (Test-Path -LiteralPath $Exe) {
    New-Item -ItemType Directory -Force -Path (Split-Path $plug) | Out-Null
    Say 'refreshing src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite (plugin self-index, incremental)'
    $o = & $Exe index --project (Join-Path $root 'src\delphi-plugin\dclDragLintWizard.dproj') --db $plug 2>&1 | Out-String
    if (-not (Test-Path -LiteralPath $plug)) { Say ('  engine output tail: ' + (($o -split "`n" | Select-Object -Last 3) -join ' | ')) }
  } else { Say "  engine not built: $Exe" }
  if (Test-Path -LiteralPath $plug) { Say 'ok      plugin self-index' }
  else { Say "MISSING plugin self-index ($plug)"; $script:missing.Add('plugin self-index') }
}

if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
if ($script:missing.Count -gt 0) {
  Say ("MISSING: " + ($script:missing -join ', ') + ' -- guards that need them will fail')
  exit 1
}
Say 'all battery prerequisites present'
exit 0
