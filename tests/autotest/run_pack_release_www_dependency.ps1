<#
  run_pack_release_www_dependency.ps1 -- pins build\pack-lint-release.ps1's dependency on
  WWW\help\dl\index.json (1.52.2). WWW left this repo on 2026-11-20 (its own local repo,
  ignored here), so a fresh clone has no such file; the pack must refuse up front and name
  the path, not die mid-staging on a bare Copy-Item after two Release builds.

  It copies the script into an empty fake repo and runs it with -SkipBuild:
    A  no index.json  -> exit 1, "PACK REFUSED", the full path, and featuregen never ran
    B  control: with index.json the check passes and the run goes on to the next step
       (the featuregen gate, absent in the fake repo, so it fails THERE, differently)
#>
param([string]$Scratch = '', [switch]$KeepWorkDir)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\WorkDirCleanup.ps1"
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Scratch -eq '') { $Scratch = Join-Path ([IO.Path]::GetTempPath()) "pack_www_guard_$PID" }
$fake = Join-Path $Scratch 'repo'
[void][IO.Directory]::CreateDirectory((Join-Path $fake 'build'))
[IO.File]::Copy((Join-Path $repo 'build\pack-lint-release.ps1'), (Join-Path $fake 'build\pack-lint-release.ps1'), $true)

$fails = 0; $passes = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:passes++; "PASS $Name" }
  else { $script:fails++; "FAIL $Name $Detail" }
}

function Invoke-Pack {
  $shell = (Get-Process -Id $PID).Path
  $out = & { $ErrorActionPreference = 'Continue'; & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fake 'build\pack-lint-release.ps1') -Version 0.0.0-test -SkipBuild -NoProfileInstall 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join "`n") }
}

$idx = Join-Path $fake 'WWW\help\dl\index.json'
$r = Invoke-Pack
Check 'A1 missing index.json: exit 1' ($r.Exit -eq 1) "exit=$($r.Exit)"
Check 'A2 refuses and names the full path' ($r.Text -match 'PACK REFUSED' -and $r.Text.Contains($idx)) $r.Text
Check 'A3 refuses before the featuregen gate' ($r.Text -notmatch 'featuregen-gate') $r.Text

[void][IO.Directory]::CreateDirectory((Split-Path $idx -Parent))
[IO.File]::WriteAllText($idx, '[]')
$r = Invoke-Pack
Check 'B1 control: with index.json the WWW check passes' (-not $r.Text.Contains($idx)) $r.Text
Check 'B2 control: the run reaches the next step (featuregen gate)' ($r.Text -match 'featuregen') $r.Text

Remove-WorkDir $Scratch -Keep:$KeepWorkDir
"run_pack_release_www_dependency: $passes passed, $fails failed"
if ($fails -gt 0) { exit 1 }
exit 0
