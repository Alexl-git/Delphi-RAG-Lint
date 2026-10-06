#Requires -Version 7.3
<#
  run_publish_release_guard.ps1 -- the release orchestrator exists, runs the
  publish steps in the spec's order, gates on the generated pages, and
  restores the deployed Debug engine byte-identically after the Release pack
  overwrites it (the hazard the 1.21.1 hand publish hit; spec 15.6).
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$WorkDir = "$env:TEMP\drag-lint-publish-release-$PID")
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
function Sha($f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
Write-Host '== publish-release orchestrator ==' -ForegroundColor Cyan
$lib = Join-Path $Repo 'tools\lib\ReleaseGuard.ps1'
$orch = Join-Path $Repo 'tools\publish-release.ps1'
Check 'ReleaseGuard.ps1 present' (Test-Path -LiteralPath $lib) $lib
Check 'publish-release.ps1 present' (Test-Path -LiteralPath $orch) $orch
if (-not (Test-Path -LiteralPath $lib) -or -not (Test-Path -LiteralPath $orch)) { Write-Host 'PUBLISH RELEASE GUARD: FAIL' -ForegroundColor Red; exit 1 }
. $lib
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

# --- the backup/restore primitive, on a scratch "engine" ---------------------
$engine = Join-Path $WorkDir 'drag-lint.exe'
[IO.File]::WriteAllBytes($engine, [byte[]](1..64))
$before = Sha $engine
$r = Invoke-WithEngineBackup -EnginePath $engine -BackupDir (Join-Path $WorkDir 'bak1') -Action { [IO.File]::WriteAllBytes($engine, [byte[]](9, 9, 9)) }
Check 'an action that overwrites the engine is undone, sha verified' ($r.Restored -and ($r.ShaAfter -eq $before) -and ((Sha $engine) -eq $before))
Check 'the backup file is removed after a verified restore' (-not (Test-Path -LiteralPath (Join-Path $WorkDir 'bak1\drag-lint.exe.bak')))
$r = Invoke-WithEngineBackup -EnginePath $engine -BackupDir (Join-Path $WorkDir 'bak2') -Action { [IO.File]::WriteAllBytes($engine, [byte[]](7)); throw 'pack failed' }
Check 'an action that throws still restores, and the error is reported' ($r.Restored -and ($r.ActionError -eq 'pack failed') -and ((Sha $engine) -eq $before))
$threw = ''
try { Invoke-WithEngineBackup -EnginePath $engine -BackupDir (Join-Path $WorkDir 'bak3') -Action { Remove-Item -LiteralPath (Join-Path $WorkDir 'bak3\drag-lint.exe.bak') -Force; [IO.File]::WriteAllBytes($engine, [byte[]](5)) } | Out-Null } catch { $threw = $_.Exception.Message }
Check 'POSITIVE CONTROL: a sabotaged restore is reported, never silent' ($threw -like '*NOT RESTORED*') $threw
[IO.File]::WriteAllBytes($engine, [byte[]](1..64))

# --- the orchestrator: dry run, order, gates -----------------------------------
$ver = [regex]::Match((Get-Content -LiteralPath (Join-Path $Repo 'src\core\DRagLint.Core.Model.pas') -Raw), "DRAGLINT_VERSION\s*=\s*'([^']+)'").Groups[1].Value
$out = & pwsh -NoProfile -File $orch -Version $ver -DryRun 2>&1 | Out-String
Check 'dry run exits 0 on the live version' ($LASTEXITCODE -eq 0) (($out -split "`n" | Select-Object -Last 2) -join ' ')
$idx = @('build the engine', 'build-feature-pages.ps1 -Check', 'build-manual.ps1', 'run_battery.ps1', 'publish-wiki.ps1', 'pack-lint-release.ps1', 'git tag') | ForEach-Object { $out.IndexOf($_) }
Check 'dry run lists all seven steps' (@($idx | Where-Object { $_ -lt 0 }).Count -eq 0) ($idx -join ',')
Check 'steps are in order: build, generate -Check, manual, battery, wiki, pack, tag' ((($idx | ForEach-Object { $_ }) -join ',') -eq (($idx | Sort-Object) -join ','))
Check 'dry run says it is a dry run and ran the -Check gate' (($out -match 'DRY RUN') -and ($out -match 'feature pages: current'))
$out = & pwsh -NoProfile -File $orch -Version '0.0.1-alpha' -DryRun 2>&1 | Out-String
Check 'a version that is not DRAGLINT_VERSION stops at preflight' (($LASTEXITCODE -eq 1) -and ($out -match 'DRAGLINT_VERSION'))

# --- the orchestrator end to end, on a STUB tree ------------------------------------
# Every step script under the stub root only appends its name to steps.log and
# exits 1 when a 'fail-<name>' marker exists; the stub pack also overwrites the
# stub engine, exactly the hazard 15.6 names. The orchestrator and its lib are
# COPIED into the stub so that both -Repo and the script's own default point at
# scratch: nothing here can reach the real build, battery, wiki or pack.
function Write-Ascii([string]$Path, [string]$Text) {
  New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
  [IO.File]::WriteAllText($Path, (($Text -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function New-StubTree([string]$Root) {
  $log = Join-Path $Root 'steps.log'
  $ps = { param($name, $extra) "`$ErrorActionPreference = 'Stop'`nAdd-Content -LiteralPath '$log' -Value '$name'`n$extra`nif (Test-Path -LiteralPath '$(Join-Path $Root "fail-$name")') { exit 1 }`nexit 0`n" }
  Write-Ascii (Join-Path $Root 'src\core\DRagLint.Core.Model.pas') "const DRAGLINT_VERSION = '9.9.9-alpha';`n"
  Write-Ascii (Join-Path $Root 'CHANGELOG.md') "# Changelog`n`n## v9.9.9-alpha`n`n- stub`n"
  New-Item -ItemType Directory -Path (Join-Path $Root 'third_party\dll-win64') -Force | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $Root 'third_party\dll-win64\drag-lint.exe'), [byte[]](1..64))
  Write-Ascii (Join-Path $Root 'build\build_draglint_win64.bat') "@echo off`necho build>>`"$log`"`nif exist `"$(Join-Path $Root 'fail-build')`" exit /b 1`nexit /b 0`n"
  Write-Ascii (Join-Path $Root 'tools\build-feature-pages.ps1') (& $ps 'gate' "Write-Host 'feature pages: current'")
  Write-Ascii (Join-Path $Root 'tools\build-manual.ps1') (& $ps 'manual' '')
  Write-Ascii (Join-Path $Root 'tests\run_battery.ps1') (& $ps 'battery' '')
  Write-Ascii (Join-Path $Root 'tools\publish-wiki.ps1') (& $ps 'wiki' '')
  Write-Ascii (Join-Path $Root 'build\pack-lint-release.ps1') ("param([string]`$Version)`n" + (& $ps 'pack' "[IO.File]::WriteAllBytes('$(Join-Path $Root 'third_party\dll-win64\drag-lint.exe')', [byte[]](9, 9, 9))"))
  New-Item -ItemType Directory -Path (Join-Path $Root 'tools\lib') -Force | Out-Null
  Copy-Item -LiteralPath $orch -Destination (Join-Path $Root 'tools\publish-release.ps1')
  Copy-Item -LiteralPath $lib -Destination (Join-Path $Root 'tools\lib\ReleaseGuard.ps1')
}
function Invoke-Stub([string]$Root, [string[]]$Extra) {
  $o = & pwsh -NoProfile -File (Join-Path $Root 'tools\publish-release.ps1') -Version '9.9.9-alpha' -Repo $Root @Extra 2>&1 | Out-String
  $steps = if (Test-Path -LiteralPath (Join-Path $Root 'steps.log')) { @(Get-Content -LiteralPath (Join-Path $Root 'steps.log') | ForEach-Object { $_.Trim() }) -join ',' } else { '' }
  return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $o; Steps = $steps; EngineSha = (Sha (Join-Path $Root 'third_party\dll-win64\drag-lint.exe')) }
}
$stubSha = $null
$s1 = Join-Path $WorkDir 'stub-ok'; New-StubTree $s1; $stubSha = Sha (Join-Path $s1 'third_party\dll-win64\drag-lint.exe')
$x = Invoke-Stub $s1 @()
Check 'stub run: every step runs, in order build,gate,manual,battery,wiki,pack' (($x.Exit -eq 0) -and ($x.Steps -eq 'build,gate,manual,battery,wiki,pack')) "exit=$($x.Exit) steps=$($x.Steps)"
Check 'stub run: the manual is built exactly once' (@($x.Steps -split ',' | Where-Object { $_ -eq 'manual' }).Count -eq 1)
Check 'stub run: the engine the pack overwrote is restored byte-identically' (($x.EngineSha -eq $stubSha) -and ($x.Out -match 'engine restored'))
$s2 = Join-Path $WorkDir 'stub-gate'; New-StubTree $s2; Write-Ascii (Join-Path $s2 'fail-gate') "x`n"
$x = Invoke-Stub $s2 @()
Check 'POSITIVE CONTROL: a stale-pages gate stops the run at step 2, nothing after it runs' (($x.Exit -eq 1) -and ($x.Steps -eq 'build,gate') -and ($x.Out -match 'STOP at step 2')) "exit=$($x.Exit) steps=$($x.Steps)"
$x = Invoke-Stub $s2 @('-DryRun')
Check 'POSITIVE CONTROL: a stale-pages gate fails the dry run too' (($x.Exit -eq 1) -and ($x.Out -match 'STOP at step 2') -and ($x.Out -notmatch 'step 3/7')) "exit=$($x.Exit)"
$s3 = Join-Path $WorkDir 'stub-pack'; New-StubTree $s3; Write-Ascii (Join-Path $s3 'fail-pack') "x`n"
$x = Invoke-Stub $s3 @('-SkipBuild', '-SkipBattery')
Check 'a failing pack stops at step 6 and the engine is STILL restored' (($x.Exit -eq 1) -and ($x.Out -match 'STOP at step 6') -and ($x.EngineSha -eq $stubSha)) "exit=$($x.Exit) steps=$($x.Steps)"
Check '-SkipBuild and -SkipBattery skip exactly those steps' ($x.Steps -eq 'gate,manual,wiki,pack') $x.Steps
$s4 = Join-Path $WorkDir 'stub-dry'; New-StubTree $s4
$x = Invoke-Stub $s4 @('-DryRun')
Check 'a dry run executes the gate and nothing else' (($x.Exit -eq 0) -and ($x.Steps -eq 'gate') -and ($x.EngineSha -eq $stubSha)) "exit=$($x.Exit) steps=$($x.Steps)"

# --- the migrated gates, executed (the real scripts, copied beside a stub gate) -----
$g = Join-Path $WorkDir 'gates'
Write-Ascii (Join-Path $g 'tools\build-feature-pages.ps1') "if (Test-Path -LiteralPath '$(Join-Path $g 'fail-gate')') { Write-Host 'feature pages: 1 output(s) would change'; exit 1 }`nWrite-Host 'feature pages: current'; exit 0`n"
Copy-Item -LiteralPath (Join-Path $Repo 'tools\publish-wiki.ps1') -Destination (Join-Path $g 'tools\publish-wiki.ps1')
New-Item -ItemType Directory -Path (Join-Path $g 'build') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $Repo 'build\pack-lint-release.ps1') -Destination (Join-Path $g 'build\pack-lint-release.ps1')
Write-Ascii (Join-Path $g 'docs\wiki\Home.md') "# stub`n"
$wikiWork = Join-Path $WorkDir 'wiki-work'
$noRemote = Join-Path $WorkDir 'no-such-wiki-repo.git'   # LOCAL and absent: a clone can only fail, never reach a network
$packVer = "zz-guard-$PID"
$packRel = "C:\TEMP\rel-zz-guard-$PID"   # pack-lint-release.ps1 stages into C:\TEMP\rel-<Version>; $PID kept on this line so run_scratch_dirs_are_per_run.ps1 sees it is per run
Write-Ascii (Join-Path $g 'fail-gate') "x`n"
$o = & pwsh -NoProfile -File (Join-Path $g 'tools\publish-wiki.ps1') -Repo $noRemote -Work $wikiWork 2>&1 | Out-String
Check 'publish-wiki.ps1: a stale gate refuses, before any clone' (($LASTEXITCODE -eq 1) -and ($o -match 'generated pages are not current') -and ($o -notmatch 'cloning') -and -not (Test-Path -LiteralPath $wikiWork)) "exit=$LASTEXITCODE"
$o = & pwsh -NoProfile -File (Join-Path $g 'build\pack-lint-release.ps1') -Version $packVer -SkipBuild 2>&1 | Out-String
Check 'pack-lint-release.ps1: a stale gate refuses, before anything is staged' (($LASTEXITCODE -eq 1) -and ($o -match 'PACK REFUSED') -and -not (Test-Path -LiteralPath $packRel)) "exit=$LASTEXITCODE"
Remove-Item -LiteralPath (Join-Path $g 'fail-gate') -Force
$o = & pwsh -NoProfile -File (Join-Path $g 'tools\publish-wiki.ps1') -Repo $noRemote -Work $wikiWork 2>&1 | Out-String
Check 'POSITIVE CONTROL: publish-wiki.ps1 passes a current gate through to the clone' (($o -match 'cloning the wiki repo') -and ($o -notmatch 'generated pages are not current')) "exit=$LASTEXITCODE"
$o = & pwsh -NoProfile -File (Join-Path $g 'build\pack-lint-release.ps1') -Version $packVer -SkipBuild 2>&1 | Out-String
Check 'POSITIVE CONTROL: pack-lint-release.ps1 passes a current gate through to staging' (($o -match '-SkipBuild: staging') -and ($o -notmatch 'PACK REFUSED')) "exit=$LASTEXITCODE"

# --- the two migrated scripts carry the gate ---------------------------------------
$pw = Get-Content -LiteralPath (Join-Path $Repo 'tools\publish-wiki.ps1') -Raw
Check 'publish-wiki.ps1 runs build-feature-pages.ps1 -Check before cloning' (($pw -match 'build-feature-pages\.ps1') -and ($pw.IndexOf('build-feature-pages.ps1') -lt $pw.IndexOf('git clone')))
$pk = Get-Content -LiteralPath (Join-Path $Repo 'build\pack-lint-release.ps1') -Raw
Check 'pack-lint-release.ps1 runs build-feature-pages.ps1 -Check before msbuild' (($pk -match 'build-feature-pages\.ps1') -and ($pk.IndexOf('build-feature-pages.ps1') -lt $pk.IndexOf('msbuild')))
$or = Get-Content -LiteralPath $orch -Raw
Check 'the pack step is wrapped in Invoke-WithEngineBackup' ($or -match 'Invoke-WithEngineBackup[^\r\n]*pack-lint-release' -or $or -match '(?s)Invoke-WithEngineBackup.*pack-lint-release\.ps1')
Check 'the plugin build is opt-in (it deploys into the live IDE)' ($or -match '\[switch\]\$BuildPlugin')

Write-Host ''
if ($script:Failed) { Write-Host 'PUBLISH RELEASE GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PUBLISH RELEASE GUARD: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @($WorkDir, "C:\TEMP\rel-zz-guard-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
