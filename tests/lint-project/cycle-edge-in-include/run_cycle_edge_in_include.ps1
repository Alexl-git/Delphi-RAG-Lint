<#
  run_cycle_edge_in_include.ps1 -- the `cycle-edge-in-include` project rule (wave 152c lane INCR).
  ON by default, severity hint, project scope (lint-all / lint --project; `lint <file> --rule` answers
  for one unit too). A uses entry (shape U) or a top-level declaration (shape D) that a uses cycle runs
  through, written in a {$I} include: drag-lint never edits an include, so `cycles --fix` cannot untangle it.

  Scenario folders (each is indexed on its own into a temp DB):
    fire\     U pair (IncUA/IncUB), D pair (IncDA/IncDB), shared include (IncSA/IncSB): 4 findings
    inline\   the same three pairs written in the .pas                       -> 0 (control a)
    outside\  include-borne entry / declaration outside the cycle's group    -> 0 (controls b, c)
    marked\   the U pair with a dl:ok cycle-edge-in-include@hash on the {$I} -> 0, no marker finding (control e)
  Control d: --disable on the firing fixture -> 0.  Every zero is paired with a circular-uses finding on
  the same index (the group exists), so a rule that is simply off cannot pass.

  Usage: pwsh -File tests\lint-project\cycle-edge-in-include\run_cycle_edge_in_include.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$repo\tests\autotest\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_cycinc_$PID"
