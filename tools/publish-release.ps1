#Requires -Version 7.3
<#
  publish-release.ps1 -Version <X.Y.Z-alpha> [-DryRun] [-SkipBuild] [-SkipBattery] [-BuildPlugin] [-Repo <root>]

  The publish pipeline of spec section 12, in one place, stopping at the first
  failure (owner decision 15.6). Steps:
    0  preflight: -Version == DRAGLINT_VERSION; CHANGELOG.md has '## v<Version>';
       the deployed engine exists
    1  build the engine (build\build_draglint_win64.bat)        [-SkipBuild]
       [-BuildPlugin] also src\delphi-plugin\_bpl_build.bat -- OFF by default: that
       build writes the BPL into third_party\dll-win32, the registered Known
       Packages path, i.e. it DEPLOYS into the live IDE (RAD Studio must be closed)
    2  tools\build-feature-pages.ps1 -Check   (gate: generated pages are committed)
    3  tools\build-manual.ps1                 (exactly once, after the last doc change,
                                               BEFORE the battery so
                                               run_manual_freshness_guard.ps1 sees it)
    4  tests\run_battery.ps1                  [-SkipBattery]
    5  tools\publish-wiki.ps1                 (itself re-runs the -Check gate)
    6  build\pack-lint-release.ps1 -Version   wrapped in Invoke-WithEngineBackup: the
       deployed DEBUG engine in third_party\dll-win64 is restored byte-identically (sha256)
    7  prints the git tag + gh release create commands (still run by hand)

  -DryRun  prints the plan with resolved paths and runs only steps 0 and 2;
           exit 0 when both pass, 1 otherwise. Nothing is built, published or packed.
  -Repo    repository root (default: the parent of this script's folder); the
           steps run the scripts under it.
  Exit codes: 0 = every step passed; 1 = stopped at the step named in red.

  ORDER vs spec section 12: section 12 lists the battery before the manual. The
  manual runs first here because the battery's run_manual_freshness_guard.ps1
  FAILS on a manual older than the wiki, and the manual reads no battery output;
  both orders rebuild it exactly once, after the last doc change (15.6).
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Version, [switch]$DryRun, [switch]$SkipBuild, [switch]$SkipBattery, [switch]$BuildPlugin,
      [string]$Repo = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path -LiteralPath $Repo).Path
. (Join-Path $PSScriptRoot 'lib\ReleaseGuard.ps1')
$engine = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe'
if ($DryRun) { Write-Host "DRY RUN -- plan for v$Version (steps 0 and 2 run, the rest are printed)" -ForegroundColor Yellow }

function Stop-At([int]$N, [string]$Why) { Write-Host "STOP at step $N -- $Why" -ForegroundColor Red; exit 1 }
function Invoke-Step([int]$N, [string]$Name, [string[]]$Cmd, [bool]$Skip = $false, [bool]$RunInDryRun = $false) {
  Write-Host ("== step {0}/7: {1}" -f $N, $Name) -ForegroundColor Cyan
  Write-Host ("   {0}" -f ($Cmd -join ' ')) -ForegroundColor DarkGray
  if ($Skip) { Write-Host '   SKIPPED by switch' -ForegroundColor Yellow; return }
  if ($DryRun -and -not $RunInDryRun) { Write-Host '   (dry run: not executed)' -ForegroundColor DarkGray; return }
  $exe = $Cmd[0]; $rest = @($Cmd | Select-Object -Skip 1)
  & $exe @rest | Out-Host
  if ($LASTEXITCODE -ne 0) { Stop-At $N "$Name exited $LASTEXITCODE" }
}

