# Guard for v152 lane BK-ATTRRULES (1.52.0-alpha, backlog B48): lint rules on the attributes
# index fact (BK-EXTRA, B09).
#  1. debug-display-placeholder (bug-patterns, warning, default OFF) over
#     tests\autotest\fixtures\v152-BK-ATTRRULES\UDisplay.pas: a line ending in { (+) } must carry
#     the finding, { (-) } must not. Controls: catalog row present and OFF; silent without --rule;
#     the same through lint <file> and lint-all; --disable silences it.
#  2. member-could-be-private reads the attributed members from the attributes table, not the
#     source line above the member: UPriv.pas AfterParamAttr (after a [ref] parameter line) is
#     reported where the 1.52 ATLB peek stayed silent; attributed members stay silent; Plain is the
#     positive control.
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$exe = if ([IO.Path]::IsPathRooted($Exe)) { $Exe } else { Join-Path $repo $Exe }
$exe = (Resolve-Path $exe).Path
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}
function Get-Findings([string[]]$ArgList) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exe @ArgList 2>$null }
  $text = ($raw -join "`n").Trim()
  if ($text -eq '') { return @() }
  try { $j = $text | ConvertFrom-Json } catch { return @() }
  if ($null -eq $j) { return @() }
  return @($j)
}
function Lines-Of($findings, [string]$rule, [string]$fileEnd) {
  return @($findings | Where-Object { $_.rule -eq $rule -and ([string]$_.file_path).EndsWith($fileEnd, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { [int]$_.start_line })
}
function Markers([string]$path) {
  $lines = [IO.File]::ReadAllLines($path); $m = @{ plus = @(); minus = @() }
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\{ \(\+\) \}\s*$') { $m.plus += ($i + 1) }
    elseif ($lines[$i] -match '\{ \(-\) \}\s*$') { $m.minus += ($i + 1) }
  }
  return $m
}

$src = Join-Path $PSScriptRoot 'fixtures\v152-BK-ATTRRULES'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('v152-attrrules-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Push-Location $tmp
try {
  Copy-Item (Join-Path $src '*.pas') $tmp
  $db = Join-Path $tmp 'a.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> (Join-Path $tmp 'index.log') }
  Assert "fixture folder indexed (exit $LASTEXITCODE)" (($LASTEXITCODE -eq 0) -and (Test-Path $db))

  # ---- 1. debug-display-placeholder ----
  $rule = 'debug-display-placeholder'
  $cat = (& { $ErrorActionPreference = 'Continue'; & $exe rules --json 2>$null }) -join "`n"
  $row = @(($cat | ConvertFrom-Json).rules | Where-Object { $_.id -eq $rule })
  Assert "$rule is a catalog row" ($row.Count -eq 1)
  Assert "$rule is OFF by default" (($row.Count -eq 1) -and (-not $row[0].default_enabled))
  $disp = Join-Path $tmp 'UDisplay.pas'
  $m = Markers $disp
  Assert "fixture carries (+) and (-) markers" (($m.plus.Count -ge 3) -and ($m.minus.Count -ge 3))
  # positive-control: debug-display-placeholder
  $one = Get-Findings @('lint', $disp, '--db', $db, '--rule', $rule, '--json')
  $g = Lines-Of $one $rule 'UDisplay.pas'
  foreach ($l in $m.plus)  { Assert "lint: $rule fires at line $l (got: $($g -join ','))" ($g -contains $l) }
  foreach ($l in $m.minus) { Assert "lint: $rule silent at line $l" (-not ($g -contains $l)) }
  $msg = @($one | Where-Object { $_.rule -eq $rule -and $_.message -match '\{Nmae\}' -and $_.message -match 'TTypo' })
  Assert "message names the placeholder and the type" ($msg.Count -eq 1)
  $all = Get-Findings @('lint-all', '--db', $db, '--rule', $rule, '--json')
  $ga = Lines-Of $all $rule 'UDisplay.pas'
  Assert "lint-all reports the same lines ($($ga -join ','))" ((@($ga | Sort-Object) -join ',') -eq (@($g | Sort-Object) -join ','))
  $def = Get-Findings @('lint', $disp, '--db', $db, '--json')
  Assert "default OFF: no $rule finding without --rule" (@($def | Where-Object { $_.rule -eq $rule }).Count -eq 0)
  $dis = Get-Findings @('lint', $disp, '--db', $db, '--rule', $rule, '--disable', $rule, '--json')
  Assert "control: --disable $rule silences it" (@($dis | Where-Object { $_.rule -eq $rule }).Count -eq 0)

  # ---- 2. member-could-be-private on the attributes fact ----
  $rule = 'member-could-be-private'
  $f = Get-Findings @('lint-all', '--db', $db, '--rule', $rule, '--json')
  $pm = Markers (Join-Path $tmp 'UPriv.pas'); $pg = Lines-Of $f $rule 'UPriv.pas'
  foreach ($l in $pm.plus)  { Assert "UPriv: $rule fires at line $l (got: $($pg -join ','))" ($pg -contains $l) }
  foreach ($l in $pm.minus) { Assert "UPriv: $rule silent at attributed line $l" (-not ($pg -contains $l)) }
} finally {
  Pop-Location
  [IO.Directory]::Delete($tmp, $true)
}
if ($fail -gt 0) { Write-Host "run_v152_BK-ATTRRULES: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v152_BK-ATTRRULES: all passed"
exit 0