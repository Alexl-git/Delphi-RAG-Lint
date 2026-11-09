<#
  EngineCompanions.ps1 -- dot-source helper: make a worktree-built engine runnable and
  its rules\ catalogue current, the way build\build_draglint_win64.bat does, WITHOUT the
  deploy step (that bat copies into third_party\dll-win64, which a lane must never do).

  WHY THIS EXISTS (1.40 lane guard, GUARD-STANDALONE / RULES-STALE-DIR / GUARD-RED-LSP):
    * A fresh worktree that only ran `msbuild drag-lint.dproj` has src\cli\Win64\Debug\
      drag-lint.exe with NO companions beside it. It starts, prints nothing and exits
      non-zero (no sqlite3.dll / tree-sitter dlls), so `index` writes no DB and a guard
      reports a misleading "FATAL: index produced no library DB" / "test db not found".
    * <exe-dir>\rules is a gitignored COPY of repo rules\; it goes stale (113 files vs 197
      seen) and docs_sync / feature-registry then compare README counts with a stale
      catalogue and fail falsely.

  Initialize-EngineCompanions -Exe <path> [-Repo <root>]
    Acts ONLY when -Exe is <Repo>\src\cli\Win64\Debug\drag-lint.exe (a build output of this
    very tree). Any other exe (the deployed dll-win64 one, a baseline copy) is returned
    untouched: those are somebody else's artefacts, and the stage must never edit them.
    Copies, only when missing or older than the source: tree-sitter*.dll (from
    third_party\dll-win64), casts.castlib, sqlite3.dll (Studio 37.0 bin64).
    Mirrors rules\*.scm|*.json|builtin-symbols.txt|enum-persist-sinks.txt into <exe-dir>\rules,
    deleting orphans (an orphan .scm would load beside its replacement under the same id).
  Returns $true when it staged (or found current), $false when -Exe is not a build output
  of this tree (nothing touched).
#>
function Initialize-EngineCompanions {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Exe,
    [string] $Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
    [string] $SqliteSrc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\sqlite3.dll'
  )
  if (-not (Test-Path -LiteralPath $Exe)) { return $false }
  $exeDir  = Split-Path -Parent (Resolve-Path -LiteralPath $Exe).Path
  $buildDir = Join-Path (Resolve-Path -LiteralPath $Repo).Path 'src\cli\Win64\Debug'
  if (-not (Test-Path -LiteralPath $buildDir)) { return $false }
  if ((Resolve-Path -LiteralPath $exeDir).Path -ne (Resolve-Path -LiteralPath $buildDir).Path) { return $false }

  function CopyIfNewer([string]$Src, [string]$Dst) {
    if (-not (Test-Path -LiteralPath $Src)) { return }
    if ((-not (Test-Path -LiteralPath $Dst)) -or ((Get-Item -LiteralPath $Src).LastWriteTimeUtc -gt (Get-Item -LiteralPath $Dst).LastWriteTimeUtc)) {
      Copy-Item -LiteralPath $Src -Destination $Dst -Force
    }
  }
  foreach ($dll in (Get-ChildItem -LiteralPath (Join-Path $Repo 'third_party\dll-win64') -Filter 'tree-sitter*.dll' -ErrorAction SilentlyContinue)) {
    CopyIfNewer $dll.FullName (Join-Path $exeDir $dll.Name)
  }
  CopyIfNewer (Join-Path $Repo 'docs\examples\convrules\casts.castlib') (Join-Path $exeDir 'casts.castlib')
  CopyIfNewer $SqliteSrc (Join-Path $exeDir 'sqlite3.dll')

  $rulesSrc = Join-Path $Repo 'rules'
  $rulesDst = Join-Path $exeDir 'rules'
  if (Test-Path -LiteralPath $rulesSrc) {
    [void](New-Item -ItemType Directory -Force -Path $rulesDst)
    $want = @(Get-ChildItem -LiteralPath $rulesSrc -File | Where-Object { $_.Extension -in '.scm', '.json' -or $_.Name -in 'builtin-symbols.txt', 'enum-persist-sinks.txt' })
    $wantNames = @($want | ForEach-Object { $_.Name })
    foreach ($old in (Get-ChildItem -LiteralPath $rulesDst -File | Where-Object { $_.Extension -in '.scm', '.json' -and $wantNames -notcontains $_.Name })) {
      [IO.File]::Delete($old.FullName)
    }
    foreach ($f in $want) {
      $dst = Join-Path $rulesDst $f.Name
      if ((-not (Test-Path -LiteralPath $dst)) -or ((Get-Item -LiteralPath $dst).Length -ne $f.Length) -or ((Get-Item -LiteralPath $dst).LastWriteTimeUtc -lt $f.LastWriteTimeUtc)) {
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
      }
    }
  }
  return $true
}

<#
  Initialize-DeployedEngineStage -Repo <root>   (GD 148, 1.39 #9)
    ~1000 guards default -Exe to <Repo>\third_party\dll-win64\drag-lint.exe, which a fresh worktree does not have
    (the deploy step is the controller's). When that exe is missing and this tree's own build output
    <Repo>\src\cli\Win64\Debug\drag-lint.exe exists, copy it plus its companions (*.dll, casts.castlib, rules\)
    into the worktree's OWN third_party\dll-win64 (gitignored), so a worktree battery does not start with
    hundreds of "exe not found". An existing dll-win64 exe is NEVER touched (that is a deployed artefact).
    Returns $true when it staged, $false when nothing was done.
#>
function Initialize-DeployedEngineStage {
  [CmdletBinding()]
  param([string] $Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
  $dst = Join-Path $Repo 'third_party\dll-win64'
  $built = Join-Path $Repo 'src\cli\Win64\Debug'
  if (Test-Path -LiteralPath (Join-Path $dst 'drag-lint.exe')) { return $false }
  if (-not (Test-Path -LiteralPath (Join-Path $built 'drag-lint.exe'))) { return $false }
  [void](New-Item -ItemType Directory -Force -Path $dst)
  foreach ($f in (Get-ChildItem -LiteralPath $built -File | Where-Object { $_.Extension -in '.exe', '.dll' -or $_.Name -in 'casts.castlib', 'drag-lint.json' })) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dst $f.Name) -Force
  }
  if (Test-Path -LiteralPath (Join-Path $built 'rules')) {
    Copy-Item -LiteralPath (Join-Path $built 'rules') -Destination $dst -Recurse -Force
  }
  return $true
}
