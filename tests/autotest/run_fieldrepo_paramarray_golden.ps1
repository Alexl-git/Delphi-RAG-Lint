<#
  run_fieldrepo_paramarray_golden.ps1 -- the Loader2019 golden REPORT for `repo gen-param-array`
  (spec docs\superpowers\specs\2026-11-18-gen-param-array-design.md section 5; 1.52 = a report, not a
  battery gate: Q3 sets a threshold only after the first measurement).

  Loader2019 is the project that used the IDE assistant; ~78 live units still carry its output, hand-finished
  afterwards, so TEXT equality is the wrong measure. This compares ASSIGNMENT TRIPLES
  (param constant, param accessor, source field) of the generated block with the unit's existing loop:
    same          the two triple sets are equal
    hand-edited   the same parameters are assigned, but a triple differs (accessor / right-hand side rewritten)
    diverged      a parameter is assigned in one set and not the other (cause tagged in the table)
    not-generated status <> planned (no table / query, binary or missing DFM, excluded, ...)
  Runs on a COPY of Loader2019 (sources + project files only) under -WorkDir; never touches the real tree;
  uses --plan, so no compiler. Writes golden-report.txt beside the copy. Exit 0 = the report was produced.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Corpus  = 'C:\Projects\Loader2019',
  [string]$WorkDir = "$env:TEMP\drag-lint-genpa-golden-$PID",
  [string]$ProgressForm = 'frmLoader2019_Main'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 1 }
if (-not (Test-Path "$Corpus\Loader2019.dproj")) { Write-Host "FATAL: corpus not found: $Corpus" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$copy = Join-Path $WorkDir 'corpus'
[IO.Directory]::CreateDirectory($copy) | Out-Null
foreach ($pat in '*.pas', '*.dfm', '*.dproj', '*.dpr') { Copy-Item (Join-Path $Corpus $pat) $copy -Force }

$out = & $Exe repo gen-param-array --project "$copy\Loader2019.dproj" --all --plan --json --progress-form $ProgressForm 2>"$WorkDir\err.txt"
$j = ($out | Where-Object { $_ -like '{*' } | Select-Object -Last 1) | ConvertFrom-Json
if ($null -eq $j) { Write-Host 'FATAL: no JSON from the verb' -ForegroundColor Red; exit 1 }

$tripleRx = [regex]'\.Params\[\s*(par\w+)\s*\]\.(As\w+)\[I\]\s*:=\s*(.*)$'
$fieldRx  = [regex]'\b(tbl\w+)\s*\.\s*As\w+'
function Get-Triples([string[]]$Lines) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($l in $Lines) {
    $t = $l.Trim()
    if ($t.StartsWith('//') -or $t.StartsWith('{')) { continue }
    $m = $tripleRx.Match($t)
    if (-not $m.Success) { continue }
    $f = $fieldRx.Match($m.Groups[3].Value)
    [void]$set.Add(('{0}|{1}|{2}' -f $m.Groups[1].Value.ToLower(), $m.Groups[2].Value, $(if ($f.Success) { $f.Groups[1].Value.ToLower() } else { '' })))
  }
  return , $set
}
function Params-Of($set) { return @($set | ForEach-Object { $_.Split('|')[0] } | Sort-Object -Unique) }
function Consts-Of([string[]]$Lines) {
  return @($Lines | ForEach-Object { if ($_ -match '^\s*(par\w+)\s*=\s*\d+;') { $Matches[1].ToLower() } } | Sort-Object -Unique)
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($u in $j.units) {
  $row = [ordered]@{ unit = $u.unit; class = ''; note = '' }
  if ($u.status -ne 'planned') {
    $row.class = 'not-generated'; $row.note = $u.status
    $rows.Add([pscustomobject]$row); continue
  }
  $gen = Get-Triples (($u.block -split "`r?`n"))
  $src = [IO.File]::ReadAllLines("$copy\$($u.unit).pas")
  $ex = Get-Triples $src
  $gp = Params-Of $gen; $ep = Params-Of $ex
  $constDiff = Compare-Object @(Consts-Of ($u.block -split "`r?`n")) @(Consts-Of $src)
  if ($gen.SetEquals($ex)) { $row.class = 'same' }
  elseif ((@($gp) -join ',') -eq (@($ep) -join ',')) { $row.class = 'hand-edited'; $row.note = 'same params, triple differs' }
  else {
    $row.class = 'diverged'
    $dfm = [IO.File]::ReadAllText("$copy\$($u.unit).dfm")
    $queries = ([regex]::Matches($dfm, ':\s*TFDQuery')).Count
    $cause = if ($ex.Count -eq 0) { 'no existing loop in the unit' }
             elseif ($queries -gt 1) { "multi-query DFM ($queries TFDQuery; LAST-query heuristic)" }
             else { 'DFM or loop edited after generation' }
    $genOnly = @($gp | Where-Object { $ep -notcontains $_ }) -join ','
    $exOnly = @($ep | Where-Object { $gp -notcontains $_ }) -join ','
    $row.note = "$cause; generated-only [$genOnly] unit-only [$exOnly]"
  }
  if ($constDiff) { $row.note += $(if ($row.note) { '; ' } else { '' }) + 'par* constants differ' }
  $rows.Add([pscustomobject]$row)
}

$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine("gen-param-array golden report -- Loader2019 ($((Get-Date).ToString('yyyy-MM-dd HH:mm')))")
$null = $sb.AppendLine("corpus copy: $copy   progress-form: $ProgressForm")
foreach ($c in 'same', 'hand-edited', 'diverged', 'not-generated') {
  $null = $sb.AppendLine(('{0,-14} {1}' -f $c, @($rows | Where-Object { $_.class -eq $c }).Count))
}
$gen = @($rows | Where-Object { $_.class -ne 'not-generated' }).Count
$ok = @($rows | Where-Object { $_.class -in 'same', 'hand-edited' }).Count
$null = $sb.AppendLine("generated units: $gen   same + hand-edited: $ok" + $(if ($gen) { (' ({0:N1} %)' -f (100.0 * $ok / $gen)) } else { '' }))
$null = $sb.AppendLine('')
foreach ($r in $rows | Where-Object { $_.class -ne 'not-generated' } | Sort-Object class, unit) {
  $null = $sb.AppendLine(('{0,-13} {1,-28} {2}' -f $r.class, $r.unit, $r.note))
}
$null = $sb.AppendLine('')
$null = $sb.AppendLine('not generated:')
foreach ($g in $rows | Where-Object { $_.class -eq 'not-generated' } | Group-Object note) {
  $null = $sb.AppendLine(('  {0,-16} {1}' -f $g.Name, (($g.Group | ForEach-Object { $_.unit }) -join ', ')))
}
$report = Join-Path $WorkDir 'golden-report.txt'
[IO.File]::WriteAllText($report, $sb.ToString())
Write-Host $sb.ToString().Substring(0, [Math]::Min(1500, $sb.Length))
Write-Host "report: $report"
exit 0
