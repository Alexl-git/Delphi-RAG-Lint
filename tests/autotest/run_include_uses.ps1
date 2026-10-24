<#
  run_include_uses.ps1 -- N-06 T4: a uses clause inside a {$I} include is
  extracted as unit_uses rows on the HOST file.

  Fixture tests\fixtures\cyclefix\incuses: IncB.pas has {$I IncB.Uses.inc} at
  line 12 (implementation); the .inc says `uses IncA;` (IncA on line 2).
    a. IncB.pas gets ONE row IncA: section implementation, origin_path = the
       absolute .inc path, start_line 2 (inside the .inc), include_line 12.
    b. IncA.pas's own `uses IncB` row stays inline: origin_path/include_line NULL
       (POSITIVE CONTROL that the query reads real rows).
    c. the IncA <-> IncB cycle now exists: `cycles` prints a group naming both,
       and lint-all circular-uses reports a finding naming both.
    d. --no-preprocess -> no include row (A8).
  Fixture tests\fixtures\includeuses: HostI.pas
    e. {$I HostI.Intf.inc} in the INTERFACE -> row Leaf, section interface,
       include_line 8, start_line 2.
    f. {$I HostI.Dead.inc} inside {$IFDEF NEVER_DEFINED} -> NO row for Dead.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-include-uses-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$inc = Join-Path $WorkDir 'incuses'; Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\incuses").Path $inc -Recurse
$iu  = Join-Path $WorkDir 'includeuses'; Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\includeuses").Path $iu -Recurse

function Index([string]$dproj, [string]$db, [string[]]$extra = @()) {
  Push-Location $WorkDir
  try { & $Exe index --project $dproj --db $db --library-db none @extra *> "$db.log" } finally { Pop-Location }
  return $LASTEXITCODE
}
function Sql([string]$db, [string]$q) {
  Push-Location $WorkDir
  try { $j = & $Exe sql --db $db --query $q --json 2>$null | Out-String } finally { Pop-Location }
  try { $o = $j | ConvertFrom-Json } catch { $o = $null }
  if ($null -eq $o -or $null -eq $o.columns) { return ,@() }
  $names = @($o.columns | ForEach-Object { $_.name })
  $rows = @()
  foreach ($r in @($o.rows)) { $h = [ordered]@{}; for ($k = 0; $k -lt $names.Count; $k++) { $h[$names[$k]] = $r[$k] }; $rows += [pscustomobject]$h }
  return ,$rows
}
$Q = "SELECT u.unit_name, u.section, u.origin_path, u.start_line, u.include_line FROM unit_uses u JOIN files f ON f.id = u.file_id WHERE f.path LIKE '%{0}'"

$db = Join-Path $WorkDir 'incuses.sqlite'
$rc = Index (Join-Path $inc 'IncUses.dproj') $db
Check 'incuses indexes (exit 0)' ($rc -eq 0) "rc=$rc"
$b = Sql $db ($Q -f 'IncB.pas')
$rowA = @($b | Where-Object { $_.unit_name -eq 'IncA' })
Check 'a: IncB.pas has exactly one IncA row' ($rowA.Count -eq 1) "rows=$($b.Count)"
$r = if ($rowA.Count -ge 1) { $rowA[0] } else { [pscustomobject]@{} }
Check 'a: section implementation' ($r.section -eq 'implementation') "got '$($r.section)'"
Check 'a: origin_path = the .inc' ($r.origin_path -eq (Join-Path $inc 'IncB.Uses.inc')) "got '$($r.origin_path)'"
Check 'a: start_line 2 (inside the .inc)' ("$($r.start_line)" -eq '2') "got '$($r.start_line)'"
Check 'a: include_line 12 (the {$I} in IncB.pas)' ("$($r.include_line)" -eq '12') "got '$($r.include_line)'"
$a = Sql $db ($Q -f 'IncA.pas')
Check 'b: positive control: IncA.pas has its own IncB row' (@($a | Where-Object { $_.unit_name -eq 'IncB' }).Count -eq 1)
Check 'b: IncA.pas rows are inline (origin NULL, include_line NULL)' (@($a | Where-Object { ($null -ne $_.origin_path) -or ($null -ne $_.include_line) }).Count -eq 0)

Push-Location $WorkDir
try {
  $cyc = & $Exe cycles --db $db 2>$null | Out-String
  $la  = & $Exe lint-all --db $db --rule circular-uses --json --library-db none 2>$null | Out-String
} finally { Pop-Location }
$grp = @($cyc -split "`r?`n" | Where-Object { ($_ -match '\bIncA\b') -and ($_ -match '\bIncB\b') })
Check 'c: cycles prints a group naming IncA and IncB' ($grp.Count -ge 1) ($cyc.Trim() -replace "`r?`n", ' | ')
$fs = @(); try { $fs = @($la | ConvertFrom-Json) } catch { }
Check 'c: lint-all circular-uses names IncA and IncB' (@($fs | Where-Object { ($_.message -match '\bIncA\b') -and ($_.message -match '\bIncB\b') }).Count -ge 1) "findings=$($fs.Count)"

$dbN = Join-Path $WorkDir 'incuses-nopp.sqlite'
$null = Index (Join-Path $inc 'IncUses.dproj') $dbN @('--no-preprocess')
$bN = Sql $dbN ($Q -f 'IncB.pas')
Check 'd: --no-preprocess -> no include row' (@($bN | Where-Object { $_.unit_name -eq 'IncA' }).Count -eq 0) "rows=$($bN.Count)"

$db2 = Join-Path $WorkDir 'includeuses.sqlite'
$rc2 = Index (Join-Path $iu 'IncUsesX.dproj') $db2
Check 'includeuses indexes (exit 0)' ($rc2 -eq 0) "rc=$rc2"
$h = Sql $db2 ($Q -f 'HostI.pas')
$leaf = @($h | Where-Object { $_.unit_name -eq 'Leaf' })
$l = if ($leaf.Count -ge 1) { $leaf[0] } else { [pscustomobject]@{} }
Check 'e: interface {$I} -> one Leaf row' ($leaf.Count -eq 1) "rows=$($h.Count)"
Check 'e: section interface' ($l.section -eq 'interface') "got '$($l.section)'"
Check 'e: include_line 8, start_line 2' (("$($l.include_line)" -eq '8') -and ("$($l.start_line)" -eq '2')) "got $($l.include_line)/$($l.start_line)"
Check 'f: inactive {$I} -> no Dead row' (@($h | Where-Object { $_.unit_name -eq 'Dead' }).Count -eq 0)

if ($script:Failed) { Write-Host 'run_include_uses: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_include_uses: PASS' -ForegroundColor Green; exit 0