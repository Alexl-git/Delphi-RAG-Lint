<#
  run_convert_apply_batch.ps1 -- convert-apply takes --unit more than once and
  converts every unit in ONE process (C13 b2, owner ruling 2026-10-06; 1.23.0).

  WHY. Each convert-apply process rebuilt the rule book's member cache from
  scratch: measured ~33 s per unit on DMTEST (BDE-to-FireDAC.rules, 33 classes)
  whatever the unit's instance count. A batch validates the book once and
  resolves every class's members once.

  THE CONTRACT this guard pins (the converter reads exactly this):
    * info --json: capabilities.batch_units is the JSON literal true.
    * ONE --unit: output unchanged -- a bare apply/1 document.
    * 2+ --unit, JSON: ONE document, schema apply-batch/1:
        mode, rules_file, units_count, ok (every unit ok), exit_code (worst
        unit), ok_count, refused_count, failed_count, classes_built (the run's
        total), units[] -- one apply/1 object per unit, in --unit order.
    * each units[i] equals the single-unit run of that unit, except
      nothing -- classes_built included: per unit it is that unit's own (the
      book's validation set plus what its run added); the batch total is the
      wrapper's.
    * the book's classes are resolved ONCE: a 2-unit batch's classes_built
      equals one unit's (the cost model the batch exists for).
    * a unit that is refused, or fails, never stops the others; the process
      exit code is the worst unit's (2 > 1 > 0); --apply writes only the units
      that succeeded.
    * text: one '=== unit i of N: <path> ===' section per unit holding that
      unit's normal output, then 'batch: N unit(s) -- a ok, b refused, c
      failed; classes_built K; exit E'.

  Fixtures: tests\autotest\fixtures\unitrules, COPIED to a $PID scratch folder
  and indexed there. Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_batch_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures\unitrules\*') $WorkDir

$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db)

