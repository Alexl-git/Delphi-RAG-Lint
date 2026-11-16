# Guard for the v1511 lane SCM rule fixes (1.51.1-alpha): B13 division-by-zero-literal (no div/mod 0 = dcc E2098;
# float message), Y1/R6 large-magic-number (case labels, enum ordinals, dispid), R3 inherited-bare (Destroy / Assign /
# AssignTo, then/else fallback), plus the B12 comment-fixer CRLF check. Reuses tests\lint\run_lint_tests.ps1 with a
# filter per fixture; the (+)/(-) expectations are the .expected files next to the fixtures.
param(
  [string]$Exe   = "third_party\dll-win64\drag-lint.exe",
  [string]$Rules = "rules"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$fail = 0
foreach ($f in 'division-by-zero-literal', 'large-magic-number-v1511', 'inherited-bare-v1511', 'inherited_bare', 'large-magic-number-v151', 'large-magic-number-exempt') {
  $out = & (Join-Path $repo 'tests\lint\run_lint_tests.ps1') -Exe $Exe -Rules $Rules -Filter $f *>&1
  $out | Where-Object { $_ -match 'PASS|FAIL|missing|should' } | ForEach-Object { Write-Host $_ }
  if (($out | Out-String) -cmatch 'FAIL  ') { $fail++ }
}
# division-by-zero-literal message must not claim an integer div/mod is covered.
$exe = (Resolve-Path $Exe).Path
$raw = & $exe lint (Join-Path $repo 'tests\lint\division-by-zero-literal.pas') --rule division-by-zero-literal --json 2>$null
$msg = (($raw | ConvertFrom-Json) | Select-Object -First 1).message
if ($msg -match "float") { Write-Host "PASS  message names the float / division form" } else { Write-Host "FAIL  message: $msg" -ForegroundColor Red; $fail++ }
# B12: a CRLF file's comment fixer applies (shared-marker-legacy-shape, risky opt-in).
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('v1511-scm-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
[IO.File]::WriteAllText((Join-Path $tmp 'Sm.pas'), "unit Sm;`r`ninterface`r`nconst`r`n  Legacy = 1;   // note // dl:shared A, B`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
$o = & $exe lint --in (Join-Path $tmp 'Sm.pas') --fix 2>&1 | Out-String
if ($o -match 'dl:shared A, B // note') { Write-Host "PASS  CRLF comment fixer applies" } else { Write-Host "FAIL  CRLF comment fixer declined: $o" -ForegroundColor Red; $fail++ }
if ($fail -gt 0) { Write-Host "FAILED: $fail" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS"
exit 0
