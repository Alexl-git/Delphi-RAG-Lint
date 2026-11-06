<#
  run_ref_type_rules.ps1 -- the lint rules on index fact F1, ref_types (1.44 lane rulesf1).

  Every rule is asserted line by line against markers in the fixture: a TRIGGER-<RULE>-*
  line fires, a CONTROL-<RULE>-* line stays silent, and nothing else fires. A rule that
  never fires and a rule that always fires both fail here.

  POSITIVE CONTROLS: the rule id answers on a fixture DB, and a copy of that DB with the
  ref_types table dropped answers NOTHING, which proves the findings come from the fact and
  that an index older than 1.44 stays silent. On the 1.43 engine the rules do not exist and
  every TRIGGER check fails: the RED this guard was written against.

  Usage: pwsh -File tests\lint-project\ref-type-rules\run_ref_type_rules.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_reftype_$PID"
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
function RuleLines([string]$Db, [string]$Rule, [string]$Lib = '') {
  $dbs = @('--db', $Db); if ($Lib) { $dbs += @('--db', $Lib) }
  $raw = & $exePath lint-all @dbs --format json --rule $Rule 2>$null
  return @((Parse-Findings $raw) | Where-Object { $_.rule -eq $Rule -and $_.file_path -like '*uRt*' } |
    ForEach-Object { '{0}:{1}' -f [IO.Path]::GetFileName($_.file_path), [int]$_.start_line } | Sort-Object)
}
function MarkerLines([string]$Dir, [string]$Prefix) {
  $hits = @(Select-String -Path (Join-Path $Dir '*.pas') -Pattern "// $Prefix-[A-Z0-9-]+")
  return @($hits | ForEach-Object { '{0}:{1}' -f $_.Filename, $_.LineNumber } | Sort-Object)
}
function CheckRule([string]$Db, [string]$Dir, [string]$Rule, [string]$Tag, [string]$Lib = '') {
  $got  = @(RuleLines $Db $Rule $Lib)
  $want = @(MarkerLines $Dir "TRIGGER-$Tag")
  Check "$Rule fires on exactly the TRIGGER-$Tag lines" (($got -join ',') -eq ($want -join ',')) "got [$($got -join ',')] want [$($want -join ',')]"
  Check "$Rule has a trigger and a control in the fixture" (($want.Count -gt 0) -and (@(MarkerLines $Dir "CONTROL-$Tag").Count -gt 0)) ''
}
try {
  $src = Join-Path $scratch 'src'
  [void](New-Item -ItemType Directory -Force -Path $src)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $src
  $db = Join-Path $scratch 'rt.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null

  # positive-control: is-always-true
  CheckRule $db $src 'is-always-true' 'ALWAYS'

  # positive-control: upcast-then-downcast
  CheckRule $db $src 'upcast-then-downcast' 'UPDOWN'

  # positive-control: with-on-temporary
  CheckRule $db $src 'with-on-temporary' 'WITH'

  # positive-control: interface-holder-of-non-refcounted
  CheckRule $db $src 'interface-holder-of-non-refcounted' 'HOLDER'

  # positive-control: argument-narrows
  CheckRule $db $src 'argument-narrows' 'NARROW'

  # positive-control: redundant-cast (chain, result, as; and the lexical check overruled by the fact)
  CheckRule $db $src 'redundant-cast' 'REDUNDANT'

  # positive-control: unsafe-typecast-without-is (chain and result; a proven upcast overruled by the fact)
  CheckRule $db $src 'unsafe-typecast-without-is' 'UNSAFE'
  $offRun = @((Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)) | Where-Object { $_.rule -eq 'unsafe-typecast-without-is' })
  Check 'a plain lint-all: unsafe-typecast-without-is stays OFF' ($offRun.Count -eq 0) "$($offRun.Count) finding(s)"

  $plain = @(Parse-Findings (& $exePath lint-all --db $db --format json 2>$null))
  foreach ($on in @('is-always-true', 'upcast-then-downcast', 'with-on-temporary', 'interface-holder-of-non-refcounted', 'argument-narrows', 'redundant-cast')) {
    Check "a plain lint-all: $on ships ON" (@($plain | Where-Object { $_.rule -eq $on }).Count -gt 0) ''
  }
  $file = Join-Path $src 'uRtUse.pas'
  $one = @(Parse-Findings (& $exePath lint $file --db $db --format json 2>$null))
  foreach ($on in @('is-always-true', 'upcast-then-downcast', 'with-on-temporary', 'interface-holder-of-non-refcounted', 'argument-narrows', 'redundant-cast')) {
    Check "lint <file> with an index: $on fires" (@($one | Where-Object { $_.rule -eq $on }).Count -gt 0) ''
  }

  $old = Join-Path $scratch 'old.sqlite'
  Copy-Item $db $old
  $py = Join-Path $scratch 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.commit()`nc.close()`n")
  python $py $old
  $tableGone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the control DB really has no ref_types' ($tableGone -match '\b0 row') $tableGone
  Check 'no ref_types table (an index older than 1.44): is-always-true answers nothing' (@(RuleLines $old 'is-always-true').Count -eq 0) ''
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
