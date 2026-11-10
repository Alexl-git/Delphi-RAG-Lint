<#
  run_t3_dotted_type_local_const.ps1 -- wave 150 T3 (TAILS G4, from EX3-b / RS1):
  (1) a UNIT-qualified type use `V: uT3Types.TT3Runner` binds its type_use ref to
      that unit's type (it was declined 'qualified', symbol_id NULL);
  (2) a routine-local TYPED CONST receiver `CLocal.Alpha` types from the const's
      written type (`CLocal: TT3Rec = (...)`), the member-access binds the field
      (it was NULL: LocalInScopeAt answers locals / params only).

  CASES (fixture tests\fixtures\t3-g4-150; lines are found by their text)
    D1 `V: uT3Types.TT3Runner`  -> uT3Types.TT3Runner  (NOT the own unit's shadow)
    D2 `Y: uT3Use.TT3Runner`    -> uT3Use.TT3Runner    (own-unit qualifier, impl type)
    L1 `CLocal.Alpha`           -> uT3Types.TT3Rec.Alpha
    L2 `CLocal.Beta`            -> uT3Types.TT3Rec.Beta
    L3 `COuter.Alpha` (in a nested routine, const of the outer one) -> uT3Types.TT3Rec.Alpha
  POSITIVE CONTROLS (bound on the base too; the pass is alive):
    C1 `W: TT3Runner`  -> uT3Use.TT3Runner;  C2 `R.Alpha` (local var);  C3 `CUnit.Beta` (unit typed const)
  NEGATIVE CONTROLS (stay NULL; nothing guesses):
    N1 `X: NoSuchUnit.TT3Rec` (unknown qualifier);  N2 `Z: TT3Rec.TT3Rec` (qualifier is a type)
  RED on 1.49.0-alpha (150 base): D1, D2, L1, L2, L3 symbol_id NULL.
  Usage: pwsh -File tests\callresolve\run_t3_dotted_type_local_const.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_t3_g4_$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\t3-g4-150").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
[IO.Directory]::CreateDirectory("$WorkDir\src") | Out-Null
Copy-Item "$Fx\*.pas" "$WorkDir\src"
$Db = "$WorkDir\t3.sqlite"
try {
  & $Exe index "$WorkDir\src" --db $Db 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }
  $q = "select r.kind, r.name_text, r.start_line, r.start_col, s.qualified_name from refs r " +
       "join files f on f.id = r.file_id left join symbols s on s.id = r.symbol_id " +
       "where f.path like '%uT3Use.pas' and r.kind in ('type_use','member-access')"
  $raw = (& $Exe sql --query $q --db $Db --json 2>$null) -join "`n"
  $js  = $raw | ConvertFrom-Json
  $cols = @($js.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $rows = @(foreach ($r in $js.rows) { $o = [ordered]@{}; for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }; [pscustomobject]$o })
  if ($rows.Count -lt 10) { Write-Host "FATAL: only $($rows.Count) refs read -- shape changed? raw: $raw" -ForegroundColor Red; exit 2 }
  $lines = [IO.File]::ReadAllLines("$Fx\uT3Use.pas")

  # The ref named ANAME on the line containing AMARK, at the occurrence of ATEXT.
  function At($mark, $text, $kind, $name) {
    $ln = 0
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($mark)) { $ln = $i + 1; break } }
    if ($ln -eq 0) { return 'NO-LINE' }
    $col = $lines[$ln - 1].IndexOf($text) + ($text.Length - $name.Length) + 1
    $hit = @($rows | Where-Object { $_.kind -eq $kind -and $_.name_text -eq $name -and [int]$_.start_line -eq $ln -and [int]$_.start_col -eq $col })
    if ($hit.Count -ne 1) { return "ROWS=$($hit.Count)@$ln`:$col" }
    if ($null -eq $hit[0].qualified_name) { return 'NULL' }
    return [string]$hit[0].qualified_name
  }
  function Expect($id, $mark, $text, $kind, $name, $want) {
    $got = At $mark $text $kind $name
    $ok = if ($null -eq $want) { $got -eq 'NULL' } else { $got -eq $want }
    Check $id $ok "$text -> $got"
  }

  Write-Host "T3 G4 dotted type_use + routine-local typed const receiver ($Exe)"
  Expect 'D1' 'V: uT3Types.TT3Runner' 'uT3Types.TT3Runner' 'type_use' 'TT3Runner' 'uT3Types.TT3Runner'
  Expect 'D2' 'Y: uT3Use.TT3Runner'   'uT3Use.TT3Runner'   'type_use' 'TT3Runner' 'uT3Use.TT3Runner'
  Expect 'L1' 'CLocal.Alpha'          'CLocal.Alpha'       'member-access' 'Alpha' 'uT3Types.TT3Rec.Alpha'
  Expect 'L2' 'CLocal.Beta'           'CLocal.Beta'        'member-access' 'Beta'  'uT3Types.TT3Rec.Beta'
  Expect 'L3' 'COuter.Alpha'          'COuter.Alpha'       'member-access' 'Alpha' 'uT3Types.TT3Rec.Alpha'
  Expect 'C1' 'W: TT3Runner'          'W: TT3Runner'       'type_use' 'TT3Runner' 'uT3Use.TT3Runner'
  Expect 'C2' 'R.Alpha'               'R.Alpha'            'member-access' 'Alpha' 'uT3Types.TT3Rec.Alpha'
  Expect 'C3' 'CUnit.Beta'            'CUnit.Beta'         'member-access' 'Beta'  'uT3Types.TT3Rec.Beta'
  Expect 'N1' 'X: NoSuchUnit.TT3Rec'  'NoSuchUnit.TT3Rec'  'type_use' 'TT3Rec' $null
  Expect 'N2' 'Z: TT3Rec.TT3Rec'      'TT3Rec.TT3Rec'      'type_use' 'TT3Rec' $null
}
finally {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
