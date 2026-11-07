<#
  run_dead_code_types.ps1 -- index facts for three dead-code rules (1.45 lane lg, survey rows 9, 11, 13).
    message-chain                         a hop that returns the type of its receiver is not counted
    default-encoding-io                   receiver type: TStrings descendant = text, other class = binary
    exception-constructed-but-not-raised  Exception ancestry beats the E+Upper name test

  Markers in uDcTypes.pas (see its header). Runs per rule: lint-all on the fixture DB (facts),
  `lint <file> --db` (facts), lint-all on a copy with ref_types dropped and type_ancestors
  emptied (an index older than 1.44), and `lint <file>` with no --db. The last two must equal
  today: ALWAYS + SILENCED. The facts runs must equal ALWAYS + ORACLE-ONLY. Every tag has an
  ALWAYS line, so a guard that only asserted "the false finding is gone" cannot pass with the
  rule off.

  Usage: pwsh -File tests\lint-project\dead-code-types\run_dead_code_types.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_dctypes_$PID"
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
  return @($Findings | Where-Object { $_.rule -eq $Rule -and $_.file_path -like '*uDcTypes*' } |
    ForEach-Object { [int]$_.start_line } | Sort-Object)
}
function Marked([string]$File, [string[]]$Kinds, [string]$Tag) {
  $rx = '// (' + ($Kinds -join '|') + ')-' + $Tag + '\b'
  return @(Select-String -Path $File -Pattern $rx | ForEach-Object { $_.LineNumber } | Sort-Object)
}
$rules = @(
  @{ Rule = 'exception-constructed-but-not-raised'; Tag = 'EXC' },
  @{ Rule = 'default-encoding-io';                  Tag = 'ENC' },
  @{ Rule = 'message-chain';                        Tag = 'CHAIN' }
)
try {
  $src = Join-Path $scratch 'src'
  [void](New-Item -ItemType Directory -Force -Path $src)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $src
  $use = Join-Path $src 'uDcTypes.pas'
  $db = Join-Path $scratch 'dc.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $old = Join-Path $scratch 'old.sqlite'
  Copy-Item $db $old
  $py = Join-Path $scratch 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.execute('DELETE FROM type_ancestors')`nc.commit()`nc.close()`n")
  python -I $py $old
  $rows = @(& $exePath sql --db $db --query "SELECT count(*) FROM ref_types" 2>&1) -join ' '
  $gone = @(& $exePath sql --db $old --query "SELECT name FROM sqlite_master WHERE name = 'ref_types'" 2>&1) -join ' '
  Check 'the fixture DB has ref_types rows' ($rows -notmatch '\b0\b\s*$') $rows
  Check 'the control DB really has no ref_types' ($gone -match '\b0 row') $gone

  $withFacts = Parse-Findings (& $exePath lint-all --db $db --enable default-encoding-io --format json 2>$null)
  $noTable   = Parse-Findings (& $exePath lint-all --db $old --enable default-encoding-io --format json 2>$null)
  $noIndex   = Parse-Findings (& $exePath lint $use --enable default-encoding-io --format json 2>$null)
  $oneFile   = Parse-Findings (& $exePath lint $use --db $db --enable default-encoding-io --format json 2>$null)

  foreach ($r in $rules) {
    $rule = $r.Rule; $tag = $r.Tag
    $always = @(Marked $use @('ALWAYS') $tag)
    $only   = @(Marked $use @('ORACLE-ONLY') $tag)
    $silenced = @(Marked $use @('SILENCED') $tag)
    $control  = @(Marked $use @('CONTROL') $tag)
    $wantOn  = @($always + $only | Sort-Object)
    $wantOff = @($always + $silenced | Sort-Object)
    Check "$rule fixture has an ALWAYS line and a CONTROL line" (($always.Count -gt 0) -and ($control.Count -gt 0)) ''
    Check "$rule lint-all with facts: ALWAYS + ORACLE-ONLY" ((@(Lines $withFacts $rule) -join ',') -eq ($wantOn -join ',')) "got [$((Lines $withFacts $rule) -join ',')] want [$($wantOn -join ',')]"
    Check "$rule lint <file> --db with facts: ALWAYS + ORACLE-ONLY" ((@(Lines $oneFile $rule) -join ',') -eq ($wantOn -join ',')) "got [$((Lines $oneFile $rule) -join ',')] want [$($wantOn -join ',')]"
    Check "$rule lint-all, ref_types dropped: as before (ALWAYS + SILENCED)" ((@(Lines $noTable $rule) -join ',') -eq ($wantOff -join ',')) "got [$((Lines $noTable $rule) -join ',')] want [$($wantOff -join ',')]"
    Check "$rule lint <file>, no index: as before (ALWAYS + SILENCED)" ((@(Lines $noIndex $rule) -join ',') -eq ($wantOff -join ',')) "got [$((Lines $noIndex $rule) -join ',')] want [$($wantOff -join ',')]"
  }
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
