$exe = (Resolve-Path "third_party\dll-win64\drag-lint.exe").Path
$fx  = (Resolve-Path "tests\ergonomics\threshold_fixture.pas").Path
$cfg = (Resolve-Path "tests\ergonomics\threshold_config.json").Path
# Default thresholds: 4 params is under 7 -> no too-many-parameters finding.
$base = & $exe lint $fx --rule too-many-parameters 2>$null | Out-String
# With config lowering to 3: 4 params trips it.
$low  = & $exe lint $fx --rule too-many-parameters --config $cfg 2>$null | Out-String
$ok1 = ($base -notmatch 'too-many-parameters')
$ok2 = ($low  -match    'too-many-parameters')
if ($ok1 -and $ok2) { Write-Host "PASS threshold config flips finding on"; exit 0 }
Write-Host "FAIL  base='$base'  low='$low'"; exit 1
