# B-02 guard: library-drift must not report a root the indexer's own walk filter
# prunes (manifest "exclude": ["Win64"]) as "missing". Before the fix, the four
# Win64 compiled-lib roots (...\Lib\RX13\Win64, ...\Library\RS37\Win64) stayed
# "missing" after every full rescan: the walker prunes a dir whose BASE NAME
# matches an exclude glob -- the root itself included -- so nothing under them
# can ever be indexed, and drift reported config as drift.
# Positive controls: the same root WITHOUT the exclude, and with a non-matching
# exclude, is still reported MISSING -- so the negative check cannot pass with
# the drift check simply switched off.
. "$PSScriptRoot\_manifest_common.ps1"
try {
$work  = Join-Path $env:TEMP "ldx_$PID"
$libW  = Join-Path $work 'Lib\Win64'
New-Item -ItemType Directory -Force -Path $libW | Out-Null
[IO.File]::WriteAllText((Join-Path $libW 'uLibForm.dfm'), "object LibForm: TLibForm`r`nend`r`n", [Text.Encoding]::ASCII)
$rootA = "$PSScriptRoot\..\fixtures\reconcile"
$db    = Join-Path $work 'drift.sqlite'
& $Exe index "$rootA" --db $db 2>&1 | Out-Null
Check 'index rootA exits 0' ($LASTEXITCODE -eq 0)

# Premise: the real walker prunes the root itself when its base name matches.
$db2 = Join-Path $work 'walk.sqlite'
& $Exe index "$libW" --db $db2 --exclude Win64 2>&1 | Out-Null
$n = (& $Exe selftest files --db $db2 2>&1 | Where-Object { $_ -match 'uLibForm' }).Count
Check 'premise: walker indexes 0 files under an excluded root' ($n -eq 0) "(got $n)"

# Positive control 1: no exclude -> the root has source and no index rows -> MISSING.
$p1 = & $Exe selftest drift --db $db --root "$libW" 2>&1 | Out-String
Check 'control: root without --exclude is MISSING' ($p1 -match 'MISSING .*Win64') $p1.Trim()

# Positive control 2: an exclude that does not match the root changes nothing.
$p2 = & $Exe selftest drift --db $db --root "$libW" --exclude Win32 2>&1 | Out-String
Check 'control: non-matching --exclude still MISSING' ($p2 -match 'MISSING .*Win64') $p2.Trim()

# The bug: an excluded root is NOT drift; it is named as excluded instead.
$b1 = & $Exe selftest drift --db $db --root "$libW" --root "$rootA" --exclude Win64 2>&1 | Out-String
Check 'excluded root is not MISSING'     (-not ($b1 -match 'MISSING .*Win64')) $b1.Trim()
Check 'excluded root is named EXCLUDED'  ($b1 -match 'EXCLUDED .*Win64')
Check 'drift is clean with it excluded'  ($b1 -match 'DRIFT-OK')

# Glob form, case-insensitive, as the walker matches it.
$b2 = & $Exe selftest drift --db $db --root "$libW" --exclude 'wIN6?' 2>&1 | Out-String
Check 'glob exclude (case-insensitive) honoured' (($b2 -match 'EXCLUDED .*Win64') -and ($b2 -match 'DRIFT-OK')) $b2.Trim()

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if ($work -and (Test-Path -LiteralPath $work)) { [IO.Directory]::Delete($work, $true) }
}