# ---- 0 preflight ---------------------------------------------------------------
Write-Host '== step 0/7: preflight' -ForegroundColor Cyan
$src = [regex]::Match((Get-Content -LiteralPath (Join-Path $Repo 'src\core\DRagLint.Core.Model.pas') -Raw), "DRAGLINT_VERSION\s*=\s*'([^']+)'").Groups[1].Value
if ($src -ne $Version) { Stop-At 0 "-Version $Version but DRAGLINT_VERSION in src\core\DRagLint.Core.Model.pas is '$src' -- bump the constant (and CHANGELOG) first, then rebuild" }
if (-not ((Get-Content -LiteralPath (Join-Path $Repo 'CHANGELOG.md') -Raw) -match ('(?m)^## v' + [regex]::Escape($Version) + '\b'))) { Stop-At 0 "CHANGELOG.md has no '## v$Version' heading" }
if (-not (Test-Path -LiteralPath $engine)) { Stop-At 0 "deployed engine not found: $engine" }
$pluginBat = Join-Path $Repo 'src\delphi-plugin\_bpl_build.bat'
if ($BuildPlugin -and -not (Test-Path -LiteralPath $pluginBat)) { Stop-At 0 "-BuildPlugin but the plugin build script is missing: $pluginBat" }
Write-Host "   version $Version, engine sha $((Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash.Substring(0, 12))..." -ForegroundColor DarkGray

# ---- 1 build the engine (and optionally the plugin) ------------------------------
Invoke-Step 1 'build the engine' @('cmd.exe', '/c', (Join-Path $Repo 'build\build_draglint_win64.bat')) -Skip $SkipBuild.IsPresent
if ($BuildPlugin) { Invoke-Step 1 'build the plugin (DEPLOYS into the live IDE)' @('cmd.exe', '/c', $pluginBat) -Skip $SkipBuild.IsPresent }
# ---- 2 gate: generated pages are current ------------------------------------------
Invoke-Step 2 'build-feature-pages.ps1 -Check' @('pwsh', '-NoProfile', '-File', (Join-Path $Repo 'tools\build-feature-pages.ps1'), '-Check') -RunInDryRun $true
# ---- 3 the manual, once -----------------------------------------------------------
Invoke-Step 3 'build-manual.ps1' @('pwsh', '-NoProfile', '-File', (Join-Path $Repo 'tools\build-manual.ps1'))
# ---- 4 the battery ----------------------------------------------------------------
Invoke-Step 4 'run_battery.ps1' @('pwsh', '-NoProfile', '-File', (Join-Path $Repo 'tests\run_battery.ps1')) -Skip $SkipBattery.IsPresent
# ---- 5 the wiki -------------------------------------------------------------------
Invoke-Step 5 'publish-wiki.ps1' @('pwsh', '-NoProfile', '-File', (Join-Path $Repo 'tools\publish-wiki.ps1'))
# ---- 6 the release archives, with the deployed engine protected -------------------
Write-Host '== step 6/7: pack-lint-release.ps1 (deployed Debug engine backed up, restored, sha-verified)' -ForegroundColor Cyan
$packScript = Join-Path $Repo 'build\pack-lint-release.ps1'
Write-Host ("   pwsh -NoProfile -File {0} -Version {1}" -f $packScript, $Version) -ForegroundColor DarkGray
Write-Host ("   protected: {0}" -f $engine) -ForegroundColor DarkGray
if ($DryRun) { Write-Host '   (dry run: not executed)' -ForegroundColor DarkGray }
else {
  $r = Invoke-WithEngineBackup -EnginePath $engine -Action { & pwsh -NoProfile -File $packScript -Version $Version | Out-Host; if ($LASTEXITCODE -ne 0) { throw "pack-lint-release.ps1 exited $LASTEXITCODE" } }
  Write-Host ("   engine restored: sha {0}... == {1}..." -f $r.ShaBefore.Substring(0, 12), $r.ShaAfter.Substring(0, 12)) -ForegroundColor Green
  if ($r.ActionError) { Stop-At 6 $r.ActionError }
}
# ---- 7 tag + release: still by hand -------------------------------------------------
Write-Host '== step 7/7: git tag + gh release create (run by hand)' -ForegroundColor Cyan
Write-Host "   git tag v$Version && git push origin v$Version" -ForegroundColor Yellow
Write-Host "   gh release create v$Version C:\TEMP\rel-$Version\drag-lint-v$Version-win64.zip C:\TEMP\rel-$Version\drag-lint-v$Version-win32.zip --title v$Version --notes-file <notes.md>" -ForegroundColor Yellow
Write-Host $(if ($DryRun) { "DRY RUN complete for v$Version" } else { "publish pipeline complete for v$Version" }) -ForegroundColor Green
exit 0
