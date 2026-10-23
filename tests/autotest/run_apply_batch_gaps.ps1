<#
  run_apply_batch_gaps.ps1 -- convert-apply batch gaps G1 / G2 / G3 reported by
  CONVERTER on 1.33.0-alpha-20261021 (plan 2026-10-23-converter-b4-batch-mode.md
  section 5), fixed in 1.33.0 (e3d/apply-batch).

  G2 (defect). A unit that NO supplied --db indexes converted nothing and still
  reported ok:true, edits_count 0, counted in ok_count. Measured on this branch
  before the fix: the SINGLE-unit run did exactly the same (ok, exit 0, even
  under --apply) -- nothing refused it in either mode. Ruling (same as C13 d,
  "a type no --db resolves is an index gap"): the unit is REFUSED, dry run and
  --apply alike, single and batch alike -- reason names the index precondition
  ('not covered by any supplied --db', the wording
  run_convert_apply_index_precondition.ps1 already pins). In a batch the other
  units are untouched by it (a refusal never stops the others).

  G1 (ask). convert-apply --progress writes ONE JSON line per finished unit to
  STDERR, flushed as the unit ends:
    {"progress":{"verb":"convert-apply","unit_done":i,"units":N,"unit":"<path>",
                 "ok":true|false,"refused":true|false,"exit_code":E}}
  OFF by default (a caller merging the streams slices '{'..'}' -- see
  MakeProgressWriter). stdout is byte-identical with and without it.
  Advertised as info capability batch_progress (JSON literal true).

  G3 (minor). Every apply/1 object carries exit_code -- that unit's exit code
  (in a batch, units[i].exit_code; a single run, the process exit code).

  Positive controls: an INDEXED unit converts (ok, edits > 0) in the same run;
  stdout without --progress is compared to stdout with it; stderr without
  --progress carries no progress line.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_apply_batch_gaps_$PID"
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

# LooseForm = MixForm renamed, written AFTER the index: on disk, in no --db.
foreach ($e in @('pas', 'dfm')) {
  $t = [IO.File]::ReadAllText((P "MixForm.$e")) -replace 'MixForm', 'LooseForm'
  [IO.File]::WriteAllText((P "LooseForm.$e"), $t, [Text.Encoding]::ASCII)
}

$errFile = Join-Path $WorkDir 'stderr.txt'
# stdout and stderr captured APART -- G1 is about which stream a line lands on
function Run([string[]]$Units, [string[]]$Extra = @()) {
  $a = @('convert-apply')
  foreach ($u in $Units) { $a += @('--unit', (P $u)) }
  $a += @('--rules', (P 'mixed.rules'), '--db', $db, '--format', 'json') + $Extra
  $o = (& $Exe @a 2> $errFile) -join "`n"
  $code = $LASTEXITCODE
  $e = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  $j = $null
  try { $j = $o | ConvertFrom-Json } catch { $j = $null }
  return [pscustomobject]@{ Code = $code; Out = $o; Err = $e; J = $j }
}
function ProgressLines([string]$s) {
  return @($s -split "`r?`n" | Where-Object { $_ -match '^\{"progress":' } | ForEach-Object { ($_ | ConvertFrom-Json).progress })
}
$PRECOND = 'not covered by any supplied --db'

# ---- capability -------------------------------------------------------------
$ij = $null
try { $ij = ((& $Exe info --json 2>$null) -join "`n") | ConvertFrom-Json } catch { $ij = $null }
Check 'C1 info --json: capabilities.batch_progress is JSON true' `
  (($null -ne $ij) -and ($ij.capabilities.batch_progress -is [bool]) -and ($ij.capabilities.batch_progress -eq $true)) `
  "capabilities = $(if ($ij) { $ij.capabilities | ConvertTo-Json -Compress } else { '<no json>' })"

# ---- G2 single --------------------------------------------------------------
$pc = Run @('MixForm.pas')
Check 'P1 POSITIVE CONTROL an indexed unit converts (exit 0, ok, edits > 0)' `
  (($pc.Code -eq 0) -and ($null -ne $pc.J) -and ($pc.J.ok -eq $true) -and ($pc.J.edits_count -gt 0)) $pc.Out
$s1 = Run @('LooseForm.pas')
Check 'G2a single dry run: an unindexed unit is REFUSED (exit 1, ok=false, refused=true)' `
  (($s1.Code -eq 1) -and ($null -ne $s1.J) -and ($s1.J.ok -eq $false) -and ($s1.J.refused -eq $true)) $s1.Out
