<#
  run_rtti_unavailable.ps1 -- the `rtti-unavailable` project rule (wave 152b lane RTTI,
  INBOX rtti-availability-rule). OFF by default, severity warning (info for a published record
  property that the class streams itself in DefineProperties).

  Fixture uRttiObjects.pas: every line tagged "// EXPECT <sub-kind> <severity>" must carry exactly
  one finding whose message starts with "<sub-kind>:" and has that severity; nothing else in the
  project may fire (uRttiClean.pas is a clean component unit, the "// CONTROL" lines are the negative
  controls). The "// LIBONLY" line fires only when the stand-in library index (lib\) is given.

  RUN 1 lint-all --rule            exactly the EXPECT lines (positive control: an engine without the
                                    rule reports nothing and fails here)
  RUN 2 plain lint-all              the rule ships OFF: nothing
  RUN 3 lint-all --enable           ON through the config path (only once the CLI wiring is in the
                                    tree: the check is SKIPPED while DRagLint.CLI.pas does not name the
                                    rule -- HANDOVER CLI of lane RTTI)
  RUN 4 lint <file> --rule          the same findings for the one unit
  RUN 5 with the library index      the LIBONLY line fires too, TViaLib stays silent

  Usage: pwsh -File tests\lint-project\rtti-unavailable\run_rtti_unavailable.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_rtti_$PID"
$Rule    = 'rtti-unavailable'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function RuleFindings([string[]]$LintArgs) {
  $raw = & $exePath lint-all @LintArgs --format json 2>$null
  return ,@((Parse-Findings $raw) | Where-Object { $_.rule -eq $Rule })
}
# "line kind severity" keys of the tagged lines; $Tag = EXPECT or LIBONLY
function Expected([string]$File, [string]$Tag) {
  $keys = @()
  $lines = [IO.File]::ReadAllLines($File)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], "//\s*$Tag\s+(\S+)\s+(\S+)")
    if ($m.Success) { $keys += ('{0} {1} {2}' -f ($i + 1), $m.Groups[1].Value, $m.Groups[2].Value) }
  }
  return ,@($keys)
}
function KeysOf($Findings) {
  return ,@($Findings | ForEach-Object {
    $kind = ([string]$_.message -split ':', 2)[0]
    '{0} {1} {2}' -f [int]$_.start_line, $kind, $_.severity } | Sort-Object)
}
try {
  $src = Join-Path $scratch 'src'
  $lib = Join-Path $scratch 'lib'
  [void](New-Item -ItemType Directory -Force -Path $src)
  [void](New-Item -ItemType Directory -Force -Path $lib)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $src
  Copy-Item (Join-Path $PSScriptRoot 'lib\*.pas') $lib
  $db    = Join-Path $scratch 'rtti.sqlite'
  $libDb = Join-Path $scratch 'library-rtti.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  Check 'project index exits 0' ($LASTEXITCODE -eq 0)
  & $exePath index $lib --db $libDb 2>&1 | Out-Null
  Check 'library index exits 0' ($LASTEXITCODE -eq 0)
  $objects = Join-Path $src 'uRttiObjects.pas'
  $want    = @((Expected $objects 'EXPECT') | Sort-Object)
  $libWant = @((Expected $objects 'LIBONLY'))
  Check 'CONTROL the fixture names expectations' (($want.Count -ge 10) -and ($libWant.Count -eq 1)) "$($want.Count) EXPECT, $($libWant.Count) LIBONLY"

  # positive-control: rtti-unavailable
  $hits = RuleFindings @('--db', $db, '--library-db', 'none', '--rule', $Rule)
  $hits | ForEach-Object { Write-Host ("    {0}:{1} [{2}] {3}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.severity, $_.message) -ForegroundColor DarkGray }
  $inObjects = @($hits | Where-Object { $_.file_path -like '*uRttiObjects.pas' })
  $got = KeysOf $inObjects
  Check 'RUN 1 exactly the EXPECT lines fire, with sub-kind and severity' (($got -join ' | ') -eq ($want -join ' | ')) "got [$($got -join ' | ')] want [$($want -join ' | ')]"
  Check 'RUN 1 the clean unit stays silent' ($hits.Count -eq $inObjects.Count) "$($hits.Count - $inObjects.Count) outside uRttiObjects.pas"
  Check 'RUN 1 the enum message names the E2134 consequence' (@($inObjects | Where-Object { $_.message -match 'TGap' -and $_.message -match 'E2134' }).Count -ge 1)
  Check 'RUN 1 the DefineProperties case says so' (@($inObjects | Where-Object { $_.message -match 'Stamp' -and $_.message -match 'DefineProperties' -and $_.severity -eq 'info' }).Count -eq 1)

  $off = RuleFindings @('--db', $db, '--library-db', 'none')
  Check 'RUN 2 plain lint-all: the rule ships OFF' ($off.Count -eq 0) "$($off.Count) finding(s)"

  $cliPas = Join-Path $repo 'src\cli\DRagLint.CLI.pas'
  $wired = (Test-Path $cliPas) -and ([IO.File]::ReadAllText($cliPas).Contains("'$Rule'"))
  if ($wired) {
    $on = RuleFindings @('--db', $db, '--library-db', 'none', '--enable', $Rule)
    Check 'RUN 3 --enable turns it on (same findings as --rule)' ($on.Count -eq $hits.Count) "$($on.Count) vs $($hits.Count)"
  } else {
    Write-Host '[SKIP] RUN 3 --enable: DRagLint.CLI.pas does not name the rule yet (HANDOVER CLI, lane RTTI)' -ForegroundColor Yellow
  }

  $one = & $exePath lint $objects --db $db --library-db none --rule $Rule --json 2>$null
  $oneF = @((Parse-Findings $one) | Where-Object { $_.rule -eq $Rule })
  $oneGot = KeysOf $oneF
  Check 'RUN 4 lint <file> --rule: the same findings' (($oneGot -join ' | ') -eq ($want -join ' | ')) "got [$($oneGot -join ' | ')]"

  $withLib = RuleFindings @('--db', $db, '--db', $libDb, '--rule', $Rule)
  $libGot = KeysOf @($withLib | Where-Object { $_.file_path -like '*uRttiObjects.pas' })
  $libExpect = @(($want + $libWant) | Sort-Object)
  Check 'RUN 5 with the library: the LIBONLY record property fires too, TViaLib stays silent' (($libGot -join ' | ') -eq ($libExpect -join ' | ')) "got [$($libGot -join ' | ')]"
} finally {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
