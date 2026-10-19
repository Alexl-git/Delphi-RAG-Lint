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
if ($Filter -eq 'test_*.ps1') {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Host 'SKIP node not found (releases.test.js)'
    } else {
        $total++
        $out = & $node.Source --test (Join-Path $PSScriptRoot 'releases.test.js') 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Host 'PASS releases.test.js' }
        else { $failed++; Write-Host 'FAIL releases.test.js'; $out | Select-Object -Last 20 | Write-Host }
    }
}
Write-Host "total=$total failed=$failed"
if ($failed -gt 0) { exit 1 }