function P([string]$n) { return (Join-Path $WorkDir $n) }
function Hash([string]$n) { return (Get-FileHash (P $n)).Hash }
function Run([string[]]$Units, [string]$Rules, [string[]]$Extra = @()) {
  $a = @('convert-apply')
  foreach ($u in $Units) { $a += @('--unit', (P $u)) }
  $a += @('--rules', (P $Rules), '--db', $db) + $Extra
  $o = (& $Exe @a 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
# an apply/1 object as comparable text -- every key, classes_built included
function Shape($o) {
  if ($null -eq $o) { return '<null>' }
  $c = $o | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  return ($c | ConvertTo-Json -Depth 8 -Compress)
}

# ---- capability -------------------------------------------------------------
$j = Json ((& $Exe info --json 2>&1) -join "`n")
Check 'C1 info --json: capabilities.batch_units is JSON true' `
  (($null -ne $j) -and ($j.capabilities.batch_units -is [bool]) -and ($j.capabilities.batch_units -eq $true)) `
  "capabilities = $(if ($j) { $j.capabilities | ConvertTo-Json -Compress } else { '<no json>' })"

# ---- one --unit: unchanged apply/1 -----------------------------------------
$sA = Run @('MixForm.pas') 'mixed.rules' @('--format', 'json')
$jA = Json $sA.Out
$sB = Run @('R26Form.pas') 'mixed.rules' @('--format', 'json')
$jB = Json $sB.Out
Check 'S1 single --unit still emits a bare apply/1 (exit 0)' (($sA.Code -eq 0) -and ($null -ne $jA) -and ($jA.schema -eq 'apply/1')) $sA.Out
Check 'S2 single control for the second unit (exit 0, apply/1)' (($sB.Code -eq 0) -and ($null -ne $jB) -and ($jB.schema -eq 'apply/1')) $sB.Out

# ---- 2 units, JSON dry run --------------------------------------------------
$r = Run @('MixForm.pas', 'R26Form.pas') 'mixed.rules' @('--format', 'json')
$j = Json $r.Out
Check 'B1 batch json: exit 0, ONE document, schema apply-batch/1' (($r.Code -eq 0) -and ($null -ne $j) -and ($j.schema -eq 'apply-batch/1')) $r.Out
Check 'B2 wrapper keys: mode dry-run, units_count 2, ok true, exit_code 0, ok/refused/failed 2/0/0' `
  (($null -ne $j) -and ($j.mode -eq 'dry-run') -and ($j.units_count -eq 2) -and ($j.ok -eq $true) -and ($j.exit_code -eq 0) -and `
   ($j.ok_count -eq 2) -and ($j.refused_count -eq 0) -and ($j.failed_count -eq 0) -and ($j.rules_file -eq (P 'mixed.rules'))) $r.Out
Check 'B3 units[] are apply/1 objects in --unit order' `
  (($null -ne $j) -and (@($j.units).Count -eq 2) -and ($j.units[0].schema -eq 'apply/1') -and ($j.units[0].unit -eq (P 'MixForm.pas')) -and ($j.units[1].unit -eq (P 'R26Form.pas'))) $r.Out
Check 'B4 units[0] equals the single run of MixForm.pas (classes_built included)' ((Shape $j.units[0]) -eq (Shape $jA)) "batch=$(Shape $j.units[0])`nsingle=$(Shape $jA)"
Check 'B5 units[1] equals the single run of R26Form.pas (classes_built included)' ((Shape $j.units[1]) -eq (Shape $jB)) "batch=$(Shape $j.units[1])`nsingle=$(Shape $jB)"
Check 'B6 the book''s classes are resolved ONCE: batch classes_built = one unit''s, not the sum' `
  (($null -ne $j) -and ($jA.classes_built -gt 0) -and ($j.classes_built -eq $jA.classes_built) -and ($jA.classes_built -eq $jB.classes_built)) `
  "batch=$($j.classes_built) singleA=$($jA.classes_built) singleB=$($jB.classes_built)"

# ---- a refusal and a failure do not stop the others; exit = worst ----------
$hS = Hash 'SwapIntf.pas'; $hI = Hash 'Ifdef.pas'
$r = Run @('SwapIntf.pas', 'Ifdef.pas', 'NoSuchUnit.pas') 'swap.rules' @('--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
Check 'R1 mixed batch --apply: exit 2 (the missing unit is the worst), ok=false' (($r.Code -eq 2) -and ($null -ne $j) -and ($j.ok -eq $false) -and ($j.exit_code -eq 2)) $r.Out
Check 'R2 counts: ok 1, refused 1, failed 1' (($null -ne $j) -and ($j.ok_count -eq 1) -and ($j.refused_count -eq 1) -and ($j.failed_count -eq 1)) $r.Out
Check 'R3 units[1] is the Ifdef refusal (refused=true, reason names the conditional region)' `
  (($null -ne $j) -and ($j.units[1].refused -eq $true) -and ($j.units[1].reason -match 'conditional')) $r.Out
Check 'R4 units[2] is the missing unit (ok=false, refused=false, error names it)' `
  (($null -ne $j) -and ($j.units[2].ok -eq $false) -and ($j.units[2].refused -eq $false) -and ($j.units[2].error -match 'unit not found: .*NoSuchUnit\.pas')) $r.Out
Check 'R5 SwapIntf.pas WAS converted (the refusal after it did not undo or block it)' ((Hash 'SwapIntf.pas') -ne $hS)
Check 'R6 Ifdef.pas is byte-identical' ((Hash 'Ifdef.pas') -eq $hI)

# ---- text mode ---------------------------------------------------------------
$r = Run @('NoOld.pas', 'Ifdef.pas') 'swap.rules'
Check 'T1 text batch: exit 1 (worst = the refusal)' ($r.Code -eq 1) $r.Out
Check 'T2 one section header per unit, in order' `
  (($r.Out -match ('(?m)^=== unit 1 of 2: ' + [regex]::Escape((P 'NoOld.pas')) + ' ===\r?$')) -and `
   ($r.Out -match ('(?m)^=== unit 2 of 2: ' + [regex]::Escape((P 'Ifdef.pas')) + ' ===\r?$')) -and `
   ($r.Out.IndexOf('=== unit 1 of 2') -lt $r.Out.IndexOf('=== unit 2 of 2'))) $r.Out
Check 'T3 the refusal sits in unit 2''s section as its REFUSED line' `
  (($r.Out -match '(?m)^REFUSED: .*conditional') -and ($r.Out.IndexOf('REFUSED:') -gt $r.Out.IndexOf('=== unit 2 of 2'))) $r.Out
Check 'T4 summary line: 2 unit(s) -- 1 ok, 1 refused, 0 failed; exit 1' `
  ($r.Out -match '(?m)^batch: 2 unit\(s\) -- 1 ok, 1 refused, 0 failed; classes_built \d+; exit 1\r?$') $r.Out

# ---- a unit that cannot be WRITTEN fails alone; the batch completes --------
# R26Form.pas is read-only: the write pre-check fails that unit (ok=false,
# refused=false, exit 2) BEFORE any byte, backup or recovery record is written;
# units 1 and 3 convert, and the apply-batch/1 document is whole.
$ro = P 'R26Form.pas'
$hP = Hash 'R26Form.pas'; $hD = Hash 'R26Form.dfm'
try {
  Set-ItemProperty -LiteralPath $ro -Name IsReadOnly -Value $true
  $r = Run @('MixForm.pas', 'R26Form.pas', 'R26Other.pas') 'r26convert.rules' @('--apply', '--format', 'json')
  $j = Json $r.Out
  Check 'W1 read-only unit 2: exit 2 (worst), ONE apply-batch/1 with 3 units: ok 2, refused 0, failed 1' `
    (($r.Code -eq 2) -and ($null -ne $j) -and ($j.schema -eq 'apply-batch/1') -and (@($j.units).Count -eq 3) -and `
     ($j.ok_count -eq 2) -and ($j.refused_count -eq 0) -and ($j.failed_count -eq 1) -and ($j.exit_code -eq 2)) $r.Out
  Check 'W2 units[1]: ok=false, refused=false, error names the file and read-only' `
    (($null -ne $j) -and ($j.units[1].ok -eq $false) -and ($j.units[1].refused -eq $false) -and `
     ($j.units[1].error -match ('^cannot write ' + [regex]::Escape($ro) + ': the file is read-only -- unit not changed, nothing written$'))) $r.Out
  Check 'W3 R26Form.pas and .dfm byte-identical, no R26Form backup written' `
    (((Hash 'R26Form.pas') -eq $hP) -and ((Hash 'R26Form.dfm') -eq $hD) -and (@(Get-ChildItem $WorkDir -Filter 'R26Form.*.BCK*').Count -eq 0)) `
    (@(Get-ChildItem $WorkDir -Filter 'R26Form.*') | ForEach-Object Name) -join ', '
  Check 'W4 units 1 and 3 converted and written (MixForm, R26Other retyped)' `
    (([IO.File]::ReadAllText((P 'MixForm.pas')) -match 'btnTop: TDstBtn;') -and ([IO.File]::ReadAllText((P 'R26Other.pas')) -match 'btnOne: TDstBtn;')) $r.Out
} finally {
  if (Test-Path -LiteralPath $ro) { Set-ItemProperty -LiteralPath $ro -Name IsReadOnly -Value $false }
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($f23 in @(Get-ChildItem "C:\TEMP\draglint_convert_apply_batch_$PID" -File -ErrorAction SilentlyContinue)) { $f23.IsReadOnly = $false }
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_batch_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
