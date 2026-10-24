<#
  run_rules_loader_dedupe.ps1 -- the .scm rule loader (TQueryRuleLoader.LoadAll) must
  load each rule ONCE (e3d small-1 a).

  THE DEFECT: LoadAll walks <exe-dir>\rules RECURSIVELY and never deduped, so a nested
  rules\rules\ copy (xcopy into an existing rules dir) ran every rule twice. `lint`
  hides it (FinalizeAndOutput drops exact duplicates); the LSP gutter showed both.

  THE SPEC:
    A  nested rules\rules\ copy      -> skipped silently: no RULE-DUPLICATE-ID, 1 finding
    B  stray same-id same-name copy  -> rules\stray\with-statement.scm: first path (sorted)
                                        wins (ordinal order), ONE RULE-DUPLICATE-ID warning on stderr naming
                                        the ignored path, 1 finding
    C  POSITIVE CONTROL: a genuinely new rule (new id) in a subfolder still loads and fires
    D  one id spanning two files (hardcoded-credential const + assignment forms) is NOT
       a duplicate: no warning for it in the unmodified rules dir
  Runs a COPY of the engine in scratch; never touches the real rules dir.
#>
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
      [string]$Companions = "$PSScriptRoot\..\..\third_party\dll-win64",
      [string]$Rules = "$PSScriptRoot\..\..\rules")
$ErrorActionPreference = 'Stop'
$script:fail = 0
function Check($name, $ok, $detail) {
  if ($ok) { Write-Host "  PASS  $name" -ForegroundColor Green }
  else { Write-Host "  FAIL  $name  $detail" -ForegroundColor Red; $script:fail++ }
}
$Work = Join-Path ([IO.Path]::GetTempPath()) ("rules-dedupe-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force $Work | Out-Null
$Fix = Join-Path $Work 't.pas'
[IO.File]::WriteAllText($Fix, "unit T;`r`ninterface`r`nimplementation`r`nprocedure P; begin`r`n  with X do Free;`r`nend;`r`nend.`r`n")

function New-Engine($name) {
  $e = Join-Path $Work $name
  New-Item -ItemType Directory -Force $e | Out-Null
  Copy-Item $Exe $e -Force
  $own = Join-Path (Split-Path $Exe) '*.dll'
  if (Test-Path $own) { Copy-Item $own $e -Force }
  Copy-Item (Join-Path $Companions 'tree-sitter*.dll'), (Join-Path $Companions 'sqlite3.dll') $e -Force
  New-Item -ItemType Directory -Force (Join-Path $e 'rules') | Out-Null
  Copy-Item (Join-Path $Rules '*') (Join-Path $e 'rules') -Recurse -Force
  $e
}
function Run-Lint($e) {
  $err = Join-Path $Work 'err.txt'
  $out = & (Join-Path $e (Split-Path $Exe -Leaf)) lint $Fix --json 2>$err
  $json = ($out | Where-Object { $_ -notmatch '^\(loaded defaults' }) -join "`n"
  $f = @(); if ($json.Trim()) { $f = @($json | ConvertFrom-Json) }
  [pscustomobject]@{ Findings = $f; Err = @((@(Get-Content $err -ErrorAction SilentlyContinue) -join ' ') -split '(?=RULE-DUPLICATE-ID)' | Where-Object { $_.Trim() }) }
}
function Dups($r) { @($r.Err | Where-Object { $_ -match 'RULE-DUPLICATE-ID' }) }

try {
  Write-Host 'A nested rules\rules\ copy' -ForegroundColor Cyan
  $e = New-Engine 'a'
  New-Item -ItemType Directory -Force (Join-Path $e 'rules\rules') | Out-Null
  Copy-Item (Join-Path $Rules '*') (Join-Path $e 'rules\rules') -Recurse -Force   # the xcopy-into-existing shape
  Check 'SETUP: nested copy present' ((Test-Path (Join-Path $e 'rules\rules\with-statement.scm'))) ''
  $r = Run-Lint $e
  Check 'A: 1 with-statement finding' (@($r.Findings | Where-Object rule -eq 'with-statement').Count -eq 1) "got $(@($r.Findings).Count)"
  Check 'A: nested copy skipped silently (no warning)' ((Dups $r).Count -eq 0) ((Dups $r) -join ' | ')

  Write-Host 'B stray same-id same-name copy' -ForegroundColor Cyan
  $e = New-Engine 'b'
  $stray = Join-Path $e 'rules\stray'
  New-Item -ItemType Directory -Force $stray | Out-Null
  Copy-Item (Join-Path $Rules 'with-statement.*') $stray -Force
  $r = Run-Lint $e
  $d = @(Dups $r)
  Check 'B: exactly one RULE-DUPLICATE-ID warning' ($d.Count -eq 1) "got $($d.Count)"
  Check 'B: warning names the ignored path and the kept one' ($d.Count -eq 1 -and $d[0] -match 'with-statement\.scm\s+ignored\s+\(already\s+loaded\s+from\s+.*stray') ($d -join ' | ')
  Check 'B: 1 with-statement finding' (@($r.Findings | Where-Object rule -eq 'with-statement').Count -eq 1) ''

  Write-Host 'C positive control: a new rule in a subfolder still loads' -ForegroundColor Cyan
  $e = New-Engine 'c'
  $sub = Join-Path $e 'rules\extra'
  New-Item -ItemType Directory -Force $sub | Out-Null
  [IO.File]::WriteAllText((Join-Path $sub 'zz-new-with.scm'), [IO.File]::ReadAllText((Join-Path $Rules 'with-statement.scm')))
  $j = [IO.File]::ReadAllText((Join-Path $Rules 'with-statement.json')) -replace '"id"\s*:\s*"with-statement"', '"id": "zz-new-with"'
  [IO.File]::WriteAllText((Join-Path $sub 'zz-new-with.json'), $j)
  $r = Run-Lint $e
  Check 'C: the new rule fires' (@($r.Findings | Where-Object rule -eq 'zz-new-with').Count -eq 1) "rules: $(@($r.Findings.rule) -join ',')"
  Check 'C: the original still fires' (@($r.Findings | Where-Object rule -eq 'with-statement').Count -eq 1) ''
  Check 'C: no duplicate warning' ((Dups $r).Count -eq 0) ((Dups $r) -join ' | ')

  Write-Host 'D unmodified rules dir' -ForegroundColor Cyan
  $e = New-Engine 'd'
  $r = Run-Lint $e
  Check 'D: no RULE-DUPLICATE-ID in the shipped rules (multi-form ids are not duplicates)' ((Dups $r).Count -eq 0) ((Dups $r) -join ' | ')
}
finally {
  [IO.Directory]::Delete($Work, $true)
}
if ($script:fail) { Write-Host "FAIL: $script:fail check(s)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS: rules loader dedupe' -ForegroundColor Green