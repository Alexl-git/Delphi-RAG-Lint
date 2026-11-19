<#
  run_v151_RTTI2_generic.ps1 -- rtti-unavailable on GENERIC types (wave v151 lane RTTI2, owner OQ11).

  Every construct of the fixture compiles with dcc64 (Delphi 13); the compiler itself rejects only a
  published FIELD of a type-parameter type (E2217), which is therefore not a rule. What compiles but
  loses RTTI or classic streaming:
    published-generic-method        a generic method in a published section: no method-table entry
                                    (MethodAddress returns nil) and no extended RTTI
    published-unstreamable-generic  a published property whose type is a generic instantiation TWriter
                                    skips (TArray<..>, a reference type such as TProc<..>, a class that is
                                    not a TPersistent), or a type parameter constrained to record;
                                    info when the class's DefineProperties names it
  A generic record instantiation stays published-record-property.

  Fixture fixtures\v151-RTTI2\generic\uRttiGeneric.pas: "// EXPECT <sub-kind> <severity>" lines must
  carry exactly one finding each, "// CONTROL" lines nothing; "// LIBONLY" lines fire only when the
  stand-in library index (lib\) is given.

  RUN 1 lint-all --rule, no library  exactly the EXPECT lines (positive control: an engine without the
                                     generic checks reports none of them and fails here)
  RUN 2 plain lint-all               the rule ships OFF: nothing
  RUN 3 lint <file> --rule           the same findings for the one unit
  RUN 4 with the library index       EXPECT + LIBONLY

  Usage: pwsh -File tests\autotest\run_v151_RTTI2_generic.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$fixture = Join-Path $PSScriptRoot 'fixtures\v151-RTTI2\generic'
$scratch = Join-Path C:\TEMP "draglint_rtti2_$PID"
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
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint-all @LintArgs --format json 2>$null }
  return ,@((Parse-Findings $raw) | Where-Object { $_.rule -eq $Rule })
}
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
  Copy-Item (Join-Path $fixture '*.pas') $src
  Copy-Item (Join-Path $fixture 'lib\*.pas') $lib
  $db    = Join-Path $scratch 'rtti2.sqlite'
  $libDb = Join-Path $scratch 'library-rtti2.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  Check 'project index exits 0' ($LASTEXITCODE -eq 0)
  & { $ErrorActionPreference = 'Continue'; & $exePath index $lib --db $libDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
  Check 'library index exits 0' ($LASTEXITCODE -eq 0)
  $unit    = Join-Path $src 'uRttiGeneric.pas'
  $want    = @((Expected $unit 'EXPECT') | Sort-Object)
  $libWant = @((Expected $unit 'LIBONLY'))
  Check 'CONTROL the fixture names expectations' (($want.Count -ge 9) -and ($libWant.Count -eq 2)) "$($want.Count) EXPECT, $($libWant.Count) LIBONLY"

  $hits = RuleFindings @('--db', $db, '--library-db', 'none', '--rule', $Rule)
  $hits | ForEach-Object { Write-Host ("    {0}:{1} [{2}] {3}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.severity, $_.message) -ForegroundColor DarkGray }
  $got = KeysOf $hits
  Check 'RUN 1 exactly the EXPECT lines fire, with sub-kind and severity' (($got -join ' | ') -eq ($want -join ' | ')) "got [$($got -join ' | ')] want [$($want -join ' | ')]"
  Check 'RUN 1 the generic-method message names the lost method-table entry' (@($hits | Where-Object { $_.message -match 'Apply' -and $_.message -match 'MethodAddress' }).Count -eq 1)
  Check 'RUN 1 the DefineProperties case is info and says so' (@($hits | Where-Object { $_.message -match 'Owned' -and $_.message -match 'DefineProperties' -and $_.severity -eq 'info' }).Count -eq 1)

  $off = RuleFindings @('--db', $db, '--library-db', 'none')
  Check 'RUN 2 plain lint-all: the rule ships OFF' ($off.Count -eq 0) "$($off.Count) finding(s)"

  $one = & { $ErrorActionPreference = 'Continue'; & $exePath lint $unit --db $db --library-db none --rule $Rule --json 2>$null }
  $oneGot = KeysOf @((Parse-Findings $one) | Where-Object { $_.rule -eq $Rule })
  Check 'RUN 3 lint <file> --rule: the same findings' (($oneGot -join ' | ') -eq ($want -join ' | ')) "got [$($oneGot -join ' | ')]"

  $withLib = RuleFindings @('--db', $db, '--db', $libDb, '--rule', $Rule)
  $libGot = KeysOf @($withLib | Where-Object { $_.file_path -like '*uRttiGeneric.pas' })
  $libExpect = @(($want + $libWant) | Sort-Object)
  Check 'RUN 4 with the library: the LIBONLY lines fire too' (($libGot -join ' | ') -eq ($libExpect -join ' | ')) "got [$($libGot -join ' | ')]"
} finally {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
