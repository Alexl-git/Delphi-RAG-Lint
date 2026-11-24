<#
  Build-Installer.ps1 -- compiles installer\drag-lint.iss into drag-lint-setup-<version>.exe.

  Use this, not ISCC directly: it is what keeps the setup honest.
    * The version comes from DRAGLINT_VERSION (src\core\DRagLint.Core.Model.pas),
      the product's one version number (owner D6) -- never typed twice.
    * The engine being shipped must REPORT that version (`drag-lint.exe --version`).
      A setup labelled 1.29 that installs a 1.28 engine is the failure this stops.
    * Every source file the .iss names must exist before ISCC runs, so a missing
      file is one clear line here instead of an ISCC error halfway through.

  Nothing is installed and nothing is deployed; the only output is the setup exe.

  -DryRun prints the defines and the checks without running ISCC.
  -LayoutV2 builds the installed-layout-v2 setup (phase 4; manifest in %APPDATA%). OFF by
  default: without it the setup installs the flat v1 layout. Not for release before the
  plugin lookups (phase 3) and the VM test (VM-TEST-CHECKLIST.md section L).
#>
param(
  [string] $EngineDir   = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64',
  [string] $Plugin32Dir = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win32',
  [string] $YadfDir     = 'C:\Projects\YADF',
  [string] $GraphvizBin = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin',
  [string] $OutDir      = (Join-Path $PSScriptRoot 'Output'),
  [string] $ToolsDir    = '',  # the folder of dl-field-repo.exe / dl-field-repo-std.exe; '' = src\tools\field-repo
  [string] $HelpIndex   = '',  # the offline feature list; '' = <repo>\WWW\help\dl\index.json
  [string] $VcRedistDir = '',  # folder of vcruntime140.dll (x64); '' = the newest Visual Studio redist folder
  [string] $EngineSha256 = '', # when given, the engine must have exactly this hash
  [string] $Iscc        = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  [string] $IsccLog     = '',  # when given, ISCC runs verbosely and its output (one line per packed file) goes there
  [switch] $DryRun,
  [switch] $LayoutV2
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

# ---- version (owner D6) ------------------------------------------------------
$model = Join-Path $repo 'src\core\DRagLint.Core.Model.pas'
$m = Select-String -LiteralPath $model -Pattern "^\s*DRAGLINT_VERSION\s*=\s*'([^']+)'" | Select-Object -First 1
if (-not $m) { throw "DRAGLINT_VERSION not found in $model" }
$version = $m.Matches[0].Groups[1].Value

$engine = Join-Path $EngineDir 'drag-lint.exe'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "engine not found: $engine" }
if ($EngineSha256 -ne '') {
  $h = (Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
  if ($h -ne $EngineSha256) { throw "the engine at $engine has SHA256 $h, expected $EngineSha256" }
}
if ($ToolsDir -eq '') { $ToolsDir = Join-Path $repo 'src\tools\field-repo' }
if ($HelpIndex -eq '') { $HelpIndex = Join-Path $repo 'WWW\help\dl\index.json' }
. (Join-Path $repo 'build\VcRuntime.ps1')
$VcRedistDir = Resolve-VcRuntimeDir 'x64' $VcRedistDir
$reported = ((& $engine --version) | Out-String).Trim()
if ($reported -ne "drag-lint $version") {
  throw "the engine at $engine reports '$reported', but DRAGLINT_VERSION is '$version'. Build and deploy that version first, or pass -EngineDir."
}

# ---- every source the .iss names --------------------------------------------
$need = @(
  "$EngineDir\drag-lint.exe", "$EngineDir\drag-lint-config.exe", "$EngineDir\drag-lint-switch.exe",
  "$EngineDir\sqlite3.dll", "$EngineDir\tree-sitter.dll", "$EngineDir\tree-sitter-delphi13.dll", "$EngineDir\tree-sitter-dfm.dll",
  "$EngineDir\ConvRulesEditor.exe", "$EngineDir\drag_lint_graph.exe", "$EngineDir\dclDragLintWizard.bpl",
  "$Plugin32Dir\dclDragLintWizard.bpl",
  "$GraphvizBin\dot.exe", "$GraphvizBin\config8",
  "$YadfDir\Win64\Release\EXE\YADF.exe", "$YadfDir\Win64\Release\EXE\YADFSetup.exe",
  "$YadfDir\Win32\Release\EXE\YADFOT.bpl", "$YadfDir\Win64\Release\EXE\YADFOT.bpl", "$YadfDir\LICENSE",
  "$repo\installer\drag-lint.starter.json", "$repo\installer\drag-lint.starter-v2.json", "$repo\charts\report-pairs.example.json",
  "$EngineDir\drag-lint-open.exe",
  "$ToolsDir\dl-field-repo.exe", "$ToolsDir\dl-field-repo-std.exe",
  "$VcRedistDir\vcruntime140.dll", $HelpIndex,
  "$repo\docs\examples\convrules\casts.castlib", "$repo\convrules\sample.rules", "$repo\convrules\BDE-to-FireDAC.rules",
  "$repo\convrules\vendor\FireDAC_Migrate_BDE.rules", "$repo\convrules\vendor\FireDAC_Rename_Units.rules", "$repo\convrules\vendor\README.md",
  "$repo\installer\licenses\drag-lint-LICENSE.txt", "$repo\installer\licenses\graphviz-EPL-2.0.txt"
)
$missing = @($need | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if (-not (Test-Path -LiteralPath "$EngineDir\rules" -PathType Container)) { $missing += "$EngineDir\rules\" }
if ($missing.Count) { throw ("missing source file(s):`n  " + ($missing -join "`n  ")) }

# The C runtime: the .iss ships exactly vcruntime140.dll in bin\, so nothing that goes to bin\ may
# import any other C runtime DLL (Graphviz brings its own in bin\graphviz\bin).
Assert-VcRuntimeFile "$VcRedistDir\vcruntime140.dll" 'x64'
$binPe = @('drag-lint.exe','drag-lint-config.exe','drag-lint-switch.exe','drag-lint-open.exe','sqlite3.dll','tree-sitter.dll',
  'tree-sitter-delphi13.dll','tree-sitter-dfm.dll','ConvRulesEditor.exe','drag_lint_graph.exe' | ForEach-Object { Join-Path $EngineDir $_ })
$binPe += "$ToolsDir\dl-field-repo.exe", "$ToolsDir\dl-field-repo-std.exe", "$VcRedistDir\vcruntime140.dll"
$vcMissing = @(Get-VcRuntimeNeeded $binPe)
if ($vcMissing.Count) { throw ("C runtime DLL(s) needed in bin\ that drag-lint.iss does not ship: " + ($vcMissing -join ', ')) }
$yadfMissing = @(Get-VcRuntimeNeeded @("$YadfDir\Win64\Release\EXE\YADF.exe", "$YadfDir\Win64\Release\EXE\YADFSetup.exe"))
if ($yadfMissing.Count) { throw ("C runtime DLL(s) needed in yadf\ that drag-lint.iss does not ship: " + ($yadfMissing -join ', ')) }

# The BPLs must be the ones the IDE loads: the Win32 plugin from dll-win32 is the
# one registered on the build machine, the Win64 one sits beside the engine.
# A BPL older than the engine it ships with is worth a warning, not a stop.
$bplAge = (Get-Item "$EngineDir\drag-lint.exe").LastWriteTime - (Get-Item "$Plugin32Dir\dclDragLintWizard.bpl").LastWriteTime
if ($bplAge.TotalDays -gt 7) { Write-Warning ("the Win32 plugin BPL is {0:N0} days older than the engine" -f $bplAge.TotalDays) }
# The Win64 BPL (64-bit IDE) has no build script of its own and was once packed six weeks
# stale (2026-10-13), so it gets the same check.
$bpl64Age = (Get-Item "$EngineDir\drag-lint.exe").LastWriteTime - (Get-Item "$EngineDir\dclDragLintWizard.bpl").LastWriteTime
if ($bpl64Age.TotalDays -gt 7) { Write-Warning ("the Win64 plugin BPL is {0:N0} days older than the engine" -f $bpl64Age.TotalDays) }

# Numeric x.y.z.0 for the Windows version resource (Inno needs four numeric fields).
$numMatch = [regex]::Match($version, '^(\d+)\.(\d+)\.(\d+)')
if (-not $numMatch.Success) { throw "DRAGLINT_VERSION '$version' does not start with x.y.z" }
$numericVersion = ($numMatch.Groups[1..3] | ForEach-Object { $_.Value }) -join '.'
$numericVersion += '.0'

$defines = [ordered]@{
  AppVersion = $version; NumericVersion = $numericVersion; EngineDir = $EngineDir; Plugin32Dir = $Plugin32Dir; YadfDir = $YadfDir
  GraphvizBin = $GraphvizBin; RepoRoot = $repo; OutDir = $OutDir
  ToolsDir = $ToolsDir; HelpIndex = $HelpIndex; VcRedistDir = $VcRedistDir
}
if ($LayoutV2) { $defines['LayoutV2'] = '1' }
"drag-lint installer $version"
$defines.GetEnumerator() | ForEach-Object { "  /D{0}={1}" -f $_.Key, $_.Value }
if ($DryRun) { 'dry run: all sources present, ISCC not run'; return }

if (-not (Test-Path -LiteralPath $Iscc -PathType Leaf)) { throw "Inno Setup compiler not found: $Iscc" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$isccArgs = @($defines.GetEnumerator() | ForEach-Object { "/D$($_.Key)=$($_.Value)" }) + @(Join-Path $PSScriptRoot 'drag-lint.iss')
if ($IsccLog -ne '') { & $Iscc @isccArgs *> $IsccLog } else { & $Iscc '/Qp' @isccArgs }
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
$setup = Join-Path $OutDir "drag-lint-setup-$version.exe"
"built: $setup ({0:N1} MB)" -f ((Get-Item -LiteralPath $setup).Length / 1MB)
