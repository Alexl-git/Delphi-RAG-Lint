<#
  run_row10_receiver.ps1 -- receiver type for field-by-name-in-loop and double-dictionary-lookup (1.45 lane lj, row 10).

  The .scm rules cannot see a type. With a 1.44+ index the verbs that own a store hand the
  rules an ITypeOracle (ref_types by position, type_ancestors for a class). Rows covered:
    4   declared-type?: stream-read-result-ignored, constructor-call-on-instance (a field)
    14  ifthen-both-branches (a variable argument is inert)
    15  sleep-in-vcl (a method of a proven TThread descendant)
    17  exception-text-in-response (a receiver typed as a response)

  Markers in uR10Use.pas, on the line the finding starts on:
    ALWAYS-<T>       fires with and without the oracle
    ORACLE-ONLY-<T>  fires only WITH the oracle (a fact adds a true finding)
    SILENCED-<T>     fires without the oracle, silent WITH it (a fact removes a false finding)
    CONTROL-<T>      never fires

  Three runs per rule: lint-all on the fixture DB (oracle), lint-all on a copy with ref_types
  dropped (an index older than 1.44), and `lint <file>` with no --db (no index at all). The last
  two must be byte-identical to today: ALWAYS + SILENCED. A guard that only asserted the false
  finding is gone would pass with the rule off, so every rule also needs its ALWAYS lines.

  Usage: pwsh -File tests\lint-project\row10-receiver\run_row10_receiver.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_row10_$PID"
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
function Lines($Findings, [string]$Rule) {
  return @($Findings | Where-Object { $_.rule -eq $Rule -and $_.file_path -like '*uR10Use*' } |
    ForEach-Object { [int]$_.start_line } | Sort-Object)
}
function Marked([string]$File, [string[]]$Kinds, [string]$Tag) {
  $rx = '// (' + ($Kinds -join '|') + ')-' + $Tag + '\b'
  return @(Select-String -Path $File -Pattern $rx | ForEach-Object { $_.LineNumber } | Sort-Object)
}
$rules = @(
  @{ Rule = 'field-by-name-in-loop'; Tag = 'FBN' },
  @{ Rule = 'double-dictionary-lookup'; Tag = 'DDL' }
)
try {
  $src = Join-Path $scratch 'src'
  [void](New-Item -ItemType Directory -Force -Path $src)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $src
  $use = Join-Path $src 'uR10Use.pas'
  $db = Join-Path $scratch 'r10.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $old = Join-Path $scratch 'old.sqlite'
  Copy-Item $db $old
  $py = Join-Path $scratch 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.commit()`nc.close()`n")
  python -I $py $old
  $rows = @(& $exePath sql --db $db --query "SELECT count(*) FROM ref_types" 2>&1) -join ' '
  $gone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the fixture DB has ref_types rows' ($rows -notmatch '\b0\b\s*$') $rows
  Check 'the control DB really has no ref_types' ($gone -match '\b0 row') $gone

  $withFacts = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
  $oldAnc = Join-Path $scratch 'oldanc.sqlite'
  Copy-Item $old $oldAnc
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DELETE FROM type_ancestors')`nc.commit()`nc.close()`n")
  python -I $py $oldAnc
  $noAnc     = Parse-Findings (& $exePath lint-all --db $oldAnc --format json 2>$null)
  $noTable   = Parse-Findings (& $exePath lint-all --db $old --format json 2>$null)
  $noIndex   = Parse-Findings (& $exePath lint $use --format json 2>$null)
  $oneFile   = Parse-Findings (& $exePath lint $use --db $db --format json 2>$null)

  foreach ($r in $rules) {
    $rule = $r.Rule; $tag = $r.Tag
    $always = @(Marked $use @('ALWAYS') $tag)
    $only   = @(Marked $use @('ORACLE-ONLY') $tag)
    $silenced = @(Marked $use @('SILENCED') $tag)
    $control  = @(Marked $use @('CONTROL') $tag)
    $wantOn  = @($always + $only | Sort-Object)
    $wantOff = @($always + $silenced | Sort-Object)
    Check "$rule fixture has an ALWAYS line and a CONTROL line" (($always.Count -gt 0) -and ($control.Count -gt 0)) ''
    Check "$rule lint-all with ref_types: ALWAYS + ORACLE-ONLY" ((@(Lines $withFacts $rule) -join ',') -eq ($wantOn -join ',')) "got [$((Lines $withFacts $rule) -join ',')] want [$($wantOn -join ',')]"
    Check "$rule lint <file> --db with ref_types: ALWAYS + ORACLE-ONLY" ((@(Lines $oneFile $rule) -join ',') -eq ($wantOn -join ',')) "got [$((Lines $oneFile $rule) -join ',')] want [$($wantOn -join ',')]"
    $wantNoTable = if ($r.AncestryOnly) { $wantOn } else { $wantOff }   # sleep-in-vcl reads type_ancestors, not ref_types
    Check "$rule lint-all, ref_types table dropped" ((@(Lines $noTable $rule) -join ',') -eq ($wantNoTable -join ',')) "got [$((Lines $noTable $rule) -join ',')] want [$($wantNoTable -join ',')]"
    Check "$rule lint-all, ref_types dropped and type_ancestors emptied: as before (ALWAYS + SILENCED)" ((@(Lines $noAnc $rule) -join ',') -eq ($wantOff -join ',')) "got [$((Lines $noAnc $rule) -join ',')] want [$($wantOff -join ',')]"
    Check "$rule lint <file>, no index: as before (ALWAYS + SILENCED)" ((@(Lines $noIndex $rule) -join ',') -eq ($wantOff -join ',')) "got [$((Lines $noIndex $rule) -join ',')] want [$($wantOff -join ',')]"
  }
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
