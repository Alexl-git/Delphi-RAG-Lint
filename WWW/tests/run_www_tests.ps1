# Runs every tests\test_*.ps1 in its own scope; exit 1 if any file fails.
param([string]$Filter = 'test_*.ps1')
$ErrorActionPreference = 'Stop'
$total = 0; $failed = 0
foreach ($f in Get-ChildItem $PSScriptRoot -Filter $Filter | Sort-Object Name) {
    $total++
    try {
        & {
            . (Join-Path $PSScriptRoot 'Assert.ps1')
            . $f.FullName
        }
        Write-Host "PASS $($f.Name)"
    } catch {
        $failed++
        Write-Host "FAIL $($f.Name): $($_.Exception.Message)"
    }
}
Write-Host "total=$total failed=$failed"
if ($failed -gt 0) { exit 1 }