$Rule = 'cycle-edge-in-include'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function LintAll([string]$Db, [string[]]$LintArgs) {
  $raw = & $exePath lint-all --db $Db --library-db none @LintArgs --format json 2>$null
  $parsed = Parse-Findings $raw
  return ,@($parsed)
}
function Leaf($F) { Split-Path $F.file_path -Leaf }
function LineOf([string]$Dir, [string]$File, [string]$Needle) {
  $l = [IO.File]::ReadAllLines((Join-Path $Dir $File))
  for ($i = 0; $i -lt $l.Count; $i++) { if ($l[$i].Contains($Needle)) { return $i + 1 } }
  return -1
}
function IndexScenario([string]$Name) {
  $dir = Join-Path $scratch $Name
  [void](New-Item -ItemType Directory -Force -Path $dir)
  Copy-Item (Join-Path $PSScriptRoot "$Name\*") $dir
  $db = Join-Path $scratch "$Name.sqlite"
  & $exePath index $dir --db $db 2>&1 | Out-Null
  Check "index $Name exits 0" ($LASTEXITCODE -eq 0)
  return @{ Dir = $dir; Db = $db }
}
try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  $fire = IndexScenario 'fire'
  $circ = LintAll $fire.Db @('--rule', 'circular-uses')
  Check 'CONTROL fire: circular-uses sees the 3 groups' ($circ.Count -eq 3) "$($circ.Count)"
  # positive-control: cycle-edge-in-include
  $hits = @((LintAll $fire.Db @('--rule', $Rule)) | Where-Object { $_.rule -eq $Rule })
  $hits | ForEach-Object { Write-Host ("    {0}:{1}:{2} {3}" -f (Leaf $_), $_.start_line, $_.start_col, $_.message.Substring(0, [Math]::Min(110, $_.message.Length))) -ForegroundColor DarkGray }
  Check 'fire: exactly 4 findings (U + D + 2 for the shared include)' ($hits.Count -eq 4) "$($hits.Count)"
  Check 'fire: all hints' (@($hits | Where-Object { $_.severity -ne 'hint' }).Count -eq 0)

  $u = @($hits | Where-Object { (Leaf $_) -eq 'IncUA.pas' })
  Check 'U: exactly 1 finding on IncUA.pas' ($u.Count -eq 1) "$($u.Count)"
  if ($u.Count -eq 1) {
    $wantLine = LineOf $fire.Dir 'IncUA.pas' '{$I IncUUses.inc}'
    Check 'U: anchored at the {$I} line of the host' ($u[0].start_line -eq $wantLine) "$($u[0].start_line) vs $wantLine"
    Check 'U: names host, target, include and the group' (($u[0].message -match '`IncUA`') -and ($u[0].message -match '`IncUB`') -and ($u[0].message -match 'IncUUses\.inc') -and ($u[0].message -match '\(IncUA -> IncUB\)'))
    Check 'U: says drag-lint never edits an include and points at cycles --plan' (($u[0].message -match 'never edits an include') -and ($u[0].message -match 'cycles --plan'))
  }
  $d = @($hits | Where-Object { (Leaf $_) -eq 'IncDA.pas' })
  Check 'D: exactly 1 finding on IncDA.pas' ($d.Count -eq 1) "$($d.Count)"
  if ($d.Count -eq 1) {
    $wantLine = LineOf $fire.Dir 'IncDA.pas' '{$I IncDTypes.inc}'
    Check 'D: anchored at the {$I} line of the host' ($d[0].start_line -eq $wantLine) "$($d[0].start_line) vs $wantLine"
    Check 'D: names the symbol, its kind, the include line and the user' (($d[0].message -match '`TIncDARec` \(record\)') -and ($d[0].message -match 'IncDTypes\.inc` \(line 2\)') -and ($d[0].message -match '`IncDB`'))
    Check 'D: members and fields are not listed' (@($hits | Where-Object { $_.message -match '`X` \(field\)' }).Count -eq 0)
  }
  $s = @($hits | Where-Object { (Leaf $_) -in @('IncSA.pas', 'IncSB.pas') })
  Check 'S: shared include = 1 finding per host' (($s.Count -eq 2) -and (@($s | Select-Object -ExpandProperty file_path -Unique).Count -eq 2)) "$($s.Count)"
  Check 'S: the message adds "also included by" the other host' (@($s | Where-Object { $_.message -match 'also included by' }).Count -eq 2)

  $dflt = @((LintAll $fire.Db @()) | Where-Object { $_.rule -eq $Rule })
  Check 'plain lint-all: the rule ships ON' ($dflt.Count -eq 4) "$($dflt.Count)"
  $off = @((LintAll $fire.Db @('--disable', $Rule)) | Where-Object { $_.rule -eq $Rule })
  Check 'control d: --disable = 0' ($off.Count -eq 0) "$($off.Count)"
  $one = @((Parse-Findings (& $exePath lint (Join-Path $fire.Dir 'IncUA.pas') --db $fire.Db --library-db none --rule $Rule --json 2>$null)) | Where-Object { $_.rule -eq $Rule })
  Check 'lint <file> --rule: the same U finding' ($one.Count -eq 1) "$($one.Count)"

  foreach ($sc in @('inline', 'outside')) {
    $x = IndexScenario $sc
    $g = LintAll $x.Db @('--rule', 'circular-uses')
    Check "CONTROL ${sc}: a uses cycle exists (circular-uses fires)" ($g.Count -ge 1) "$($g.Count)"
    $h = @((LintAll $x.Db @('--rule', $Rule)) | Where-Object { $_.rule -eq $Rule })
    $h | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Leaf $_), $_.start_line, $_.message.Substring(0, [Math]::Min(100, $_.message.Length))) -ForegroundColor DarkGray }
    Check "control (${sc}): 0 findings" ($h.Count -eq 0) "$($h.Count)"
  }
  $mk = IndexScenario 'marked'
  $mh = @((LintAll $mk.Db @('--rule', $Rule)) | Where-Object { $_.rule -eq $Rule })
  Check 'control e: the dl:ok on the {$I} line suppresses the finding' ($mh.Count -eq 0) "$($mh.Count)"
  $mm = @((LintAll $mk.Db @('--rule', 'review-marker-unused')) + (LintAll $mk.Db @('--rule', 'review-marker-stale')))
  Check 'control e: the marker is neither unused nor stale' ($mm.Count -eq 0) "$($mm.Count)"
  $mk0 = Join-Path $scratch 'unmarked'
  [void](New-Item -ItemType Directory -Force -Path $mk0)
  Copy-Item (Join-Path $PSScriptRoot 'fire\IncUA.pas') $mk0
  Copy-Item (Join-Path $PSScriptRoot 'fire\IncUB.pas') $mk0
  Copy-Item (Join-Path $PSScriptRoot 'fire\IncUUses.inc') $mk0
  $db0 = Join-Path $scratch 'unmarked.sqlite'
  & $exePath index $mk0 --db $db0 2>&1 | Out-Null
  $m0 = @((LintAll $db0 @('--rule', $Rule)) | Where-Object { $_.rule -eq $Rule })
  Check 'control e: the same pair WITHOUT the marker fires (the marker is what silenced it)' ($m0.Count -eq 1) "$($m0.Count)"
} finally {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