Check 'G2b the reason names the index precondition' `
  (($null -ne $s1.J) -and ($s1.J.reason -match [regex]::Escape($PRECOND)) -and ($s1.J.reason -match 'LooseForm\.pas')) $s1.Out
Check 'G2c a refused unit plans nothing (edits_count 0)' (($null -ne $s1.J) -and ($s1.J.edits_count -eq 0)) $s1.Out

# ---- G2 batch, dry run ------------------------------------------------------
$b = Run @('MixForm.pas', 'LooseForm.pas')
$j = $b.J
Check 'G2d batch: exit 1, ok=false, ok 1 / refused 1 / failed 0' `
  (($b.Code -eq 1) -and ($null -ne $j) -and ($j.schema -eq 'apply-batch/1') -and ($j.ok -eq $false) -and ($j.exit_code -eq 1) -and `
   ($j.ok_count -eq 1) -and ($j.refused_count -eq 1) -and ($j.failed_count -eq 0)) $b.Out
Check 'G2e batch units[1] is the same refusal as the single run' `
  (($null -ne $j) -and ($j.units[1].refused -eq $true) -and ($j.units[1].reason -eq $s1.J.reason)) $b.Out
Check 'P2 POSITIVE CONTROL batch units[0] (indexed) still converts' `
  (($null -ne $j) -and ($j.units[0].ok -eq $true) -and ($j.units[0].edits_count -eq $pc.J.edits_count)) $b.Out

# ---- G3 exit_code -----------------------------------------------------------
Check 'G3a single apply/1 carries exit_code = the process exit code (0 and 1)' `
  (($pc.J.exit_code -is [long] -or $pc.J.exit_code -is [int]) -and ($pc.J.exit_code -eq 0) -and ($s1.J.exit_code -eq 1)) `
  "ok=$($pc.J.exit_code) refused=$($s1.J.exit_code)"
Check 'G3b batch units[i].exit_code: 0 for the ok unit, 1 for the refusal' `
  (($null -ne $j) -and ($j.units[0].exit_code -eq 0) -and ($j.units[1].exit_code -eq 1)) $b.Out

# ---- G1 progress ------------------------------------------------------------
Check 'G1a without --progress: no progress line on stderr' (@(ProgressLines $b.Err).Count -eq 0) $b.Err
$bp = Run @('MixForm.pas', 'LooseForm.pas') @('--progress')
$pl = @(ProgressLines $bp.Err)
Check 'G1b --progress: exactly one stderr line per unit (2)' ($pl.Count -eq 2) $bp.Err
Check 'G1c lines name verb, unit_done 1..N, units N, unit path in --unit order' `
  (($pl.Count -eq 2) -and ($pl[0].verb -eq 'convert-apply') -and ($pl[0].unit_done -eq 1) -and ($pl[1].unit_done -eq 2) -and `
   ($pl[0].units -eq 2) -and ($pl[0].unit -eq (P 'MixForm.pas')) -and ($pl[1].unit -eq (P 'LooseForm.pas'))) $bp.Err
Check 'G1d lines carry ok / refused / exit_code per unit' `
  (($pl.Count -eq 2) -and ($pl[0].ok -eq $true) -and ($pl[0].exit_code -eq 0) -and ($pl[1].ok -eq $false) -and `
   ($pl[1].refused -eq $true) -and ($pl[1].exit_code -eq 1)) $bp.Err
Check 'G1e stdout is byte-identical with and without --progress (exit identical)' (($bp.Out -eq $b.Out) -and ($bp.Code -eq $b.Code)) `
  "with=$($bp.Out.Length) without=$($b.Out.Length)"
Check 'G1f --progress never writes a progress line to stdout' (-not ($bp.Out -match '"progress"')) $bp.Out

# ---- G2 batch --apply: the refused unit is untouched, the other written ------
$hM = Hash 'MixForm.pas'; $hL = Hash 'LooseForm.pas'
$ba = Run @('MixForm.pas', 'LooseForm.pas') @('--apply', '--no-backup', '--no-reindex')
Check 'G2f batch --apply: exit 1, refused_count 1' (($ba.Code -eq 1) -and ($null -ne $ba.J) -and ($ba.J.refused_count -eq 1)) $ba.Out
Check 'G2g LooseForm.pas is byte-identical (refused, nothing written)' ((Hash 'LooseForm.pas') -eq $hL)
Check 'P3 POSITIVE CONTROL MixForm.pas WAS written' ((Hash 'MixForm.pas') -ne $hM)

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_apply_batch_gaps_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
