. "$PSScriptRoot\_manifest_common.ps1"
$fx = "$PSScriptRoot\..\fixtures\coverage"
$c = & $Exe selftest coverage --config "$fx\cov.drag-lint.json" --root "$fx\tree" 2>$null | Out-String
Check 'inA indexed by A'   ($c -match 'inA\s+indexed\s+A')
Check 'inB indexed by B'   ($c -match 'inB\s+indexed\s+B')
Check 'copy excluded'      ($c -match 'oldstuff - Copy\s+excluded')
Check 'unassigned flagged' ($c -match 'unassigned\s+unassigned')
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
