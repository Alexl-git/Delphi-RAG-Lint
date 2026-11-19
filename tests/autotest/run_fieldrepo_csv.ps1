<#
  run_fieldrepo_csv.ps1 -- lane TTCSV acceptance: builds tests\fieldrepo\CsvMemTableTests.dpr and runs it
  against tests\fieldrepo\csvmemtable (sample.csv + golden.pas.txt). Exit 0 = all PASS.
  -OutDir: where the build log lives (default: $env:TEMP).
#>
param([string]$OutDir = $env:TEMP)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$log = Join-Path $OutDir 'fieldrepo_csv_build.log'
$bat = Join-Path $root 'build\_build_fieldrepo_csv_tests_local.bat'
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$bat`"" -RedirectStandardOutput $log -Wait -PassThru -WindowStyle Hidden; $null = $p.Handle
if (-not (Select-String -Path $log -Pattern 'BUILD_EXITCODE=0' -Quiet)) {
  Write-Host 'FAIL build'; Select-String -Path $log -Pattern 'Error|Fatal' | Select-Object -First 10 | ForEach-Object { $_.Line }
  exit 1
}
$exe = Join-Path $root 'tests\fieldrepo\CsvMemTableTests.exe'
$out = & $exe (Join-Path $root 'tests\fieldrepo\csvmemtable')
$out | ForEach-Object { Write-Host $_ }
$fails = @($out | Where-Object { $_ -like 'FAIL*' }).Count
Write-Host ("fieldrepo-csv: {0} passed, {1} failed" -f @($out | Where-Object { $_ -like 'PASS*' }).Count, $fails)
if ($fails -gt 0 -or $LASTEXITCODE -ne 0) { exit 1 }
exit 0
