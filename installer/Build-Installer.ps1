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
#>
param(
  [string] $EngineDir   = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64',
  [string] $Plugin32Dir = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win32',
  [string] $YadfDir     = 'C:\Projects\YADF',
  [string] $GraphvizBin = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin',
  [string] $OutDir      = (Join-Path $PSScriptRoot 'Output'),
  [string] $Iscc        = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  [switch] $DryRun
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
$reported = ((& $engine --version) | Out-String).Trim()
if ($reported -ne "drag-lint $version") {
  throw "the engine at $engine reports '$reported', but DRAGLINT_VERSION is '$version'. Build and deploy that version first, or pass -EngineDir."
}

# ---- every source the .iss names --------------------------------------------
$need = @(
  "$EngineDir\drag-lint.exe", "$EngineDir\drag-lint-config.exe", "$EngineDir\drag-lint-switch.exe",
  "$EngineDir\tree-sitter.dll", "$EngineDir\tree-sitter-delphi13.dll", "$EngineDir\tree-sitter-dfm.dll",
  "$EngineDir\ConvRulesEditor.exe", "$EngineDir\drag_lint_graph.exe", "$EngineDir\dclDragLintWizard.bpl",
  "$Plugin32Dir\dclDragLintWizard.bpl",
  "$GraphvizBin\dot.exe", "$GraphvizBin\config8",
  "$YadfDir\Win64\Release\EXE\YADF.exe", "$YadfDir\Win64\Release\EXE\YADFSetup.exe",
  "$YadfDir\Win32\Release\EXE\YADFOT.bpl", "$YadfDir\Win64\Release\EXE\YADFOT.bpl", "$YadfDir\LICENSE",
  "$repo\installer\drag-lint.starter.json", "$repo\charts\report-pairs.example.json",
  "$repo\charts\src\Ask-Report.ps1", "$repo\charts\src\Register-DragLintProtocol.ps1", "$repo\charts\src\Set-DragLintMcpConfig.ps1",
  "$repo\installer\licenses\drag-lint-LICENSE.txt", "$repo\installer\licenses\graphviz-EPL-2.0.txt"
)
$missing = @($need | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if (-not (Test-Path -LiteralPath "$EngineDir\rules" -PathType Container)) { $missing += "$EngineDir\rules\" }
if ($missing.Count) { throw ("missing source file(s):`n  " + ($missing -join "`n  ")) }

# The BPLs must be the ones the IDE loads: the Win32 plugin from dll-win32 is the
# one registered on the build machine, the Win64 one sits beside the engine.
# A BPL older than the engine it ships with is worth a warning, not a stop.
$bplAge = (Get-Item "$EngineDir\drag-lint.exe").LastWriteTime - (Get-Item "$Plugin32Dir\dclDragLintWizard.bpl").LastWriteTime
if ($bplAge.TotalDays -gt 7) { Write-Warning ("the Win32 plugin BPL is {0:N0} days older than the engine" -f $bplAge.TotalDays) }

$defines = [ordered]@{
  AppVersion = $version; EngineDir = $EngineDir; Plugin32Dir = $Plugin32Dir; YadfDir = $YadfDir
  GraphvizBin = $GraphvizBin; RepoRoot = $repo; OutDir = $OutDir
}
"drag-lint installer $version"
$defines.GetEnumerator() | ForEach-Object { "  /D{0}={1}" -f $_.Key, $_.Value }
if ($DryRun) { 'dry run: all sources present, ISCC not run'; return }

if (-not (Test-Path -LiteralPath $Iscc -PathType Leaf)) { throw "Inno Setup compiler not found: $Iscc" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$isccArgs = @($defines.GetEnumerator() | ForEach-Object { "/D$($_.Key)=$($_.Value)" }) + @('/Qp', (Join-Path $PSScriptRoot 'drag-lint.iss'))
& $Iscc @isccArgs
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }
$setup = Join-Path $OutDir "drag-lint-setup-$version.exe"
"built: $setup ({0:N1} MB)" -f ((Get-Item -LiteralPath $setup).Length / 1MB)
