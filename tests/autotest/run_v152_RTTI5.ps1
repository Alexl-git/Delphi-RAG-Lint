<#
  run_v152_RTTI5.ps1 -- rtti-unavailable sub-kind anonymous-field-type (v152 lane RTTI5, INBOX
  rtti-availability-rule sub-check 5). Fixture tests\lint\rtti-unavailable.pas: every line tagged
  "// EXPECT anonymous-field-type" must carry exactly one rtti-unavailable finding (message starts
  "anonymous-field-type:", severity warning); every other line is a CONTROL (named twin, private /
  public section, record, comment, indexed property) and must stay silent.

  RUN 1 lint <file> --config enabling the rule   exactly the EXPECT lines (positive control: an engine
                                                  without the sub-kind reports nothing and fails here)
  RUN 2 lint <file> with no config                the rule ships OFF: nothing
  RUN 3 lint <file> --rule rtti-unavailable       same lines as RUN 1 (--rule counts as opting in)
  RUN 4 lint-all over a one-unit project index    same lines through the project path, --rule and --enable

  Usage: pwsh -File tests\autotest\run_v152_RTTI5.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$scratch = Join-Path C:\TEMP "draglint_rtti5_$PID"
$Rule    = 'rtti-unavailable'
$Kind    = 'anonymous-field-type'
$fixture = Join-Path $repo 'tests\lint\rtti-unavailable.pas'
$cfgFile = Join-Path $repo 'tests\lint\rtti-unavailable.config.json'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @(($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function RuleFindings([string[]]$Raw) {
  return ,@((Parse-Findings $Raw) | Where-Object { $_.rule -eq $Rule })
}
function Keys($Findings) {
  return ,@($Findings | ForEach-Object { '{0} {1} {2}' -f [int]$_.start_line, (([string]$_.message -split ':', 2)[0]), $_.severity } | Sort-Object)
}
try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  $lines = [IO.File]::ReadAllLines($fixture)
  $want = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '//\s*EXPECT') {
      $n = $i + 1
      while ($lines[$n - 1] -notmatch ':') { $n-- }   # continuation line: back to the name line
      $want += ('{0} {1} warning' -f $n, $Kind)
    }
  }
  $want = @($want | Sort-Object)
  Check 'CONTROL the fixture names expectations' ($want.Count -eq 6) "$($want.Count) EXPECT"

  $r1 = RuleFindings (& { $ErrorActionPreference = 'Continue'; & $exePath lint $fixture --config $cfgFile --json 2>$null })
  $r1 | ForEach-Object { Write-Host ("    {0} [{1}] {2}" -f $_.start_line, $_.severity, $_.message) -ForegroundColor DarkGray }
  $got = Keys $r1
  Check 'RUN 1 exactly the EXPECT lines fire, with sub-kind and severity' (($got -join ' | ') -eq ($want -join ' | ')) "got [$($got -join ' | ')] want [$($want -join ' | ')]"
  Check 'RUN 1 the message names the field and the named-type fix' (@($r1 | Where-Object { $_.message -match 'FBad' -and $_.message -match 'named type' }).Count -eq 1)

  $r2 = RuleFindings (& { $ErrorActionPreference = 'Continue'; & $exePath lint $fixture --json 2>$null })
  Check 'RUN 2 no config: the rule ships OFF' ($r2.Count -eq 0) "$($r2.Count) finding(s)"

  $r3 = RuleFindings (& { $ErrorActionPreference = 'Continue'; & $exePath lint $fixture --rule $Rule --json 2>$null })
  Check 'RUN 3 --rule: the same lines' ((($(Keys $r3)) -join ' | ') -eq ($want -join ' | ')) "got $($r3.Count)"

  $src = Join-Path $scratch 'src'; [void](New-Item -ItemType Directory -Force -Path $src)
  $text = [IO.File]::ReadAllText($fixture).Replace('unit rtti-unavailable;', 'unit uRttiAnon;')
  [IO.File]::WriteAllText((Join-Path $src 'uRttiAnon.pas'), $text, [Text.Encoding]::ASCII)
  $db = Join-Path $scratch 'rtti5.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  Check 'RUN 4 index exits 0' ($LASTEXITCODE -eq 0)
  $r4 = RuleFindings (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --library-db none --rule $Rule --format json 2>$null })
  Check 'RUN 4 lint-all --rule: the same lines' ((($(Keys $r4)) -join ' | ') -eq ($want -join ' | ')) "got $($r4.Count)"
  $r5 = RuleFindings (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --library-db none --enable $Rule --format json 2>$null })
  Check 'RUN 4 lint-all --enable: the same lines' ((($(Keys $r5)) -join ' | ') -eq ($want -join ' | ')) "got $($r5.Count)"
  $r6 = RuleFindings (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --library-db none --format json 2>$null })
  Check 'RUN 4 plain lint-all: OFF' ($r6.Count -eq 0) "$($r6.Count) finding(s)"
} finally {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0